import type { Pool } from "pg";
import type { ShopItem } from "./shop.js";
import { TileKind, tileAtWorld } from "./world.js";

export const PLAYER_MAX_HEALTH = 100;
export const PLAYER_MAX_HUNGER = 100;
export const PLAYER_MAX_OXYGEN = 100;
export const PLAYER_LAND_SPEED = 4;
export const PLAYER_WATER_SPEED = 2.5;
export const PLAYER_HITBOX_WIDTH = 0.7;
export const PLAYER_HITBOX_HEIGHT = 0.7;
export const MELEE_RANGE = 1.5;

export interface PlayerState {
  userId: string; x: number; y: number; health: number; stamina: number; maxStamina: number; hunger: number; oxygen: number;
  xp: number; level: number; gold: number; inventory: Record<string, number>;
  hotbar: Array<string | null>; selectedHotbarSlot: number;
}
export interface PlayerInput { dx: number; dy: number; dt: number; }
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
    const tile = tileAtWorld(Math.floor(state.x), Math.floor(state.y));
    const inWater = tile === TileKind.Ocean || tile === TileKind.Shallow;
    const speed = inWater ? PLAYER_WATER_SPEED : PLAYER_LAND_SPEED;
    state.x = clamp(state.x + nx * speed * dt, -1_000_000, 1_000_000);
    state.y = clamp(state.y + ny * speed * dt, -1_000_000, 1_000_000);
  }
  const tile = tileAtWorld(Math.floor(state.x), Math.floor(state.y));
  const inWater = tile === TileKind.Ocean || tile === TileKind.Shallow;
  state.hunger = clamp(state.hunger - dt * 0.12, 0, PLAYER_MAX_HUNGER);
  state.oxygen = inWater ? clamp(state.oxygen - dt * 0.35, 0, PLAYER_MAX_OXYGEN)
    : clamp(state.oxygen + dt * 0.8, 0, PLAYER_MAX_OXYGEN);
  if (state.hunger === 0 || state.oxygen === 0) state.health = clamp(state.health - dt * 2, 0, PLAYER_MAX_HEALTH);
  return state;
}

export function createDefaultPlayer(userId: string): PlayerState {
  return { userId, x: 0, y: 0, health: PLAYER_MAX_HEALTH, stamina: 100, maxStamina: 100, hunger: PLAYER_MAX_HUNGER, oxygen: PLAYER_MAX_OXYGEN,
    xp: 0, level: 1, gold: 0, inventory: {}, hotbar: ["cutlass", "flintlock", null, null, null, null, null, null], selectedHotbarSlot: 0 };
}
interface PlayerRow {
  user_id: string; x: number; y: number; health: number; stamina: number; max_stamina: number; hunger: number; oxygen: number;
  xp: string; level: number; gold: string; inventory: Record<string, number>;
  hotbar: Array<string | null>; selected_hotbar_slot: number;
}
function rowToState(row: PlayerRow): PlayerState {
  return { userId: row.user_id, x: row.x, y: row.y, health: row.health, stamina: row.stamina, maxStamina: row.max_stamina, hunger: row.hunger, oxygen: row.oxygen,
    xp: Number(row.xp), level: row.level, gold: Number(row.gold), inventory: row.inventory ?? {},
    hotbar: row.hotbar ?? [null, null, null, null, null, null, null, null], selectedHotbarSlot: row.selected_hotbar_slot };
}
export class PlayerStore {
  private readonly active = new Map<string, PlayerState>();
  constructor(private readonly db: Pool) {}
  async loadOrCreate(userId: string): Promise<PlayerState> {
    await this.db.query(
      "INSERT INTO player_profiles (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING",
      [userId],
    );
    const result = await this.db.query<PlayerRow>(
      "SELECT user_id, x, y, health, stamina, max_stamina, hunger, oxygen, xp, level, gold, inventory, hotbar, selected_hotbar_slot FROM player_profiles WHERE user_id = $1",
      [userId],
    );
    const row = result.rows[0];
    if (!row) throw new Error("PLAYER_NOT_FOUND");
    const state = rowToState(row);
    this.active.set(userId, state);
    return state;
  }
  get(userId: string): PlayerState | undefined { return this.active.get(userId); }
  tick(dt: number): void { for (const state of this.active.values()) applyPlayerInput(state, { dx: 0, dy: 0, dt }); }
  async persist(userId: string): Promise<void> {
    const state = this.active.get(userId); if (!state) return;
    await this.db.query(
      "UPDATE player_profiles SET x=$2, y=$3, health=$4, stamina=$5, max_stamina=$6, hunger=$7, oxygen=$8, xp=$9, level=$10, gold=$11, inventory=$12::jsonb, hotbar=$13::jsonb, selected_hotbar_slot=$14, updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",
      [userId, state.x, state.y, state.health, state.hunger, state.oxygen, state.xp, state.level, state.gold,
        JSON.stringify(state.inventory), JSON.stringify(state.hotbar), state.selectedHotbarSlot]);
  }
  async purchase(userId: string, item: ShopItem, quantity: number, totalGold: number): Promise<PlayerState> {
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      const result = await client.query<PlayerRow>(
        "SELECT user_id, x, y, health, stamina, max_stamina, hunger, oxygen, xp, level, gold, inventory, hotbar, selected_hotbar_slot FROM player_profiles WHERE user_id = $1 FOR UPDATE",
        [userId],
      );
      const row = result.rows[0];
      if (!row) throw new Error("PLAYER_NOT_FOUND");
      const gold = Number(row.gold);
      if (!Number.isSafeInteger(gold) || gold < totalGold) throw new Error("INSUFFICIENT_GOLD");
      const inventory = row.inventory ?? {};
      const currentQuantity = Number(inventory[item.id] ?? 0);
      if (!Number.isSafeInteger(currentQuantity) || currentQuantity < 0 || currentQuantity + quantity > 1_000_000) {
        throw new Error("INVENTORY_LIMIT");
      }
      const nextInventory = { ...inventory, [item.id]: currentQuantity + quantity };
      const updated = await client.query<PlayerRow>(
        "UPDATE player_profiles SET gold=$2, inventory=$3::jsonb, updated_at=CURRENT_TIMESTAMP WHERE user_id=$1 RETURNING user_id, x, y, health, stamina, max_stamina, hunger, oxygen, xp, level, gold, inventory, hotbar, selected_hotbar_slot",
        [userId, gold - totalGold, JSON.stringify(nextInventory)],
      );
      await client.query("COMMIT");
      const state = rowToState(updated.rows[0]);
      this.active.set(userId, state);
      return state;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
  async unload(userId: string): Promise<void> { await this.persist(userId); this.active.delete(userId); }
  async persistAll(): Promise<void> {
    const userIds = [...this.active.keys()];
    for (const userId of userIds) await this.persist(userId);
  }
}
