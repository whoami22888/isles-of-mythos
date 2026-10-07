import type { PlayerState } from "./player.js";
import { isPlayerState } from "./player.js";
import type { WorldChunk } from "./world.js";

export interface ResourceNode { id:string; type:"wood"|"stone"|"herb"; x:number; y:number; }

export type GenericSystemResponseType =
  | "base_state" | "building_state" | "breeding_started" | "breeding_jobs"
  | "guild_state" | "guild_invitations" | "guild_bank_state" | "guild_operation_ok"
  | "realm_list" | "territory_list" | "fortress_list" | "territory_state" | "realm_reputation"
  | "trade_route_state" | "trade_route_list" | "realm_operation_ok"
  | "army_state" | "army_training" | "army_operation_ok" | "battle_state" | "defense_state" | "defense_list"
  | "ship_state" | "ship_list" | "ship_inventory" | "ship_crew" | "fleet_state" | "fleet_list" | "naval_combat_result"
  | "realm_war_list" | "realm_war_state" | "guild_battle_list" | "guild_battle_state"
  | "endgame_creature_list" | "endgame_creature_state" | "mythic_content_list" | "territory_season_state";

export type GenericSystemResponse = { type: GenericSystemResponseType; requestId: string; [key: string]: unknown };

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

export type WorldEventType="world_boss"|"treasure_storm"|"ghost_fleet"|"kraken"|"dragon_migration";
export interface WorldEventSummary { id:string; eventType:WorldEventType; status:"active"|"completed"|"expired"; regionId:number|null; centerX:number; centerY:number; maxHealth:string|null; currentHealth:string|null; state:Record<string,unknown>; startedAt:string; endsAt:string; }

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
  | { type:"resource_gathered"; requestId:string; resourceId:string; itemId:string; quantity:number; respawnsAt:string; state:PlayerState }
  | { type: "world_chunk"; requestId: string; chunk: WorldChunk }
  | ProjectileSpawnMessage
  | CombatResultMessage
  | { type: "creature_state"; requestId?: string; creature: CreatureState }
  | { type: "creature_party"; creatures: CreatureState[] }
  | { type: "craft_result"; requestId: string; recipeId: string; state: PlayerState }
  | { type: "shop_purchase_result"; requestId: string; transactionId: string; itemId: string; quantity: number; totalGold: string; state: PlayerState }
  | { type: "trade_result"; requestId: string; transactionId: string; from: EconomySnapshot; to: EconomySnapshot }
  | { type: "army_list"; requestId: string; armies: ArmySummary[] }
  | { type: "invasion_list"; requestId: string; invasions: InvasionSummary[] }
  | { type: "invasion_waves"; requestId: string; invasionId: string; waves: InvasionWave[] }
  | { type: "invasion_state"; requestId: string; invasion: InvasionSummary }
  | { type: "invasion_operation_ok"; requestId: string; invasionId: string }
  | { type:"world_event_list"; requestId:string; events:WorldEventSummary[] }
  | { type:"world_event_state"; requestId:string; event:WorldEventSummary }
  | { type:"world_event_reward"; requestId:string; eventId:string; gold:string; items:Record<string,number> }
  | { type: "friends_list"; requestId: string; friends: Record<string, unknown>[] }
  | { type: "blocks_list"; requestId: string; blockedUserIds: string[] }
  | { type: "social_operation_ok"; requestId: string }
  | { type: "social_reported"; requestId: string; reportId: string }
  | { type: "chat_message"; requestId: string; message: Record<string, unknown> }
  | { type: "chat_history"; requestId: string; messages: Record<string, unknown>[] }
  | { type: "party_state"; requestId: string; party: Record<string, unknown> | null }
  | { type: "party_invitations"; requestId: string; invitations: Record<string, unknown>[] }
  | { type: "party_operation_ok"; requestId: string }
  | { type: "auction_list"; requestId: string; listings: Record<string, unknown>[] }
  | { type: "auction_state"; requestId: string; listing: Record<string, unknown> }
  | { type: "auction_history"; requestId: string; transactions: Record<string, unknown>[] }
  | { type: "auction_operation_ok"; requestId: string }
  | GenericSystemResponse
  | { type: "error"; code: string };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isRecordArray(value: unknown): value is Record<string, unknown>[] { return Array.isArray(value) && value.every(isRecord); }

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

