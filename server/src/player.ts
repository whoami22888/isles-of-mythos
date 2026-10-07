import type { Pool } from "pg";
import type { ShopItem } from "./shop.js";
import { applyInventoryDelta, cloneInventory, parseGoldDoubloons, parseTriumphBadges, runEconomyTransaction, subtractGoldDoubloons, type Inventory } from "./economy.js";
import { TileKind, tileAtWorld } from "./world.js";

export const PLAYER_MAX_HEALTH = 100;
export const PLAYER_MAX_HUNGER = 100;
export const PLAYER_MAX_OXYGEN = 100;
export const PLAYER_LAND_SPEED = 4;
export const PLAYER_WATER_SPEED = 2.5;
export const PLAYER_HITBOX_WIDTH = 0.7;
export const PLAYER_HITBOX_HEIGHT = 0.7;
export const MELEE_RANGE = 1.5;
export const STARTING_FLINTLOCK_AMMO = 30;
export const PLAYER_BASE_DEFENSE = 0;

export interface PlayerState {
  userId: string; x: number; y: number; health: number; defense: number; stamina: number; maxStamina: number; hunger: number; oxygen: number;
  xp: number; level: number; gold: bigint; triumphBadges: bigint; inventory: Record<string, number>;
  hotbar: Array<string | null>; selectedHotbarSlot: number;
}
export type PublicPlayerState = Omit<PlayerState, "gold" | "triumphBadges"> & { gold: string; triumphBadges: string };

export function serializePlayerState(state: PlayerState): PublicPlayerState {
  return { ...state, gold: state.gold.toString(), triumphBadges: state.triumphBadges.toString(), inventory: { ...state.inventory } };
}

export interface PlayerInput { dx: number; dy: number; dt: number; speedMultiplier?: number; }
export interface Hitbox { x: number; y: number; width: number; height: number; }

export function playerHitbox(state: Pick<PlayerState, "x" | "y">): Hitbox {
  return { x: state.x - PLAYER_HITBOX_WIDTH / 2, y: state.y - PLAYER_HITBOX_HEIGHT / 2,
    width: PLAYER_HITBOX_WIDTH, height: PLAYER_HITBOX_HEIGHT };
}
export function meleeHitbox(state: Pick<PlayerState, "x" | "y">, facingX = 0, facingY = 1): Hitbox {
  const length = Math.hypot(facingX, facingY) || 1, nx = facingX / length, ny = facingY / length;
  const centerX = state.x + nx * (MELEE_RANGE / 2), centerY = state.y + ny * (MELEE_RANGE / 2);
  return { x: centerX - MELEE_RANGE / 2, y: centerY - MELEE_RANGE / 2, width: MELEE_RANGE, height: MELEE_RANGE };
}
function clamp(value: number, min: number, max: number): number { return Math.max(min, Math.min(max, value)); }

export function applyPlayerInput(state: PlayerState, input: PlayerInput): PlayerState {
  const dt = clamp(input.dt, 0, 0.25);
  const dx = Number.isFinite(input.dx) ? input.dx : 0, dy = Number.isFinite(input.dy) ? input.dy : 0;
  const length = Math.hypot(dx, dy);
  if (length > 0 && dt > 0) {
    const nx = dx / length, ny = dy / length;
    const speedMultiplier = clamp(input.speedMultiplier ?? 1, 0, 1);
    const tile = tileAtWorld(Math.floor(state.x), Math.floor(state.y));
    const inWater = tile === TileKind.Ocean || tile === TileKind.Shallow;
    const speed = inWater ? PLAYER_WATER_SPEED : PLAYER_LAND_SPEED;
    state.x = clamp(state.x + nx * speed * dt * speedMultiplier, -1_000_000, 1_000_000);
    state.y = clamp(state.y + ny * speed * dt * speedMultiplier, -1_000_000, 1_000_000);
  }
  const tile = tileAtWorld(Math.floor(state.x), Math.floor(state.y));
  const inWater = tile === TileKind.Ocean || tile === TileKind.Shallow;
  state.stamina = clamp(state.stamina + dt * 12, 0, state.maxStamina);
  state.hunger = clamp(state.hunger - dt * 0.12, 0, PLAYER_MAX_HUNGER);
  state.oxygen = inWater ? clamp(state.oxygen - dt * 0.35, 0, PLAYER_MAX_OXYGEN)
    : clamp(state.oxygen + dt * 0.8, 0, PLAYER_MAX_OXYGEN);
  if (state.hunger === 0 || state.oxygen === 0) state.health = clamp(state.health - dt * 2, 0, PLAYER_MAX_HEALTH);
  return state;
}

