import type { PlayerState } from "./player.js";
import { isPlayerState } from "./player.js";
import type { WorldChunk } from "./world.js";

export interface ProjectileSpawnMessage {
  type: "projectile_spawn";
  projectileId: string;
  ownerUserId: string;
  targetId: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  expiresAt: number;
}

export interface CombatResultMessage {
  type: "combat_result";
  requestId: string;
  targetId: string;
  damage: number;
  critical: boolean;
  killed: boolean;
  targetHealth: number;
  status?: string;
  missed?: boolean;
}

export interface CreatureState {
  id:string; species:string; nickname:string|null; level:number; health:number; maxHealth:number;
  tameProgress:number; partySlot:number|null; aiMode:"follow"|"assist"|"stay"; x:number; y:number;
}

export type EconomySnapshot = { userId: string; gold: string; inventory: Record<string, number> };

export type InvasionPhase="WARNING"|"MUSTER"|"ARRIVAL"|"ASSAULT"|"BATTLE"|"RESOLUTION"|"REWARD"|"COOLDOWN"|"COMPLETE";
export type InvasionRole="tank"|"damage"|"support"|"scout"|"commander"|"logistics";
export interface InvasionSummary {
  id:string; territoryId:string; sourceType:string; targetBaseId:string|null; phase:InvasionPhase;
  threatScore:number; outcome:string|null; phaseEndsAt:string;
}
export interface InvasionWave {
  id:string; wave_number:number; unit_type:string; category:string; quantity:number; max_health:number;
  current_health:number; attack:number; defense:number; status:string; aggro_range:number; target_user_id:string|null;
}
export interface ArmySummary {
  id:string; name:string; assignment:string; status:string;
}

export type ServerMessage =
  | { type: "server_ready"; timestamp: number }
  | { type: "pong"; timestamp: number }
  | { type: "auth_ok"; userId: string }
  | { type: "player_state"; state: PlayerState }
  | { type: "world_chunk"; requestId: string; chunk: WorldChunk }
  | ProjectileSpawnMessage
  | CombatResultMessage
  | { type: "creature_state"; requestId?: string; creature: CreatureState }
  | { type: "creature_party"; creatures: CreatureState[] }
  | { type: "craft_result"; requestId: string; recipeId: string; state: PlayerState }
  | { type: "shop_purchase_result"; requestId: string; itemId: string; quantity: number; totalGold: string; state: PlayerState }
  | { type: "trade_result"; requestId: string; from: EconomySnapshot; to: EconomySnapshot }
  | { type: "army_list"; requestId: string; armies: ArmySummary[] }
  | { type: "invasion_list"; requestId: string; invasions: InvasionSummary[] }
  | { type: "invasion_waves"; requestId: string; invasionId: string; waves: InvasionWave[] }
  | { type: "invasion_state"; requestId: string; invasion: InvasionSummary }
  | { type: "invasion_operation_ok"; requestId: string; invasionId: string }
  | { type: "error"; code: string };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

export function isCreatureState(value: unknown): value is CreatureState {
  if (!isRecord(value)) return false;
  return typeof value.id === "string" &&
    typeof value.species === "string" &&
    (value.nickname === null || typeof value.nickname === "string") &&
    typeof value.level === "number" &&
    typeof value.health === "number" &&
    typeof value.maxHealth === "number" &&
    typeof value.tameProgress === "number" &&
    (value.partySlot === null || typeof value.partySlot === "number") &&
    (value.aiMode === "follow" || value.aiMode === "assist" || value.aiMode === "stay") &&
    typeof value.x === "number" &&
    typeof value.y === "number";
}

function isWorldChunk(value: unknown): boolean {
  if (!isRecord(value)) return false;
  return typeof value.x === "number" && typeof value.y === "number" && typeof value.size === "number" &&
    Array.isArray(value.tiles) && value.tiles.every((tile) => typeof tile === "number");
}

function isInvasionSummary(value: unknown): value is InvasionSummary {
  if (!isRecord(value)) return false;
  const phases = ["WARNING","MUSTER","ARRIVAL","ASSAULT","BATTLE","RESOLUTION","REWARD","COOLDOWN","COMPLETE"];
  return typeof value.id === "string" && value.id.length > 0 &&
    typeof value.territoryId === "string" &&
    typeof value.sourceType === "string" &&
    (value.targetBaseId === null || typeof value.targetBaseId === "string") &&
    typeof value.phase === "string" && phases.includes(value.phase) &&
    typeof value.threatScore === "number" && Number.isSafeInteger(value.threatScore) &&
    (value.outcome === null || typeof value.outcome === "string") &&
    typeof value.phaseEndsAt === "string";
}

function isInvasionWave(value: unknown): value is InvasionWave {
  if (!isRecord(value)) return false;
  return typeof value.id === "string" && typeof value.wave_number === "number" && Number.isSafeInteger(value.wave_number) &&
    typeof value.unit_type === "string" && typeof value.category === "string" &&
    typeof value.quantity === "number" && Number.isSafeInteger(value.quantity) && value.quantity > 0 &&
    typeof value.max_health === "number" && Number.isSafeInteger(value.max_health) &&
    typeof value.current_health === "number" && Number.isSafeInteger(value.current_health) &&
    typeof value.attack === "number" && Number.isSafeInteger(value.attack) &&
    typeof value.defense === "number" && Number.isSafeInteger(value.defense) &&
    typeof value.status === "string" && typeof value.aggro_range === "number" && Number.isSafeInteger(value.aggro_range) &&
    (value.target_user_id === null || typeof value.target_user_id === "string");
}