function isWorldChunk(value: unknown): value is WorldChunk {
  if (!isRecord(value)) return false;
  return typeof value.x === "number" && typeof value.y === "number" && typeof value.size === "number" &&
    Array.isArray(value.tiles) && value.tiles.every((tile) => typeof tile === "number") &&
    (value.resources === undefined || Array.isArray(value.resources) && value.resources.every((resource) => isRecord(resource) &&
      typeof resource.id === "string" && (resource.type === "wood" || resource.type === "stone" || resource.type === "herb") &&
      typeof resource.x === "number" && Number.isFinite(resource.x) && typeof resource.y === "number" && Number.isFinite(resource.y)));
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
    typeof value.max_health === "number" && Number.isSafeInteger(value.max_health) && value.max_health > 0 &&
    typeof value.current_health === "number" && Number.isSafeInteger(value.current_health) && value.current_health >= 0 && value.current_health <= value.max_health &&
    typeof value.attack === "number" && Number.isSafeInteger(value.attack) && value.attack > 0 &&
    typeof value.defense === "number" && Number.isSafeInteger(value.defense) && value.defense >= 0 &&
    typeof value.status === "string" && (value.status === "queued" || value.status === "active" || value.status === "defeated" || value.status === "retreated") &&
    typeof value.aggro_range === "number" && Number.isSafeInteger(value.aggro_range) && value.aggro_range >= 1 && value.aggro_range <= 100 &&
    (value.target_user_id === null || typeof value.target_user_id === "string");
}

