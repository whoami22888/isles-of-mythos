import { describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";

// MYTHOS-NET-05: real Fastify + PostgreSQL + WebSocket. A collection well over 1 MiB must
// reach the client as bounded frames that reassemble to the complete owned collection,
// survive a connection cut mid-snapshot, and be re-sent paged after a party change.

const FRAME_LIMIT = 65536;
const CREATURE_COUNT = 4000;

interface Snapshot {
  frames: number;
  maxFrameBytes: number;
  totalBytes: number;
  ids: string[];
  total: number;
}

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);

function rawText(raw: unknown): string {
  if (Buffer.isBuffer(raw)) return raw.toString("utf8");
  if (Array.isArray(raw)) return Buffer.concat(raw as Buffer[]).toString("utf8");
  return Buffer.from(raw as ArrayBuffer).toString("utf8");
}

async function openAuthenticated(port: number, token: string) {
  const socket = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  await new Promise<void>((resolve, reject) => {
    socket.once("open", () => resolve());
    socket.once("error", reject);
  });
  socket.send(JSON.stringify({ type: "auth", token }));
  return socket;
}

// Collects frames until a snapshot is complete, or until `cutAfterFrames` frames when given.
function readSnapshot(socket: WebSocket, cutAfterFrames?: number): Promise<Snapshot & { cut: boolean }> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Timed out waiting for creature snapshot")), 20000);
    const snapshot: Snapshot = { frames: 0, maxFrameBytes: 0, totalBytes: 0, ids: [], total: 0 };
    let expectedPage = 0;
    let pageCount = 0;
    let snapshotId: unknown;
    socket.on("message", (raw) => {
      const text = rawText(raw);
      const message: unknown = JSON.parse(text);
      if (!isObj(message) || (message.type !== "creature_party" && message.type !== "creature_party_page")) return;
      const bytes = Buffer.byteLength(text, "utf8");
      snapshot.frames += 1;
      snapshot.maxFrameBytes = Math.max(snapshot.maxFrameBytes, bytes);
      snapshot.totalBytes += bytes;
      const creatures = message.creatures as { id: string }[];
      if (message.type === "creature_party") {
        expectedPage = 0;
        snapshotId = message.snapshotId;
        snapshot.ids = [];
      }
      expect(message.page).toBe(expectedPage);
      expect(message.snapshotId).toBe(snapshotId);
      pageCount = message.pageCount as number;
      snapshot.total = message.total as number;
      snapshot.ids.push(...creatures.map((c) => c.id));
      expectedPage += 1;
      if (cutAfterFrames !== undefined && snapshot.frames >= cutAfterFrames) {
        clearTimeout(timer);
        socket.terminate();
        resolve({ ...snapshot, cut: true });
        return;
      }
      if (expectedPage === pageCount) {
        clearTimeout(timer);
        resolve({ ...snapshot, cut: false });
      }
    });
    socket.once("error", reject);
  });
}

describe("creature snapshot over a real Fastify WebSocket", () => {
  it("delivers a >1 MiB collection as bounded frames, recovers after a mid-stream cut, and re-pages after a party change", async () => {
    const app = await buildApp();
    const db = createDbPool();
    const unique = Date.now();
    let userId = "";
    try {
      const reg = await app.inject({
        method: "POST",
        url: "/auth/register",
        payload: { username: `snap_${unique}`, email: `snap_${unique}@example.com`, password: "Correct-Horse-Battery-9" },
      });
      expect(reg.statusCode).toBe(201);
      const body = JSON.parse(reg.body) as { accessToken: string; user: { id: string } };
      userId = body.user.id;

      await db.query(
        `INSERT INTO player_creatures (owner_user_id, wild_source_id, species, nickname, level, xp, health, max_health, attack, defense, element, ability_ids, tame_progress, ai_mode, x, y)
         SELECT $1, 'snap-' || $2 || '-' || g, 'ember-drake', 'Pet ' || g, 1 + (g % 99), 12345, 100, 120, 30, 20, 'fire', '["ember-breath"]'::jsonb, 100, 'follow', g, -g
         FROM generate_series(1, $3) g`,
        [userId, String(unique), CREATURE_COUNT],
      );
      const expected = await db.query<{ id: string }>(
        "SELECT id FROM player_creatures WHERE owner_user_id=$1 ORDER BY COALESCE(party_slot,999),created_at,id",
        [userId],
      );
      const expectedIds = expected.rows.map((r) => r.id);
      expect(expectedIds).toHaveLength(CREATURE_COUNT);

      await app.listen({ host: "127.0.0.1", port: 0 });
      const address = app.server.address();
      if (address === null || typeof address === "string") throw new Error("No test address");

      // 1. Full snapshot: bounded frames, complete data.
      const first = await openAuthenticated(address.port, body.accessToken);
      const full = await readSnapshot(first);
      expect(full.totalBytes).toBeGreaterThan(1_048_576);
      expect(full.maxFrameBytes).toBeLessThanOrEqual(FRAME_LIMIT);
      expect(full.frames).toBeGreaterThan(20);
      expect(full.total).toBe(CREATURE_COUNT);
      expect([...full.ids].sort()).toEqual([...expectedIds].sort());
      first.close();

      // 2. Cut the connection mid-snapshot, reconnect, recover everything.
      const second = await openAuthenticated(address.port, body.accessToken);
      const partial = await readSnapshot(second, 3);
      expect(partial.cut).toBe(true);
      expect(partial.ids.length).toBeLessThan(CREATURE_COUNT);
      const third = await openAuthenticated(address.port, body.accessToken);
      const recovered = await readSnapshot(third);
      expect(recovered.cut).toBe(false);
      expect([...recovered.ids].sort()).toEqual([...expectedIds].sort());

      // 3. A party change re-sends the snapshot, paged and complete.
      const target = expectedIds[0];
      const repaged = readSnapshot(third);
      third.send(JSON.stringify({ type: "set_creature_party", requestId: "party-1", creatureId: target, slot: 0 }));
      const after = await repaged;
      expect(after.maxFrameBytes).toBeLessThanOrEqual(FRAME_LIMIT);
      expect(after.total).toBe(CREATURE_COUNT);
      expect([...after.ids].sort()).toEqual([...expectedIds].sort());
      expect(after.ids[0]).toBe(target); // party slot 0 sorts first
      third.close();
    } finally {
      // Close the app first so its player persistence has flushed; deleting the user while
      // the server is still writing that player's rows deadlocks.
      await app.close();
      if (userId) await db.query("DELETE FROM users WHERE id=$1", [userId]);
      await db.end();
    }
  }, 60000);
});
