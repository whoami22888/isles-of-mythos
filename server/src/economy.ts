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

export async function runEconomyMutation<T>(\n  client: PoolClient,\n  userId: string,\n  mutation: (draft: EconomyDraft) => EconomyMutation<T> | Promise<EconomyMutation<T>>,\n): Promise<T> {\n  const result = await client.query<{ gold: string; triumph_badges: string; inventory: Inventory }>(\n    "SELECT gold, triumph_badges, inventory FROM player_profiles WHERE user_id=$1 FOR UPDATE",\n    [userId],\n  );\n  const row = result.rows[0];\n  if (!row) throw new Error("PLAYER_NOT_FOUND");\n\n  const draft: EconomyDraft = {\n    client,\n    gold: parseGoldDoubloons(row.gold),\n    triumphBadges: parseTriumphBadges(row.triumph_badges),\n    inventory: cloneInventory(row.inventory),\n  };\n  const next = await mutation(draft);\n  const gold = parseGoldDoubloons(next.gold);\n  const triumphBadges = parseTriumphBadges(next.triumphBadges ?? draft.triumphBadges);\n  const inventory = cloneInventory(next.inventory);\n\n  await client.query(\n    "UPDATE player_profiles SET gold=$2, triumph_badges=$3, inventory=$4::jsonb, updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",\n    [userId, gold.toString(), triumphBadges.toString(), JSON.stringify(inventory)],\n  );\n  return next.value;\n}\n\nexport async function runEconomyTransaction<T>(\n  db: Pool,\n  userId: string,\n  mutation: (draft: EconomyDraft) => EconomyMutation<T> | Promise<EconomyMutation<T>>,\n): Promise<T> {\n  const client = await db.connect();\n  try {\n    await client.query("BEGIN");\n    const value = await runEconomyMutation(client, userId, mutation);\n    await client.query("COMMIT");\n    return value;\n  } catch (error) {\n    await client.query("ROLLBACK");\n    throw error;\n  } finally {\n    client.release();\n  }\n}\n