function isWorldEvent(value: unknown): value is WorldEventSummary {
  if(!isRecord(value)) return false;
  const types=["world_boss","treasure_storm","ghost_fleet","kraken","dragon_migration"];
  const statuses=["active","completed","expired"];
  return typeof value.id==="string" && types.includes(value.eventType as string) && statuses.includes(value.status as string) &&
    (value.regionId===null || (typeof value.regionId==="number" && Number.isSafeInteger(value.regionId))) &&
    typeof value.centerX==="number" && Number.isSafeInteger(value.centerX) &&
    typeof value.centerY==="number" && Number.isSafeInteger(value.centerY) &&
    (value.maxHealth===null || typeof value.maxHealth==="string") &&
    (value.currentHealth===null || typeof value.currentHealth==="string") &&
    isRecord(value.state) && typeof value.startedAt==="string" && typeof value.endsAt==="string";
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
    case "resource_gathered":
      return typeof value.requestId==="string" && typeof value.resourceId==="string" && typeof value.itemId==="string" &&
        typeof value.quantity==="number" && Number.isSafeInteger(value.quantity) && value.quantity>0 && typeof value.respawnsAt==="string" && isPlayerState(value.state)
        ? {type:"resource_gathered",requestId:value.requestId,resourceId:value.resourceId,itemId:value.itemId,quantity:value.quantity,respawnsAt:value.respawnsAt,state:value.state} : null;
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
      return typeof value.requestId === "string" && typeof value.transactionId === "string" && typeof value.itemId === "string" && typeof value.quantity === "number" &&
        Number.isSafeInteger(value.quantity) && value.quantity > 0 && typeof value.totalGold === "string" && isPlayerState(value.state)
        ? { type:"shop_purchase_result", requestId:value.requestId, transactionId:value.transactionId, itemId:value.itemId, quantity:value.quantity, totalGold:value.totalGold, state:value.state } : null;
    case "trade_result": {
      const isSnapshot = (snapshot: unknown): snapshot is EconomySnapshot =>
        isRecord(snapshot) && typeof snapshot.userId === "string" && typeof snapshot.gold === "string" &&
        isRecord(snapshot.inventory) && Object.values(snapshot.inventory).every((quantity) => typeof quantity === "number" && Number.isSafeInteger(quantity) && quantity >= 0);
      return typeof value.requestId === "string" && typeof value.transactionId === "string" && isSnapshot(value.from) && isSnapshot(value.to)
        ? { type:"trade_result", requestId:value.requestId, transactionId:value.transactionId, from:value.from, to:value.to } : null;
    }
    case "army_list":
      return typeof value.requestId === "string" && Array.isArray(value.armies) && value.armies.every(isArmySummary)
        ? { type:"army_list", requestId:value.requestId, armies:value.armies } : null;
    case "world_event_list":
      return typeof value.requestId==="string" && Array.isArray(value.events) && value.events.every(isWorldEvent) ? {type:"world_event_list",requestId:value.requestId,events:value.events}:null;
    case "world_event_state":
      return typeof value.requestId==="string" && isWorldEvent(value.event) ? {type:"world_event_state",requestId:value.requestId,event:value.event}:null;
    case "world_event_reward":
      return typeof value.requestId==="string" && typeof value.eventId==="string" && typeof value.gold==="string" && isRecord(value.items) && Object.values(value.items).every((n)=>typeof n==="number" && Number.isSafeInteger(n) && n>0)
        ? {type:"world_event_reward",requestId:value.requestId,eventId:value.eventId,gold:value.gold,items:value.items as Record<string,number>}:null;
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
    case "friends_list":
      return typeof value.requestId==="string" && isRecordArray(value.friends) ? {type:"friends_list",requestId:value.requestId,friends:value.friends}:null;
    case "blocks_list":
      return typeof value.requestId==="string" && Array.isArray(value.blockedUserIds) && value.blockedUserIds.every((id)=>typeof id==="string") ? {type:"blocks_list",requestId:value.requestId,blockedUserIds:value.blockedUserIds}:null;
    case "social_operation_ok":
      return typeof value.requestId==="string" ? {type:"social_operation_ok",requestId:value.requestId}:null;
    case "social_reported":
      return typeof value.requestId==="string" && typeof value.reportId==="string" ? {type:"social_reported",requestId:value.requestId,reportId:value.reportId}:null;
    case "chat_message":
      return typeof value.requestId==="string" && isRecord(value.message) ? {type:"chat_message",requestId:value.requestId,message:value.message}:null;
    case "chat_history":
      return typeof value.requestId==="string" && isRecordArray(value.messages) ? {type:"chat_history",requestId:value.requestId,messages:value.messages}:null;
    case "party_state":
      return typeof value.requestId==="string" && (value.party===null || isRecord(value.party)) ? {type:"party_state",requestId:value.requestId,party:value.party}:null;
    case "party_invitations":
      return typeof value.requestId==="string" && isRecordArray(value.invitations) ? {type:"party_invitations",requestId:value.requestId,invitations:value.invitations}:null;
    case "party_operation_ok":
      return typeof value.requestId==="string" ? {type:"party_operation_ok",requestId:value.requestId}:null;
    case "auction_list":
      return typeof value.requestId==="string" && isRecordArray(value.listings) ? {type:"auction_list",requestId:value.requestId,listings:value.listings}:null;
    case "auction_state":
      return typeof value.requestId==="string" && isRecord(value.listing) ? {type:"auction_state",requestId:value.requestId,listing:value.listing}:null;
    case "auction_history":
      return typeof value.requestId==="string" && isRecordArray(value.transactions) ? {type:"auction_history",requestId:value.requestId,transactions:value.transactions}:null;
    case "auction_operation_ok":
      return typeof value.requestId==="string" ? {type:"auction_operation_ok",requestId:value.requestId}:null;
    case "combat_result":
      return typeof value.requestId === "string" && value.requestId.length > 0 && value.requestId.length <= 64 &&
        typeof value.targetId === "string" && typeof value.damage === "number" &&
        typeof value.critical === "boolean" && typeof value.killed === "boolean" && typeof value.targetHealth === "number" &&
        (value.status === undefined || typeof value.status === "string") &&
        (value.missed === undefined || typeof value.missed === "boolean")
        ? { type:"combat_result", requestId:value.requestId, targetId:value.targetId, damage:value.damage, critical:value.critical, killed:value.killed, targetHealth:value.targetHealth,
          ...(value.missed === undefined ? {} : { missed:value.missed }), ...(value.status === undefined ? {} : { status:value.status }) } : null;
    case "guild_operation_ok":
      return typeof value.requestId === "string" && typeof value.guildId === "string" &&
        (value.transactionId === undefined || typeof value.transactionId === "string" && (value.rewardTransactionIds === undefined || (Array.isArray(value.rewardTransactionIds) && value.rewardTransactionIds.every((id) => typeof id === "string"))))
        ? { type: "guild_operation_ok", requestId: value.requestId, guildId: value.guildId, ...(value.transactionId === undefined ? {} : { transactionId: value.transactionId }), ...(value.rewardTransactionIds === undefined ? {} : { rewardTransactionIds: value.rewardTransactionIds }) } : null;
    default: {
      const genericTypes = new Set<GenericSystemResponseType>([
        "base_state","building_state","breeding_started","breeding_jobs","guild_state","guild_invitations","guild_bank_state","guild_operation_ok",
        "realm_list","territory_list","fortress_list","territory_state","realm_reputation","trade_route_state","trade_route_list","realm_operation_ok",
        "army_state","army_training","army_operation_ok","battle_state","defense_state","defense_list","ship_state","ship_list","ship_inventory","ship_crew",
        "fleet_state","fleet_list","naval_combat_result","realm_war_list","realm_war_state","guild_battle_list","guild_battle_state",
        "endgame_creature_list","endgame_creature_state","mythic_content_list","territory_season_state",
      ]);
      return genericTypes.has(value.type as GenericSystemResponseType) &&
        typeof value.requestId === "string" && value.requestId.length > 0 && value.requestId.length <= 64
        ? value as GenericSystemResponse
        : null;
    }
  }
}
