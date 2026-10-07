import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { createDbPool } from "./db.js";
import { MAX_ITEM_STACK } from "./economy.js";
import { gatherResource } from "./resource-gathering.js";
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

async function createPlayer() {
  const db = createDbPool();
  const unique = randomUUID().replace(/-/g, "").slice(0, 24);
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
  it("gathers once, depletes the node, and replays the same request without a second reward", async () => {
    const { db, userId } = await createPlayer();
    const node = findResource();
    try {
      const first = await gatherResource(db, userId, "gather-1", "gather_resource|" + node.id, node);
      const replay = await gatherResource(db, userId, "gather-1", "gather_resource|" + node.id, node);
      expect(replay).toEqual(first);

      const player = await db.query<{ inventory: Record<string, number> }>(
        "SELECT inventory FROM player_profiles WHERE user_id=$1",
        [userId],
      );
      expect(player.rows[0]?.inventory).toEqual({ [first.itemId]: first.quantity });

      await expect(gatherResource(db, userId, "gather-2", "gather_resource|" + node.id, node)).rejects.toThrow("RESOURCE_DEPLETED");
    } finally {
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
      expect(results.filter((result) => result.status === "rejected").map((result) => result.reason.message)).toEqual(["RESOURCE_DEPLETED"]);
      const player = await db.query<{ inventory: Record<string, number> }>("SELECT inventory FROM player_profiles WHERE user_id=$1", [userId]);
      expect(Object.values(player.rows[0]?.inventory ?? {}).reduce((sum, value) => sum + value, 0)).toBeGreaterThan(0);
    } finally {
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
      await db.end();
    }
  });
});
