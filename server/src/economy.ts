import type { Pool, PoolClient } from "pg";

export const MAX_ITEM_STACK = 1_000_000;
export const MAX_GOLD_DOUBLOONS = 9_223_372_036_854_775_807n;

export type Inventory = Record<string, number>;

export interface EconomyDraft {
  client: PoolClient;
  gold: bigint;
  inventory: Inventory;
}

export interface EconomyMutation<T> {
  gold: bigint;
  inventory: Inventory;
  value: T;
}

export function validateItemId(itemId: string): void {
  if (typeof itemId !== "string" || itemId.length < 1 || itemId.length > 128) {
    throw new Error("INVALID_ITEM_ID");
  }
}

export function validateStackQuantity(quantity: number): void {
  if (!Number.isSafeInteger(quantity) || quantity < 0 || quantity > MAX_ITEM_STACK) {
    throw new Error("INVALID_ITEM_QUANTITY");
  }
}

export function cloneInventory(inventory: Inventory | null | undefined): Inventory {
  const source = inventory ?? {};
  const next: Inventory = {};
  for (const [itemId, quantity] of Object.entries(source)) {
    validateItemId(itemId);
    validateStackQuantity(quantity);
    if (quantity > 0) next[itemId] = quantity;
  }
  return next;
}

export function applyInventoryDelta(inventory: Inventory, itemId: string, delta: number): Inventory {
  validateItemId(itemId);
  if (!Number.isSafeInteger(delta) || Math.abs(delta) > MAX_ITEM_STACK) {
    throw new Error("INVALID_ITEM_QUANTITY");
  }
  const current = inventory[itemId] ?? 0;
  validateStackQuantity(current);
  const nextQuantity = current + delta;
  if (!Number.isSafeInteger(nextQuantity) || nextQuantity < 0 || nextQuantity > MAX_ITEM_STACK) {
    throw new Error(nextQuantity < 0 ? "INSUFFICIENT_INVENTORY" : "INVENTORY_LIMIT");
  }
  const next = { ...inventory };
  if (nextQuantity === 0) delete next[itemId];
  else next[itemId] = nextQuantity;
  return next;
}

export function parseGoldDoubloons(value: string | bigint): bigint {
  const parsed = typeof value === "bigint"
    ? value
    : (/^(0|[1-9][0-9]*)$/.test(value) ? BigInt(value) : (() => { throw new Error("INVALID_GOLD"); })());
  if (parsed < 0n || parsed > MAX_GOLD_DOUBLOONS) throw new Error("GOLD_OVERFLOW");
  return parsed;
}

export function addGoldDoubloons(current: bigint, delta: bigint): bigint {
  const next = parseGoldDoubloons(current) + parseGoldDoubloons(delta);
  if (next > MAX_GOLD_DOUBLOONS) throw new Error("GOLD_OVERFLOW");
  return next;
}

export function subtractGoldDoubloons(current: bigint, amount: bigint): bigint {
  const balance = parseGoldDoubloons(current);
  const cost = parseGoldDoubloons(amount);
  if (cost > balance) throw new Error("INSUFFICIENT_GOLD");
  return balance - cost;
}

export async function runEconomyTransaction<T>(
  db: Pool,
  userId: string,
  mutation: (draft: EconomyDraft) => EconomyMutation<T> | Promise<EconomyMutation<T>>,
): Promise<T> {
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    const result = await client.query<{ gold: string; inventory: Inventory }>(
      "SELECT gold, inventory FROM player_profiles WHERE user_id=$1 FOR UPDATE",
      [userId],
    );
    const row = result.rows[0];
    if (!row) throw new Error("PLAYER_NOT_FOUND");

    const draft: EconomyDraft = {
      client,
      gold: parseGoldDoubloons(row.gold),
      inventory: cloneInventory(row.inventory),
    };
    const next = await mutation(draft);
    const gold = parseGoldDoubloons(next.gold);
    const inventory = cloneInventory(next.inventory);

    await client.query(
      "UPDATE player_profiles SET gold=$2, inventory=$3::jsonb, updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",
      [userId, gold.toString(), JSON.stringify(inventory)],
    );
    await client.query("COMMIT");
    return next.value;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
