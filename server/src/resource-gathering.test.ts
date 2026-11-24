import { randomUUID } from "node:crypto";
import { describe, expect, it, vi } from "vitest";
import { createDbPool } from "./db.js";
import { MAX_ITEM_STACK } from "./economy.js";
import { gatherResource } from "./resource-gathering.js";
import { createMutationTiming } from "./mutation-timing.js";
import { generateChunk, type ResourceNode } from "./world.js";

function findResource(): ResourceNode {
  for (let chunkY = -4; chunkY <= 4; chunkY += 1) {
    for (let chunkX = -4; chunkX <= 4; chunkX += 1) {
      const node = generateChunk(chunkX, chunkY).resources[0];
      if (node) return node;
    }
  }
  throw new Error("TEST_RESOURCE_NODE_NOT_FOUND");
}

async function cleanupResource(db: ReturnType<typeof createDbPool>, userId: string, nodeId: string): Promise<void> {
  await db.query("DELETE FROM resource_gather_requests WHERE user_id=$1", [userId]);
  await db.query("DELETE FROM world_resource_nodes WHERE node_id=$1", [nodeId]);
}

async function createPlayer() {
  const db = createDbPool();
  const unique = randomUUID().replace(/-/g, "").slice(0, 20);
  const user = await db.query<{ user_id: string }>(
    "INSERT INTO users(username,email,password_hash) VALUES($1,$2,$3) RETURNING id AS user_id",
    [`gather_${unique}`, `gather_${unique}@example.com`, "test"],
  );
  const userId = user.rows[0]?.user_id;
  if (!userId) throw new Error("TEST_PLAYER_NOT_CREATED");
  await db.query(
    "INSERT INTO player_profiles(user_id,inventory,hotbar,selected_hotbar_slot) VALUES($1,$2::jsonb,'[null,null,null,null,null,null,null,null]'::jsonb,0)",
    [userId, JSON.stringify({})],
  );
  return { db, userId };
}