export function createDefaultPlayer(userId: string): PlayerState {
  return { userId, x: 0, y: 0, health: PLAYER_MAX_HEALTH, defense: PLAYER_BASE_DEFENSE, stamina: 100, maxStamina: 100, hunger: PLAYER_MAX_HUNGER, oxygen: PLAYER_MAX_OXYGEN,
    xp: 0, level: 1, gold: 0n, triumphBadges: 0n, inventory: { "ammo.flintlock": STARTING_FLINTLOCK_AMMO, "capture.orb": 3, "creature.feed": 4 }, hotbar: ["cutlass", "flintlock", null, null, null, null, null, null], selectedHotbarSlot: 0 };
}
interface PlayerRow {
  user_id: string; x: number; y: number; health: number; defense: number; stamina: number; max_stamina: number; hunger: number; oxygen: number;
  xp: string; level: number; gold: string; triumph_badges: string; inventory: Record<string, number>;
  hotbar: Array<string | null>; selected_hotbar_slot: number;
}
function rowToState(row: PlayerRow): PlayerState {
  return { userId: row.user_id, x: row.x, y: row.y, health: row.health, defense: row.defense ?? PLAYER_BASE_DEFENSE, stamina: row.stamina, maxStamina: row.max_stamina, hunger: row.hunger, oxygen: row.oxygen,
    xp: Number(row.xp), level: row.level, gold: parseGoldDoubloons(row.gold), triumphBadges: parseTriumphBadges(row.triumph_badges),
    inventory: cloneInventory({ "ammo.flintlock": STARTING_FLINTLOCK_AMMO, ...(row.inventory ?? {}) }),
    hotbar: row.hotbar ?? [null, null, null, null, null, null, null, null], selectedHotbarSlot: row.selected_hotbar_slot };
}
export class PlayerStore {
  private readonly active = new Map<string, PlayerState>();
  private readonly dirty = new Set<string>();
  private readonly revisions = new Map<string, number>();
  private readonly operations = new Map<string, Promise<void>>();
  private readonly economyInventorySnapshots = new Map<string, Inventory>();
  constructor(private readonly db: Pool) {}
  async runExclusive<T>(userId: string, operation: () => Promise<T>): Promise<T> {
    const previous = this.operations.get(userId) ?? Promise.resolve();
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const queued = previous.catch(() => undefined).then(() => gate);
    this.operations.set(userId, queued);
    await previous.catch(() => undefined);
    try { return await operation(); }
    finally {
      release();
      if (this.operations.get(userId) === queued) this.operations.delete(userId);
    }
  }
  async loadOrCreate(userId: string): Promise<PlayerState> {
    const existing = this.active.get(userId);
    if (existing) return existing;
    await this.db.query(
      "INSERT INTO player_profiles (user_id, inventory, hotbar, selected_hotbar_slot) VALUES ($1, '{\"ammo.flintlock\":30,\"capture.orb\":3,\"creature.feed\":4}'::jsonb, '[\"cutlass\",\"flintlock\",null,null,null,null,null,null]'::jsonb, 0) ON CONFLICT (user_id) DO NOTHING",
      [userId],
    );
    const result = await this.db.query<PlayerRow>(
      "SELECT user_id, x, y, health, defense, stamina, max_stamina, hunger, oxygen, xp, level, gold, triumph_badges, inventory, hotbar, selected_hotbar_slot FROM player_profiles WHERE user_id = $1",
      [userId],
    );
    const row = result.rows[0];
    if (!row) throw new Error("PLAYER_NOT_FOUND");
    const state = rowToState(row);
    this.active.set(userId, state);
    this.economyInventorySnapshots.set(userId, cloneInventory(state.inventory));
    this.revisions.set(userId, 0);
    this.dirty.delete(userId);
    return state;
  }
  get(userId: string): PlayerState | undefined { return this.active.get(userId); }
  markDirty(userId: string): void {
    if (!this.active.has(userId)) return;
    this.dirty.add(userId);
    this.revisions.set(userId, (this.revisions.get(userId) ?? 0) + 1);
  }
  tick(dt: number): void {
    for (const [userId, state] of this.active) {
      const before = [state.health, state.stamina, state.hunger, state.oxygen].join("|");
      applyPlayerInput(state, { dx: 0, dy: 0, dt });
      const after = [state.health, state.stamina, state.hunger, state.oxygen].join("|");
      if (before !== after) this.markDirty(userId);
    }
  }
  private async persistUnsafe(userId: string): Promise<void> {
    const state = this.active.get(userId); if (!state) return;
    const revision = this.revisions.get(userId) ?? 0;
    const snapshot = {
      x: state.x,
      y: state.y,
      health: state.health,
      defense: state.defense,
      stamina: state.stamina,
      maxStamina: state.maxStamina,
      hunger: state.hunger,
      oxygen: state.oxygen,
      xp: state.xp,
      level: state.level,
      hotbar: JSON.stringify(state.hotbar),
      selectedHotbarSlot: state.selectedHotbarSlot,
    };
    await this.db.query(
      "UPDATE player_profiles SET x=$2, y=$3, health=$4, defense=$5, stamina=$6, max_stamina=$7, hunger=$8, oxygen=$9, xp=$10, level=$11, hotbar=$12::jsonb, selected_hotbar_slot=$13, updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",
      [userId, snapshot.x, snapshot.y, snapshot.health, snapshot.defense, snapshot.stamina, snapshot.maxStamina, snapshot.hunger, snapshot.oxygen, snapshot.xp, snapshot.level,
        snapshot.hotbar, snapshot.selectedHotbarSlot]);
    const baselineInventory = this.economyInventorySnapshots.get(userId);
    const inventoryChanged = !baselineInventory || !sameInventory(baselineInventory, state.inventory);
    if (inventoryChanged) {
      await this.db.query(
        "UPDATE player_profiles SET inventory=$2::jsonb, updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",
        [userId, JSON.stringify(cloneInventory(state.inventory))],
      );
      this.economyInventorySnapshots.set(userId, cloneInventory(state.inventory));
    }
    if ((this.revisions.get(userId) ?? 0) === revision) this.dirty.delete(userId);
  }
  async purchase(userId: string, requestId: string, item: ShopItem, quantity: number, totalGold: bigint): Promise<PublicPlayerState> {
    return this.runExclusive(userId, async () => {
      if (!requestId || requestId.length > 64) throw new Error("INVALID_REQUEST_ID");
      const requestKey = userId + ":" + requestId;
      const fingerprint = JSON.stringify({ itemId: item.id, quantity, totalGold: totalGold.toString() });
      const client = await this.db.connect();
      try {
        await client.query("BEGIN");
        const inserted = await client.query(
          "INSERT INTO shop_purchase_requests (request_key, user_id, fingerprint, response) VALUES ($1, $2, $3, '{}'::jsonb) ON CONFLICT (request_key) DO NOTHING RETURNING request_key",
          [requestKey, userId, fingerprint],
        );
        if (inserted.rowCount === 0) {
          const existing = await client.query<{ fingerprint: string; response: PublicPlayerState }>(
            "SELECT fingerprint, response FROM shop_purchase_requests WHERE request_key=$1 FOR UPDATE",
            [requestKey],
          );
          const row = existing.rows[0];
          if (!row) throw new Error("SHOP_REQUEST_NOT_FOUND");
          if (row.fingerprint !== fingerprint) throw new Error("SHOP_REQUEST_CONFLICT");
          await client.query("COMMIT");
          return row.response;
        }

        const result = await client.query<{ gold: string; inventory: Inventory }>(
          "SELECT gold, inventory FROM player_profiles WHERE user_id=$1 FOR UPDATE",
          [userId],
        );
        const row = result.rows[0];
        if (!row) throw new Error("PLAYER_NOT_FOUND");
        const gold = parseGoldDoubloons(row.gold);
        const inventory = cloneInventory(row.inventory);
        const nextInventory = applyInventoryDelta(inventory, item.id, quantity);
        const nextGold = subtractGoldDoubloons(gold, totalGold);
        await client.query(
          "UPDATE player_profiles SET gold=$2, inventory=$3::jsonb, updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",
          [userId, nextGold.toString(), JSON.stringify(nextInventory)],
        );

        const state = this.active.get(userId);
        if (!state) throw new Error("PLAYER_NOT_FOUND");
        const response = serializePlayerState({ ...state, gold: nextGold, inventory: nextInventory });
        await client.query(
          "UPDATE shop_purchase_requests SET response=$2::jsonb WHERE request_key=$1",
          [requestKey, JSON.stringify(response)],
        );
        await client.query("COMMIT");
        state.gold = nextGold;
        state.inventory = nextInventory;
        this.economyInventorySnapshots.set(userId, cloneInventory(nextInventory));
        this.markDirty(userId);
        return response;
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      } finally {
        client.release();
      }
    });
  }

