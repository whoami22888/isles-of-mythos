import type { Pool } from "pg";
import { applyInventoryDelta, runEconomyMutation } from "./economy.js";
import type { ResourceNode } from "./world.js";

const RESOURCE_YIELDS: Record<ResourceNode["type"], { itemId: string; quantity: number; respawnMs: number }> = {
  wood: { itemId: "resource.wood", quantity: 2, respawnMs: 60_000 },
  stone: { itemId: "resource.stone", quantity: 2, respawnMs: 90_000 },
  herb: { itemId: "resource.herb", quantity: 1, respawnMs: 45_000 },
};

export interface ResourceGatherResult {
  transactionId: string;
  nodeId: string;
  itemId: string;
  quantity: number;
  respawnsAt: string;
}

export function resourceGatherFingerprint(nodeId: string): string {
  return "gather_resource|" + nodeId;
}

export async function gatherResource(
  db: Pool,
  userId: string,
  requestId: string,
  fingerprint: string,
  node: ResourceNode,
): Promise<ResourceGatherResult> {
  const reward = RESOURCE_YIELDS[node.type];
  if (!reward) throw new Error("RESOURCE_NOT_FOUND");

  const client = await db.connect();
  try {
    await client.query("BEGIN");

    const existing = await client.query<{
      fingerprint: string;
      transaction_id: string;
      node_id: string;
      item_id: string;
      quantity: number;
      respawns_at: string;
    }>(
      "SELECT fingerprint,transaction_id,node_id,item_id,quantity,respawns_at FROM resource_gather_requests WHERE user_id=$1 AND request_id=$2 FOR UPDATE",
      [userId, requestId],
    );
    if (existing.rows[0]) {
      const row = existing.rows[0];
      if (row.fingerprint !== fingerprint) throw new Error("RESOURCE_REQUEST_CONFLICT");
      await client.query("COMMIT");
      return {
        transactionId: row.transaction_id,
        nodeId: row.node_id,
        itemId: row.item_id,
        quantity: row.quantity,
        respawnsAt: new Date(row.respawns_at).toISOString(),
      };
    }

    await client.query(
      "INSERT INTO world_resource_nodes(node_id,type,x,y) VALUES($1,$2,$3,$4) ON CONFLICT(node_id) DO NOTHING",
      [node.id, node.type, node.x, node.y],
    );

    const nodeRow = await client.query<{
      node_id: string;
      type: ResourceNode["type"];
      x: number;
      y: number;
      depleted_until: string | null;
    }>(
      "SELECT node_id,type,x,y,depleted_until FROM world_resource_nodes WHERE node_id=$1 FOR UPDATE",
      [node.id],
    );
    const stored = nodeRow.rows[0];
    if (!stored || stored.type !== node.type || stored.x !== node.x || stored.y !== node.y) {
      throw new Error("RESOURCE_NODE_MISMATCH");
    }
    if (stored.depleted_until && new Date(stored.depleted_until).getTime() > Date.now()) {
      throw new Error("RESOURCE_DEPLETED");
    }

    const requestInsert = await client.query<{ request_id: string; transaction_id: string }>(
      "INSERT INTO resource_gather_requests(user_id,request_id,fingerprint,node_id,item_id,quantity,respawns_at) VALUES($1,$2,$3,$4,$5,$6,CURRENT_TIMESTAMP + ($7 * interval '1 millisecond')) ON CONFLICT(user_id,request_id) DO NOTHING RETURNING request_id,transaction_id",
      [userId, requestId, fingerprint, node.id, reward.itemId, reward.quantity, reward.respawnMs],
    );
    if (requestInsert.rowCount !== 1) {
      const retry = await client.query<{
        fingerprint: string;
        transaction_id: string;
        node_id: string;
        item_id: string;
        quantity: number;
        respawns_at: string;
      }>(
        "SELECT fingerprint,transaction_id,node_id,item_id,quantity,respawns_at FROM resource_gather_requests WHERE user_id=$1 AND request_id=$2 FOR UPDATE",
        [userId, requestId],
      );
      const row = retry.rows[0];
      if (!row) throw new Error("RESOURCE_REQUEST_CONFLICT");
      if (row.fingerprint !== fingerprint) throw new Error("RESOURCE_REQUEST_CONFLICT");
      await client.query("COMMIT");
      return {
        nodeId: row.node_id,
        itemId: row.item_id,
        quantity: row.quantity,
        respawnsAt: new Date(row.respawns_at).toISOString(),
      };
    }

    await runEconomyMutation(client, userId, ({ gold, inventory }) => ({
      gold,
      inventory: applyInventoryDelta(inventory, reward.itemId, reward.quantity),
      value: undefined,
    }));

    const updatedNode = await client.query<{ depleted_until: string }>(
      "UPDATE world_resource_nodes SET depleted_until=CURRENT_TIMESTAMP + ($2 * interval '1 millisecond'),updated_at=CURRENT_TIMESTAMP WHERE node_id=$1 RETURNING depleted_until",
      [node.id, reward.respawnMs],
    );
    const respawnsAt = updatedNode.rows[0]?.depleted_until;
    if (!respawnsAt) throw new Error("RESOURCE_NODE_UPDATE_FAILED");

    await client.query(
      "UPDATE resource_gather_requests SET respawns_at=$3,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1 AND request_id=$2",
      [userId, requestId, respawnsAt],
    );

    await client.query("COMMIT");
    return {
      transactionId: requestInsert.rows[0]?.transaction_id ?? (()=>{throw new Error("RESOURCE_TRANSACTION_ID_MISSING");})(),
      nodeId: node.id,
      itemId: reward.itemId,
      quantity: reward.quantity,
      respawnsAt: new Date(respawnsAt).toISOString(),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