describe("resource gathering transactions", () => {
  it("does not issue a redundant resource-gather ledger update", async () => {
    const sqlCalls: string[] = [];
    const respawnsAt = "2026-11-24T10:00:00.000Z";
    const node: ResourceNode = { id: "node-performance", type: "wood", x: 0, y: 0 };
    const query = vi.fn(async (sql: string) => {
      const normalized = sql.trim();
      sqlCalls.push(normalized);
      if (normalized === "BEGIN" || normalized === "COMMIT" || normalized === "ROLLBACK") {
        return { rows: [], rowCount: null };
      }
      if (normalized.startsWith("SELECT fingerprint")) return { rows: [], rowCount: 0 };
      if (normalized.startsWith("INSERT INTO world_resource_nodes")) return { rows: [], rowCount: 1 };
      if (normalized.startsWith("SELECT node_id,type,x,y,depleted_until")) {
        return { rows: [{ node_id: node.id, type: node.type, x: node.x, y: node.y, depleted_until: null }], rowCount: 1 };
      }
      if (normalized.startsWith("INSERT INTO resource_gather_requests")) {
        return { rows: [{ request_id: "request-1", transaction_id: "00000000-0000-4000-8000-000000000001" }], rowCount: 1 };
      }
      if (normalized.startsWith("SELECT gold, triumph_badges, inventory")) {
        return { rows: [{ gold: "0", triumph_badges: "0", inventory: {} }], rowCount: 1 };
      }
      if (normalized.startsWith("UPDATE resource_gather_requests")) return { rows: [], rowCount: 1 };
      if (normalized.startsWith("UPDATE player_profiles")) return { rows: [], rowCount: 1 };
      if (normalized.startsWith("INSERT INTO economy_transactions")) return { rows: [], rowCount: 1 };
      if (normalized.startsWith("UPDATE world_resource_nodes")) {
        return { rows: [{ depleted_until: respawnsAt }], rowCount: 1 };
      }
      throw new Error("Unexpected resource-gathering query: " + normalized);
    });
    const client = { query, release: vi.fn() };
    const db = { connect: vi.fn().mockResolvedValue(client) };

    const result = await gatherResource(db as never, "user-1", "request-1", "gather_resource|node-performance", node);

    expect(result.respawnsAt).toBe(respawnsAt);
    expect(sqlCalls.some((sql) => sql.startsWith("UPDATE resource_gather_requests"))).toBe(false);
    expect(client.release).toHaveBeenCalledExactlyOnceWith(undefined);
  });

  it("gathers once, depletes the node, and replays the same request without a second reward", async () => {
    const { db, userId } = await createPlayer();
    const node = findResource();
    try {
      const timing = createMutationTiming();
      const first = await gatherResource(db, userId, "gather-1", "gather_resource|" + node.id, node, timing);
      const replay = await gatherResource(db, userId, "gather-1", "gather_resource|" + node.id, node);
      expect(timing.diagnostic?.traceId).toMatch(/^[0-9a-f-]{36}$/i);
      expect(timing.diagnostic?.backendPid).toBeGreaterThan(0);
      expect(timing.stages.commitMs).toBeGreaterThanOrEqual(0);
      expect(timing.diagnostic?.commitEventLoopActiveMs).toBeGreaterThanOrEqual(0);
      expect(timing.diagnostic?.commitEventLoopIdleMs).toBeGreaterThanOrEqual(0);
      expect(first.transactionId).toMatch(/^[0-9a-f-]{36}$/i);
      expect(replay).toEqual(first);
      const ledger = await db.query<{ transaction_id: string; respawns_at: Date }>(
        "SELECT transaction_id,respawns_at FROM resource_gather_requests WHERE user_id=$1 AND request_id=$2",
        [userId, "gather-1"],
      );
      const nodeState = await db.query<{ depleted_until: Date }>(
        "SELECT depleted_until FROM world_resource_nodes WHERE node_id=$1",
        [node.id],
      );
      expect(ledger.rows[0]?.transaction_id).toBe(first.transactionId);
      expect(ledger.rows[0]?.respawns_at).toEqual(nodeState.rows[0]?.depleted_until);

      const player = await db.query<{ inventory: Record<string, number> }>(
        "SELECT inventory FROM player_profiles WHERE user_id=$1",
        [userId],
      );
      expect(player.rows[0]?.inventory).toEqual({ [first.itemId]: first.quantity });

      await expect(gatherResource(db, userId, "gather-2", "gather_resource|" + node.id, node)).rejects.toThrow("RESOURCE_DEPLETED");
    } finally {
      await cleanupResource(db, userId, node.id);
      await db.end();
    }
  });

  it("rolls back node depletion when inventory would overflow", async () => {
    const { db, userId } = await createPlayer();
    const node = findResource();
    const itemId = node.type === "wood" ? "resource.wood" : node.type === "stone" ? "resource.stone" : "resource.herb";
    try {
      await db.query("UPDATE player_profiles SET inventory=$2::jsonb WHERE user_id=$1", [userId, JSON.stringify({ [itemId]: MAX_ITEM_STACK })]);
      await expect(gatherResource(db, userId, "gather-overflow", "gather_resource|" + node.id, node)).rejects.toThrow("INVENTORY_LIMIT");
      const nodeState = await db.query("SELECT depleted_until FROM world_resource_nodes WHERE node_id=$1", [node.id]);
      expect(nodeState.rows[0]).toBeUndefined();
      const request = await db.query("SELECT request_id FROM resource_gather_requests WHERE user_id=$1", [userId]);
      expect(request.rows).toHaveLength(0);
    } finally {
      await cleanupResource(db, userId, node.id);
      await db.end();
    }
  });

  it("serializes concurrent gathers against the same node", async () => {
    const { db, userId } = await createPlayer();
    const node = findResource();
    try {
      const results = await Promise.allSettled([
        gatherResource(db, userId, "gather-a", "gather_resource|" + node.id, node),
        gatherResource(db, userId, "gather-b", "gather_resource|" + node.id, node),
      ]);
      expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
      const rejected = results.filter((result): result is PromiseRejectedResult => result.status === "rejected");
      expect(rejected).toHaveLength(1);
      expect(rejected[0]?.reason instanceof Error ? rejected[0].reason.message : rejected[0]?.reason).toBe("RESOURCE_DEPLETED");
      const player = await db.query<{ inventory: Record<string, number> }>("SELECT inventory FROM player_profiles WHERE user_id=$1", [userId]);
      expect(Object.values(player.rows[0]?.inventory ?? {}).reduce((sum, value) => sum + value, 0)).toBeGreaterThan(0);
    } finally {
      await cleanupResource(db, userId, node.id);
      await db.end();
    }
  });

  it("rejects reuse of a request id with a different fingerprint", async () => {
    const { db, userId } = await createPlayer();
    const node = findResource();
    try {
      await gatherResource(db, userId, "gather-conflict", "gather_resource|" + node.id, node);
      await expect(gatherResource(db, userId, "gather-conflict", "gather_resource|other-node", node)).rejects.toThrow("RESOURCE_REQUEST_CONFLICT");
    } finally {
      await cleanupResource(db, userId, node.id);
      await db.end();
    }
  });
});