  async reloadEconomy(userId: string): Promise<PlayerState> {
    const result = await this.db.query<{ gold: string; triumph_badges: string; inventory: Record<string, number> }>(
      "SELECT gold, triumph_badges, inventory FROM player_profiles WHERE user_id=$1",
      [userId],
    );
    const state = this.active.get(userId);
    const row = result.rows[0];
    if (!state || !row) throw new Error("PLAYER_NOT_FOUND");
    state.gold = parseGoldDoubloons(row.gold);
    state.triumphBadges = parseTriumphBadges(row.triumph_badges);
    state.inventory = cloneInventory(row.inventory);
    this.economyInventorySnapshots.set(userId, cloneInventory(state.inventory));
    return state;
  }

  async consumeInventory(userId: string, itemId: string, quantity = 1): Promise<PlayerState> {
    return this.runExclusive(userId, async () => {
      const result = await runEconomyTransaction(this.db, userId, ({ gold, inventory }) => {
        const nextInventory = applyInventoryDelta(inventory, itemId, -quantity);
        return { gold, inventory: nextInventory, value: { gold, inventory: nextInventory } };
      });
      const state = this.active.get(userId);
      if (!state) throw new Error("PLAYER_NOT_FOUND");
      state.gold = result.gold;
      state.inventory = result.inventory;
      this.economyInventorySnapshots.set(userId, cloneInventory(result.inventory));
      this.markDirty(userId);
      return state;
    });
  }

  async persist(userId: string): Promise<void> {
    await this.runExclusive(userId, () => this.persistUnsafe(userId));
  }
  async unload(userId: string): Promise<void> {
    await this.runExclusive(userId, async () => {
      await this.persistUnsafe(userId);
      this.active.delete(userId);
      this.dirty.delete(userId);
      this.revisions.delete(userId);
      this.economyInventorySnapshots.delete(userId);
    });
  }
  async persistDirty(): Promise<void> {
    const userIds = [...this.dirty];
    for (const userId of userIds) await this.persist(userId);
  }
  async persistAll(): Promise<void> {
    const userIds = [...this.active.keys()];
    for (const userId of userIds) await this.persist(userId);
  }
}

function sameInventory(a: Inventory, b: Inventory): boolean {
  const aKeys = Object.keys(a);
  const bKeys = Object.keys(b);
  if (aKeys.length !== bKeys.length) return false;
  for (const key of aKeys) if (a[key] !== b[key]) return false;
  return true;
}