function isArmySummary(value: unknown): value is ArmySummary {
  return isRecord(value) &&
    typeof value.id === "string" &&
    typeof value.name === "string" &&
    typeof value.assignment === "string" &&
    typeof value.status === "string";
}

export function parseServerMessage(value: unknown): ServerMessage | null {
  if (!isRecord(value) || typeof value.type !== "string") return null;
  switch (value.type) {
    case "server_ready":
      return typeof value.timestamp === "number" ? { type: "server_ready", timestamp: value.timestamp } : null;
    case "pong":
      return typeof value.timestamp === "number" ? { type: "pong", timestamp: value.timestamp } : null;
    case "auth_ok":
      return typeof value.userId === "string" ? { type: "auth_ok", userId: value.userId } : null;
    case "player_state":
      return isPlayerState(value.state) ? { type: "player_state", state: value.state } : null;
    case "world_chunk":
      return typeof value.requestId === "string" && isWorldChunk(value.chunk) ? { type: "world_chunk", requestId: value.requestId, chunk: value.chunk } : null;
    case "projectile_spawn":
      return typeof value.projectileId === "string" && typeof value.ownerUserId === "string" && typeof value.targetId === "string" &&
        typeof value.x === "number" && Number.isFinite(value.x) && typeof value.y === "number" && Number.isFinite(value.y) &&
        typeof value.vx === "number" && Number.isFinite(value.vx) && typeof value.vy === "number" && Number.isFinite(value.vy) &&
        typeof value.expiresAt === "number" && Number.isFinite(value.expiresAt)
        ? { type: "projectile_spawn", projectileId: value.projectileId, ownerUserId: value.ownerUserId, targetId: value.targetId, x: value.x, y: value.y, vx: value.vx, vy: value.vy, expiresAt: value.expiresAt }
        : null;
    case "creature_state":
      return isCreatureState(value.creature)
        ? { type:"creature_state", ...(typeof value.requestId === "string" ? { requestId:value.requestId } : {}), creature:value.creature }
        : null;
    case "creature_party":
      return Array.isArray(value.creatures) && value.creatures.every(isCreatureState) ? { type:"creature_party", creatures:value.creatures } : null;
    case "craft_result":
      return typeof value.requestId === "string" && typeof value.recipeId === "string" && isPlayerState(value.state)
        ? { type:"craft_result", requestId:value.requestId, recipeId:value.recipeId, state:value.state } : null;
    case "shop_purchase_result":
      return typeof value.requestId === "string" && typeof value.itemId === "string" && typeof value.quantity === "number" &&
        Number.isSafeInteger(value.quantity) && value.quantity > 0 && typeof value.totalGold === "string" && isPlayerState(value.state)
        ? { type:"shop_purchase_result", requestId:value.requestId, itemId:value.itemId, quantity:value.quantity, totalGold:value.totalGold, state:value.state } : null;
    case "trade_result": {
      const isSnapshot = (snapshot: unknown): snapshot is EconomySnapshot =>
        isRecord(snapshot) && typeof snapshot.userId === "string" && typeof snapshot.gold === "string" &&
        isRecord(snapshot.inventory) && Object.values(snapshot.inventory).every((quantity) => typeof quantity === "number" && Number.isSafeInteger(quantity) && quantity >= 0);
      return typeof value.requestId === "string" && isSnapshot(value.from) && isSnapshot(value.to)
        ? { type:"trade_result", requestId:value.requestId, from:value.from, to:value.to } : null;
    }
    case "army_list":
      return typeof value.requestId === "string" && Array.isArray(value.armies) && value.armies.every(isArmySummary)
        ? { type:"army_list", requestId:value.requestId, armies:value.armies } : null;
    case "invasion_list":
      return typeof value.requestId === "string" && Array.isArray(value.invasions) && value.invasions.every(isInvasionSummary)
        ? { type:"invasion_list", requestId:value.requestId, invasions:value.invasions } : null;
    case "invasion_waves":
      return typeof value.requestId === "string" && typeof value.invasionId === "string" && value.invasionId.length > 0 &&
        Array.isArray(value.waves) && value.waves.every(isInvasionWave)
        ? { type:"invasion_waves", requestId:value.requestId, invasionId:value.invasionId, waves:value.waves } : null;
    case "invasion_state":
      return typeof value.requestId === "string" && isInvasionSummary(value.invasion)
        ? { type:"invasion_state", requestId:value.requestId, invasion:value.invasion } : null;
    case "invasion_operation_ok":
      return typeof value.requestId === "string" && typeof value.invasionId === "string" && value.invasionId.length > 0
        ? { type:"invasion_operation_ok", requestId:value.requestId, invasionId:value.invasionId } : null;
    case "combat_result":
      return typeof value.requestId === "string" && value.requestId.length > 0 && value.requestId.length <= 64 &&
        typeof value.targetId === "string" && typeof value.damage === "number" &&
        typeof value.critical === "boolean" && typeof value.killed === "boolean" && typeof value.targetHealth === "number" &&
        (value.status === undefined || typeof value.status === "string") &&
        (value.missed === undefined || typeof value.missed === "boolean")
        ? { type:"combat_result", requestId:value.requestId, targetId:value.targetId, damage:value.damage, critical:value.critical, killed:value.killed, targetHealth:value.targetHealth,
          ...(value.missed === undefined ? {} : { missed:value.missed }), ...(value.status === undefined ? {} : { status:value.status }) } : null;
    case "error":
      return typeof value.code === "string" ? { type:"error", code:value.code } : null;
    default:
      return null;
  }
}
