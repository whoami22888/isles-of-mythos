import type { Pool, PoolClient } from "pg";

export const MAX_ITEM_STACK = 1_000_000;
export const MAX_GOLD_DOUBLOONS = 9_223_372_036_854_775_807n;
export const MAX_TRIUMPH_BADGES = MAX_GOLD_DOUBLOONS;

export type Inventory = Record<string, number>;

export interface EconomyDraft {
  client: PoolClient;
  gold: bigint;
  triumphBadges: bigint;
  inventory: Inventory;
}

export interface EconomyMutation<T> {
  gold: bigint;
  triumphBadges?: bigint;
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
    next[itemId] = quantity;
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
  next[itemId] = nextQuantity;
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

export function parseTriumphBadges(value: string | bigint): bigint {
  const parsed = typeof value === "bigint"
    ? value
    : (/^(0|[1-9][0-9]*)$/.test(value) ? BigInt(value) : (() => { throw new Error("INVALID_TRIUMPH_BADGES"); })());
  if (parsed < 0n || parsed > MAX_TRIUMPH_BADGES) throw new Error("TRIUMPH_BADGES_OVERFLOW");
  return parsed;
}

export function addTriumphBadges(current: bigint, delta: bigint): bigint {
  const next = parseTriumphBadges(current) + parseTriumphBadges(delta);
  if (next > MAX_TRIUMPH_BADGES) throw new Error("TRIUMPH_BADGES_OVERFLOW");
  return next;
}

export function subtractTriumphBadges(current: bigint, amount: bigint): bigint {
  const balance = parseTriumphBadges(current);
  const cost = parseTriumphBadges(amount);
  if (cost > balance) throw new Error("INSUFFICIENT_TRIUMPH_BADGES");
  return balance - cost;
}

export function subtractGoldDoubloons(current: bigint, amount: bigint): bigint {
  const balance = parseGoldDoubloons(current);
  const cost = parseGoldDoubloons(amount);
  if (cost > balance) throw new Error("INSUFFICIENT_GOLD");
  return balance - cost;
}

export async function runEconomyMutation<T>(
  client: PoolClient,
  userId: string,
  mutation: (draft: EconomyDraft) => EconomyMutation<T> | Promise<EconomyMutation<T>>,
  operation = "economy_mutation",
): Promise<T> {
  const result = await client.query<{ gold: string; triumph_badges: string; inventory: Inventory }>(
    "SELECT gold, triumph_badges, inventory FROM player_profiles WHERE user_id=$1 FOR UPDATE",
    [userId],
  );
  const row = result.rows[0];
  if (!row) throw new Error("PLAYER_NOT_FOUND");

  const draft: EconomyDraft = {
    client,
    gold: parseGoldDoubloons(row.gold),
    triumphBadges: parseTriumphBadges(row.triumph_badges),
    inventory: cloneInventory(row.inventory),
  };
  const next = await mutation(draft);
  const gold = parseGoldDoubloons(next.gold);
  const triumphBadges = parseTriumphBadges(next.triumphBadges ?? draft.triumphBadges);
  const inventory = cloneInventory(next.inventory);

  await client.query(
    "UPDATE player_profiles SET gold=$2, triumph_badges=$3, inventory=$4::jsonb, updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",
    [userId, gold.toString(), triumphBadges.toString(), JSON.stringify(inventory)],
  );

  await client.query(
    "INSERT INTO economy_transactions (user_id, operation, gold_before, gold_after, triumph_badges_before, triumph_badges_after, inventory_before, inventory_after) VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb)",
    [
      userId,
      operation,
      draft.gold.toString(),
      gold.toString(),
      draft.triumphBadges.toString(),
      triumphBadges.toString(),
      JSON.stringify(draft.inventory),
      JSON.stringify(inventory),
    ],
  );

  return next.value;
}

export async function runEconomyTransaction<T>(
  db: Pool,
  userId: string,
  mutation: (draft: EconomyDraft) => EconomyMutation<T> | Promise<EconomyMutation<T>>,
  operation = "economy_mutation",
): Promise<T> {
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    const value = await runEconomyMutation(client, userId, mutation, operation);
    await client.query("COMMIT");
    return value;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}