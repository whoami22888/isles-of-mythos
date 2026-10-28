import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { createDbPool } from "./db.js";
import { gatherResource } from "./resource-gathering.js";
import { generateChunk, type ResourceNode } from "./world.js";

// Real PostgreSQL. Covers the parallel paths the sequential tests do not: many players on one node, and many
// simultaneous retries of one request id. Hard validity lives in the transaction, not in anti-cheat scoring.
function findResource(skip = 0): ResourceNode {
  let seen = 0;
  for (let chunkY = -6; chunkY <= 6; chunkY += 1) {
    for (let chunkX = -6; chunkX <= 6; chunkX += 1) {
      for (const node of generateChunk(chunkX, chunkY).resources) {
        if (seen++ === skip) return node;
      }
    }
  }
  throw new Error("TEST_RESOURCE_NODE_NOT_FOUND");
}

async function createPlayer(db: ReturnType<typeof createDbPool>): Promise<string> {
  const unique = randomUUID().replace(/-/g, "").slice(0, 20);
  const user = await db.query<{ user_id: string }>(
    "INSERT INTO users(username,email,password_hash) VALUES($1,$2,$3) RETURNING id AS user_id",
    [`gcc_${unique}`, `gcc_${unique}@example.com`, "test"],
  );
  const userId = user.rows[0]?.user_id;
  if (!userId) throw new Error("TEST_PLAYER_NOT_CREATED");
  await db.query(
    "INSERT INTO player_profiles(user_id,inventory,hotbar,selected_hotbar_slot) VALUES($1,$2::jsonb,'[null,null,null,null,null,null,null,null]'::jsonb,0)",
    [userId, JSON.stringify({})],
  );
  return userId;
}

const total = (inventory: Record<string, number> | undefined) => Object.values(inventory ?? {}).reduce((a, b) => a + b, 0);

describe("resource gathering parallel authority", () => {
  it("lets exactly one of many concurrent players harvest a node", async () => {
    const db = createDbPool();
    const node = findResource(1);
    const players = await Promise.all(Array.from({ length: 8 }, () => createPlayer(db)));
    try {
      const results = await Promise.allSettled(
        players.map((id, i) => gatherResource(db, id, "race-" + i, "gather_resource|" + node.id, node)),
      );
      const ok = results.filter((r) => r.status === "fulfilled");
      expect(ok).toHaveLength(1);
      for (const r of results) {
        if (r.status === "rejected") expect(String(r.reason instanceof Error ? r.reason.message : r.reason)).toBe("RESOURCE_DEPLETED");
      }
      const rows = await db.query<{ user_id: string; inventory: Record<string, number> }>(
        "SELECT user_id,inventory FROM player_profiles WHERE user_id = ANY($1::uuid[])", [players]);
      expect(rows.rows.filter((row) => total(row.inventory) > 0)).toHaveLength(1);
      const ledger = await db.query("SELECT 1 FROM resource_gather_requests WHERE user_id = ANY($1::uuid[])", [players]);
      expect(ledger.rowCount).toBe(1);
    } finally {
      await db.query("DELETE FROM resource_gather_requests WHERE user_id = ANY($1::uuid[])", [players]);
      await db.query("DELETE FROM world_resource_nodes WHERE node_id=$1", [node.id]);
      await db.end();
    }
  });

  it("pays a request id once when it is replayed in parallel", async () => {
    const db = createDbPool();
    const node = findResource(2);
    const userId = await createPlayer(db);
    try {
      const results = await Promise.allSettled(
        Array.from({ length: 6 }, () => gatherResource(db, userId, "same-request", "gather_resource|" + node.id, node)),
      );
      // Every identical retry must replay the winner's result; none may be told the node is depleted.
      const failures = results.flatMap((r) => (r.status === "rejected" ? [String(r.reason)] : []));
      expect(failures).toEqual([]);
      const ok = results as PromiseFulfilledResult<Awaited<ReturnType<typeof gatherResource>>>[];
      expect(new Set(ok.map((r) => r.value.transactionId)).size).toBe(1);
      const player = await db.query<{ inventory: Record<string, number> }>("SELECT inventory FROM player_profiles WHERE user_id=$1", [userId]);
      expect(total(player.rows[0]?.inventory)).toBe(ok[0]?.value.quantity);
      const ledger = await db.query("SELECT 1 FROM resource_gather_requests WHERE user_id=$1", [userId]);
      expect(ledger.rowCount).toBe(1);
    } finally {
      await db.query("DELETE FROM resource_gather_requests WHERE user_id=$1", [userId]);
      await db.query("DELETE FROM world_resource_nodes WHERE node_id=$1", [node.id]);
      await db.end();
    }
  });
});
