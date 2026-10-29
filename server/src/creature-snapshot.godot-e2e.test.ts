import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import type { WebSocket as WsSocket } from "ws";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";

// MYTHOS-NET-05: headless Godot 4.7.2 client against a REAL Fastify + PostgreSQL server.
// Needs a Godot binary: set GODOT_BIN. Set REQUIRE_GODOT_E2E=1 (CI does) to make a missing
// binary a FAILURE instead of a skip, so an unexecuted end-to-end test can never read as a pass.

const GODOT_BIN = process.env.GODOT_BIN ?? "";
const REQUIRED = process.env.REQUIRE_GODOT_E2E === "1";
const CREATURE_COUNT = 4000; // serialises to well over 1 MiB
const CUT_AFTER_FRAMES = 3;
const here = path.dirname(fileURLToPath(import.meta.url));
const clientRoot = path.resolve(here, "../../client-godot");

function runGodot(args: string[], timeoutMs: number): Promise<{ code: number | null; output: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn(GODOT_BIN, ["--headless", "--path", clientRoot, "--script", "res://tests/creature_snapshot_e2e.gd", "--", ...args], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    child.stdout.on("data", (chunk: Buffer) => { output += chunk.toString("utf8"); });
    child.stderr.on("data", (chunk: Buffer) => { output += chunk.toString("utf8"); });
    const timer = setTimeout(() => { child.kill("SIGKILL"); reject(new Error(`Godot timed out after ${timeoutMs} ms\n${output}`)); }, timeoutMs);
    child.on("error", (error) => { clearTimeout(timer); reject(error); });
    child.on("close", (code) => { clearTimeout(timer); resolve({ code, output }); });
  });
}

describe("creature snapshot: Godot client against real Fastify", () => {
  it("requires a Godot binary when REQUIRE_GODOT_E2E=1", () => {
    if (REQUIRED) {
      expect(GODOT_BIN, "GODOT_BIN must be set when REQUIRE_GODOT_E2E=1").not.toBe("");
      expect(existsSync(GODOT_BIN), `GODOT_BIN does not exist: ${GODOT_BIN}`).toBe(true);
    }
  });

  it.skipIf(!GODOT_BIN)("recovers a >1 MiB collection completely after a mid-snapshot connection cut", async () => {
    const app = await buildApp();
    const db = createDbPool();
    const unique = Date.now();
    let userId = "";
    try {
      const reg = await app.inject({
        method: "POST",
        url: "/auth/register",
        payload: { username: `e2e_${unique}`, email: `e2e_${unique}@example.com`, password: "Correct-Horse-Battery-9" },
      });
      expect(reg.statusCode).toBe(201);
      const body = JSON.parse(reg.body) as { accessToken: string; user: { id: string } };
      userId = body.user.id;

      await db.query(
        `INSERT INTO player_creatures (owner_user_id, wild_source_id, species, nickname, level, xp, health, max_health, attack, defense, element, ability_ids, tame_progress, ai_mode, x, y)
         SELECT $1, 'e2e-' || $2 || '-' || g, 'ember-drake', 'Pet ' || g, 1 + (g % 99), 12345, 100, 120, 30, 20, 'fire', '["ember-breath"]'::jsonb, 100, 'follow', g, -g
         FROM generate_series(1, $3) g`,
        [userId, String(unique), CREATURE_COUNT],
      );
      const ordered = await db.query<{ id: string }>(
        "SELECT id FROM player_creatures WHERE owner_user_id=$1 ORDER BY COALESCE(party_slot,999),created_at,id",
        [userId],
      );
      const ids = ordered.rows.map((row) => row.id);
      expect(ids).toHaveLength(CREATURE_COUNT);
      const expectedHash = createHash("sha256").update(ids.join("\n"), "utf8").digest("hex");

      // Cut the FIRST connection after a few creature frames (a real mid-snapshot drop).
      let connections = 0;
      let cutAtFrame = 0;
      app.websocketServer.on("connection", (socket: WsSocket) => {
        connections += 1;
        if (connections !== 1) return;
        const originalSend = socket.send.bind(socket) as (data: unknown, ...rest: unknown[]) => void;
        let creatureFrames = 0;
        (socket as unknown as { send: (data: unknown, ...rest: unknown[]) => void }).send = (data: unknown, ...rest: unknown[]) => {
          originalSend(data, ...rest);
          if (typeof data === "string" && /^\{"type":"creature_party(_page)?"/.test(data)) {
            creatureFrames += 1;
            if (creatureFrames === CUT_AFTER_FRAMES) { cutAtFrame = creatureFrames; socket.terminate(); }
          }
        };
      });

      await app.listen({ host: "127.0.0.1", port: 0 });
      const address = app.server.address();
      if (address === null || typeof address === "string") throw new Error("No test address");

      const result = await runGodot(
        [`ws://127.0.0.1:${address.port}/ws`, body.accessToken, String(CREATURE_COUNT), expectedHash],
        120000,
      );
      expect(result.output).toContain("NET05_E2E PASS");
      expect(result.code, result.output).toBe(0);
      expect(cutAtFrame).toBe(CUT_AFTER_FRAMES);
      expect(connections).toBeGreaterThanOrEqual(2);
    } finally {
      // Close the app first so its player persistence has flushed; deleting the user while
      // the server is still writing that player's rows deadlocks.
      await app.close();
      if (userId) await db.query("DELETE FROM users WHERE id=$1", [userId]);
      await db.end();
    }
  }, 150000);
});
