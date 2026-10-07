import { randomUUID } from "node:crypto";
import type { Pool } from "pg";
import {
  addGoldDoubloons,
  applyInventoryDelta,
  cloneInventory,
  parseGoldDoubloons,
  subtractGoldDoubloons,
  type Inventory,
} from "./economy.js";

const ITEM_ID_PATTERN = /^[a-z0-9]+(?:[._-][a-z0-9]+)*$/;
const MAX_TRADE_ITEMS = 32;
const MAX_REQUEST_ID = 64;

export interface TradeItem {
  readonly itemId: string;
  readonly quantity: number;
}

export interface TradeRequest {
  readonly requestId: string;
  readonly fromUserId: string;
  readonly toUserId: string;
  readonly gold: string;
  readonly items: readonly TradeItem[];
}

export interface TradeParticipantSnapshot {
  readonly userId: string;
  readonly gold: string;
  readonly inventory: Inventory;
}

export interface TradeResult {
  readonly requestId: string;
  readonly transactionId: string;
  readonly from: TradeParticipantSnapshot;
  readonly to: TradeParticipantSnapshot;
}

function validateTradeRequest(request: TradeRequest): void {
  if (!request.requestId || request.requestId.length > MAX_REQUEST_ID) throw new Error("INVALID_TRADE_REQUEST");
  if (!request.fromUserId || !request.toUserId || request.fromUserId === request.toUserId) throw new Error("INVALID_TRADE_PARTICIPANTS");
  if (request.items.length > MAX_TRADE_ITEMS) throw new Error("INVALID_TRADE_ITEMS");
  for (const item of request.items) {
    if (!ITEM_ID_PATTERN.test(item.itemId) || item.itemId.length > 128) throw new Error("INVALID_TRADE_ITEM");
    if (!Number.isSafeInteger(item.quantity) || item.quantity < 1 || item.quantity > 1_000_000) {
      throw new Error("INVALID_TRADE_QUANTITY");
    }
  }
  parseGoldDoubloons(request.gold);
}

function fingerprintRequest(request: TradeRequest): string {
  const items = [...request.items]
    .map(({ itemId, quantity }) => ({ itemId, quantity }))
    .sort((a, b) => a.itemId.localeCompare(b.itemId));
  return JSON.stringify({
    fromUserId: request.fromUserId,
    toUserId: request.toUserId,
    gold: request.gold,
    items,
  });
}

export async function tradePlayers(db: Pool, request: TradeRequest): Promise<TradeResult> {
  validateTradeRequest(request);
  const requestKey = request.fromUserId + ":" + request.requestId;
  const fingerprint = fingerprintRequest(request);
  const transactionId = randomUUID();
  const client = await db.connect();

  try {
    await client.query("BEGIN");

    const inserted = await client.query(
      "INSERT INTO trade_requests (request_key, transaction_id, user_id, fingerprint, response) VALUES ($1, $2, $3, $4, '{}'::jsonb) ON CONFLICT (request_key) DO NOTHING RETURNING request_key",
      [requestKey, transactionId, request.fromUserId, fingerprint],
    );

    if (inserted.rowCount === 0) {
      const existing = await client.query<{ transaction_id: string; fingerprint: string; response: TradeResult }>(
        "SELECT transaction_id, fingerprint, response FROM trade_requests WHERE request_key=$1 FOR UPDATE",
        [requestKey],
      );
      const row = existing.rows[0];
      if (!row) throw new Error("TRADE_REQUEST_NOT_FOUND");
      if (row.fingerprint !== fingerprint) throw new Error("TRADE_REQUEST_CONFLICT");
      await client.query("COMMIT");
      return { ...row.response, transactionId: row.transaction_id };
    }

    const userIds = [request.fromUserId, request.toUserId].sort();
    const result = await client.query<{ user_id: string; gold: string; inventory: Record<string, number> }>(
      "SELECT user_id, gold, inventory FROM player_profiles WHERE user_id = ANY($1::uuid[]) ORDER BY user_id FOR UPDATE",
      [userIds],
    );
    if (result.rows.length !== 2) throw new Error("PLAYER_NOT_FOUND");

    const byUser = new Map(result.rows.map((row) => [row.user_id, row]));
    const fromRow = byUser.get(request.fromUserId);
    const toRow = byUser.get(request.toUserId);
    if (!fromRow || !toRow) throw new Error("PLAYER_NOT_FOUND");

    let fromInventory = cloneInventory(fromRow.inventory);
    let toInventory = cloneInventory(toRow.inventory);
    const transferGold = parseGoldDoubloons(request.gold);
    let fromGold = parseGoldDoubloons(fromRow.gold);
    let toGold = parseGoldDoubloons(toRow.gold);

    for (const item of request.items) {
      fromInventory = applyInventoryDelta(fromInventory, item.itemId, -item.quantity);
      toInventory = applyInventoryDelta(toInventory, item.itemId, item.quantity);
    }
    fromGold = subtractGoldDoubloons(fromGold, transferGold);
    toGold = addGoldDoubloons(toGold, transferGold);

    await client.query(
      "UPDATE player_profiles SET gold=$2, inventory=$3::jsonb, updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",
      [request.fromUserId, fromGold.toString(), JSON.stringify(fromInventory)],
    );
    await client.query(
      "UPDATE player_profiles SET gold=$2, inventory=$3::jsonb, updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",
      [request.toUserId, toGold.toString(), JSON.stringify(toInventory)],
    );

    const response: TradeResult = {
      requestId: request.requestId,
      transactionId,
      from: { userId: request.fromUserId, gold: fromGold.toString(), inventory: fromInventory },
      to: { userId: request.toUserId, gold: toGold.toString(), inventory: toInventory },
    };
    await client.query(
      "UPDATE trade_requests SET response=$2::jsonb WHERE request_key=$1",
      [requestKey, JSON.stringify(response)],
    );
    await client.query("COMMIT");
    return response;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
