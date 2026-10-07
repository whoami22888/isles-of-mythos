import Fastify, { type FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import rateLimit from "@fastify/rate-limit";
import swagger from "@fastify/swagger";
import swaggerUi from "@fastify/swagger-ui";
import websocket from "@fastify/websocket";
import type { WebSocket } from "ws";
import type { Pool } from "pg";
import { config } from "./config.js";
import { recordHttpRequest, recordTick, renderPrometheusMetrics, setActivePlayers, setDatabaseUp, setWebSocketAuthenticated, setWebSocketConnections } from "./metrics.js";
import { createDbPool } from "./db.js";
import { registerAuthRoutes } from "./auth.js";
import { log } from "./logger.js";
import { parseClientMessage, type ServerMessage } from "./protocol.js";
import { PlayerStore, applyPlayerInput, serializePlayerState } from "./player.js";
import { WorldChunkCache } from "./world.js";
import { SHOP_ITEMS, calculatePurchase, getShopItem, serializeShopItem } from "./shop.js";
import { craftRecipe } from "./crafting.js";
import { gatherResource, resourceGatherFingerprint } from "./resource-gathering.js";
import { tradePlayers } from "./trading.js";
import { addThreat, applyDamage, createCombatTarget, creatureAbilityDamage, createProjectile, advanceProjectile, isMeleeHit, distance, mitigateDamage, tickCreatureAi, tickStatusEffects, tickStatuses, weaponFor, type CombatProjectile, type CombatTarget, type StatusEffect } from "./combat.js";
import { CombatReplayCache } from "./combat-replay.js";
import { CAPTURE_HEALTH_RATIO, CreatureStore } from "./creature.js";
import { BaseStore, BASE_PERMISSIONS, BUILDING_TYPES, WORKER_MODES, type BasePermission, type BuildingType, type WorkerMode } from "./base.js";
import { BreedingStore } from "./breeding.js";
import { ShipStore, SHIP_CLASSES, CREW_ROLES, type ShipClass, type CrewRole } from "./ship.js";
import { NavalStore } from "./naval.js";
import { FleetStore } from "./fleet.js";
import { ShipInventoryStore } from "./ship-inventory.js";
import { GuildStore } from "./guild.js";
import { ArmyStore } from "./army.js";
import { RealmStore } from "./realm.js";
import { InvasionStore } from "./invasion.js";
import { SocialStore } from "./social.js";
import { AuctionStore } from "./auction.js";
import { WorldEventCoordinator } from "./world-events.js";
import { EndgameStore } from "./endgame.js";
import { TerritorySeasonStore } from "./territory-seasons.js";
import { registerFrontendRoutes } from "./frontend.js";
import { resolve } from "node:path";

function errorCode(error: unknown, fallback: string): string {
  return error instanceof Error ? error.message : fallback;
}

function send(socket: WebSocket, message: ServerMessage): void {
  if (socket.readyState === socket.OPEN) socket.send(JSON.stringify(message, (_key, value: unknown) => typeof value === "bigint" ? value.toString() : value));
}

function rawMessageToString(raw: WebSocket.RawData): string {
  if (typeof raw === "string") return raw;
  if (Buffer.isBuffer(raw)) return raw.toString("utf8");
  if (raw instanceof ArrayBuffer) return new TextDecoder().decode(new Uint8Array(raw));
  return Buffer.concat(raw).toString("utf8");
}

function parseCreatureTargetId(targetId: string): { x: number; y: number } | null {
  const match = /^creature:(-?\d{1,7}):(-?\d{1,7})$/.exec(targetId);
  if (!match) return null;
  const x = Number(match[1]);
  const y = Number(match[2]);
  if (!Number.isSafeInteger(x) || !Number.isSafeInteger(y) || Math.abs(x) > 1_000_000 || Math.abs(y) > 1_000_000) {
    return null;
  }
  return { x, y };
}

export interface BuildAppOptions {
  db?: Pool;
  clientDistDir?: string;
}

export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const clientDistDir = options.clientDistDir ?? resolve(process.cwd(), "client/dist");
  const db = options.db ?? createDbPool();
  const ownsDb = options.db === undefined;
  const world = new WorldChunkCache(256);
  const players = new PlayerStore(db);
  const creatures = new CreatureStore(db);
  const bases = new BaseStore(db);
  const breeding = new BreedingStore(db);
  const ships = new ShipStore(db);
  const naval = new NavalStore(db);
  const fleets = new FleetStore(db);
  const shipInventory = new ShipInventoryStore(db);
  const guilds = new GuildStore(db);
  const armies = new ArmyStore(db);
  const realms = new RealmStore(db);
  const social = new SocialStore(db);
  const auctions = new AuctionStore(db);
  const worldEvents = new WorldEventCoordinator(db, (userId) => players.get(userId)?.level);
  const endgame = new EndgameStore(db);
  const territorySeasons = new TerritorySeasonStore(db);
  const sockets = new Set<WebSocket>();
  const playerConnections = new Map<string, number>();
  const userSockets = new Map<string, Set<WebSocket>>();
  const invasions = new InvasionStore(db, (bounds) => {
    const active: string[] = [];
    for (const [userId, socketsForUser] of userSockets) {
      if (socketsForUser.size === 0) continue;
      const player = players.get(userId);
      if (player && player.x >= bounds.minX && player.x <= bounds.maxX && player.y >= bounds.minY && player.y <= bounds.maxY) active.push(userId);
    }
    return active;
  });
  const combatTargets = new Map<string, CombatTarget>();
  const defeatedCreatures = new Set<string>();
  const capturedWorldCreatures = new Set<string>();
  let capturedWorldCreaturesLoaded = false;
  const loadCapturedWorldCreatures = async (): Promise<void> => {
    const capturedRows = await db.query<{ wild_source_id: string }>("SELECT wild_source_id FROM player_creatures");
    capturedWorldCreatures.clear();
    for (const row of capturedRows.rows) capturedWorldCreatures.add(row.wild_source_id);
    capturedWorldCreaturesLoaded = true;
  };
  let capturedWorldCreaturesReady: Promise<void> | undefined;
  const ensureCapturedWorldCreaturesLoaded = (): Promise<void> => {
    if (!capturedWorldCreaturesReady) {
      capturedWorldCreaturesReady = loadCapturedWorldCreatures().catch((error) => {
        capturedWorldCreaturesReady = undefined;
        throw error;
      });
    }
    return capturedWorldCreaturesReady;
  };
  const visibleWorldChunk = (x: number, y: number) => {
    const chunk = world.get(x, y);
    if (capturedWorldCreatures.size === 0) return chunk;
    const creatures = chunk.creatures.filter((spawn) => !capturedWorldCreatures.has(spawn.id));
    return creatures.length === chunk.creatures.length ? chunk : { ...chunk, creatures };
  };
  const visibleClientWorldChunk = async (x: number, y: number) => {
    const chunk = visibleWorldChunk(x, y);
    if (chunk.resources.length === 0) return chunk;
    const resourceIds = chunk.resources.map((resource) => resource.id);
    const result = await db.query<{ node_id: string }>(
      "SELECT node_id FROM world_resource_nodes WHERE node_id = ANY($1::varchar[]) AND depleted_until > CURRENT_TIMESTAMP",
      [resourceIds],
    );
    if (result.rows.length === 0) return chunk;
    const depleted = new Set(result.rows.map((row) => row.node_id));
    const resources = chunk.resources.filter((resource) => !depleted.has(resource.id));
    return resources.length === chunk.resources.length ? chunk : { ...chunk, resources };
  };

  const projectiles = new Map<string, CombatProjectile>();
  const pendingCombatRequests = new Map<string, number>();
  const attackCooldowns = new Map<string, number>();
  const dodgeCooldowns = new Map<string, number>();
  const blocking = new Set<string>();
  const invulnerableUntil = new Map<string, number>();
  const playerStatuses = new Map<string, StatusEffect[]>();
  const combatActivationNextAt = new Map<string, number>();
  const combatReplay = new CombatReplayCache<Extract<ServerMessage, { type: "combat_result" }>>();
  const creatureReplay = new CombatReplayCache<ServerMessage>();
  const baseReplay = new CombatReplayCache<ServerMessage>();
  const economyReplay = new CombatReplayCache<ServerMessage>();
  const pendingBaseRequests = new Map<string, Promise<ServerMessage>>();
  const pendingEconomyRequests = new Map<string, Promise<ServerMessage>>();
  const pendingCreatureRequests = new Map<string, Promise<ServerMessage>>();
  const pendingCreatureOperations = new Map<string, Promise<void>>();
  const pendingPlayerUnloads = new Map<string, Promise<void>>();
  let shuttingDown = false;
  let authenticatedSocketCount = 0;
  const app = Fastify({ logger: false });

  app.addHook("onResponse", (_request, reply) => {
    recordHttpRequest(reply.elapsedTime, reply.statusCode);
  });

  app.setErrorHandler((error, request, reply) => {
    const statusCode = error !== null && typeof error === "object" && "statusCode" in error
      && typeof error.statusCode === "number" && error.statusCode >= 400 && error.statusCode < 600
      ? error.statusCode
      : 500;
    const clientError = statusCode === 400 ? "INVALID_REQUEST"
      : statusCode === 401 ? "UNAUTHORIZED"
      : statusCode === 403 ? "FORBIDDEN"
      : statusCode === 404 ? "NOT_FOUND"
      : statusCode === 405 ? "METHOD_NOT_ALLOWED"
      : statusCode === 409 ? "CONFLICT"
      : statusCode === 429 ? "RATE_LIMITED"
      : "HTTP_ERROR";
    log("http_request_failed", {
      method: request.method,
      url: request.url,
      statusCode,
      message: error instanceof Error ? error.message : String(error),
    });
    if (reply.sent) return;
    reply.code(statusCode).send({
      error: statusCode >= 500 ? "INTERNAL_SERVER_ERROR" : clientError,
      message: statusCode >= 500 ? "Internal server error" : clientError,
    });
  });

  app.get("/metrics", { schema: { tags: ["system"] }, config: { rateLimit: { max: 1200, timeWindow: "1 minute" } } }, async (_request, reply) => {
    try {
      await db.query("SELECT 1");
      setDatabaseUp(true);
    } catch {
      setDatabaseUp(false);
    }
    reply.type("text/plain; version=0.0.4").send(renderPrometheusMetrics());
  });

  async function runCreatureRequest(
    userId: string,
    requestId: string,
    fingerprint: string,
    operation: () => Promise<ServerMessage> | ServerMessage,
  ): Promise<ServerMessage> {
    const replay = creatureReplay.lookup(userId, requestId, fingerprint);
    if (replay.kind === "hit") return replay.response;
    if (replay.kind === "conflict") return { type: "error", code: "INVALID_MESSAGE" };
    const key = userId + ":" + requestId;
    const existing = pendingCreatureRequests.get(key);
    if (existing) return existing;
    const previous = pendingCreatureOperations.get(userId) ?? Promise.resolve();
    const task = previous.catch(() => undefined).then(async () => {
      const response = await operation();
      creatureReplay.remember(userId, requestId, fingerprint, response);
      return response;
    });
    const drain = task.then(() => undefined, () => undefined);
    pendingCreatureRequests.set(key, task);
    pendingCreatureOperations.set(userId, drain);
    try {
      return await task;
    } finally {
      if (pendingCreatureRequests.get(key) === task) pendingCreatureRequests.delete(key);
      if (pendingCreatureOperations.get(userId) === drain) pendingCreatureOperations.delete(userId);
    }
  }

  async function runEconomyRequest(
    userId: string,
    requestId: string,
    fingerprint: string,
    operation: () => Promise<ServerMessage> | ServerMessage,
  ): Promise<ServerMessage> {
    const replay = economyReplay.lookup(userId, requestId, fingerprint);
    if (replay.kind === "hit") return replay.response;
    if (replay.kind === "conflict") return { type: "error", code: "INVALID_MESSAGE" };
    const key = userId + ":" + requestId;
    const existing = pendingEconomyRequests.get(key);
    if (existing) return existing;
    const task = Promise.resolve().then(operation).then((response) => {
      economyReplay.remember(userId, requestId, fingerprint, response);
      return response;
    });
    pendingEconomyRequests.set(key, task);
    try { return await task; }
    finally {
      if (pendingEconomyRequests.get(key) === task) pendingEconomyRequests.delete(key);
    }
  }

  async function runBaseRequest(
    userId: string,
    requestId: string,
    fingerprint: string,
    operation: () => Promise<ServerMessage> | ServerMessage,
  ): Promise<ServerMessage> {
    const replay = baseReplay.lookup(userId, requestId, fingerprint);
    if (replay.kind === "hit") return replay.response;
    if (replay.kind === "conflict") return { type: "error", code: "INVALID_MESSAGE" };
    const key = userId + ":" + requestId;
    const existing = pendingBaseRequests.get(key);
    if (existing) return existing;
    const task = Promise.resolve().then(operation).then((response) => {
      baseReplay.remember(userId, requestId, fingerprint, response);
      return response;
    });
    pendingBaseRequests.set(key, task);
    try {
      return await task;
    } finally {
      if (pendingBaseRequests.get(key) === task) pendingBaseRequests.delete(key);
    }
  }

  function playerHasStatus(userId: string, statusId: StatusEffect["id"]): boolean {
    return (playerStatuses.get(userId) ?? []).some((status) => status.id === statusId && status.remainingMs > 0);
  }

  function applyPlayerStatus(userId: string, status: StatusEffect): void {
    const statuses = playerStatuses.get(userId) ?? [];
    const next = statuses.filter((entry) => entry.id !== status.id);
    next.push({ ...status });
    playerStatuses.set(userId, next);
  }

  function tickPlayerStatuses(dtMs: number): void {
    for (const [userId, statuses] of playerStatuses) {
      const player = players.get(userId);
      const result = tickStatusEffects(player?.health ?? 0, statuses, dtMs);
      if (player && result.damage > 0 && player.health > 0) {
        player.health = result.health;
        players.markDirty(userId);
        for (const socket of userSockets.get(userId) ?? []) send(socket, { type: "player_state", state: serializePlayerState(player) });
      }
      if (result.statuses.length === 0) playerStatuses.delete(userId);
      else playerStatuses.set(userId, result.statuses);
    }
  }

  await app.register(cors, {
    origin: (origin, callback) => {
      callback(null, origin === undefined || origin === config.corsOrigin);
    },
  });
  await app.register(rateLimit, { max: 120, timeWindow: "1 minute" });
  await app.register(swagger, {
    openapi: {
      openapi: "3.1.0",
      info: {
        title: "Isles of Mythos API",
        description: "Authoritative backend API for Isles of Mythos: Sunken Tides.",
        version: "0.1.0",
      },
      components: {
        securitySchemes: {
          bearerAuth: { type: "http", scheme: "bearer", bearerFormat: "JWT" },
        },
      },
    },
  });
  await app.register(swaggerUi, { routePrefix: "/documentation" });
  await app.register(websocket, {
    options: {
      maxPayload: config.websocketMaxPayloadBytes,
      perMessageDeflate: false,
    },
  });

  let heartbeat: ReturnType<typeof setInterval> | undefined;
  let survivalTick: ReturnType<typeof setInterval> | undefined;
  let breedingTick: ReturnType<typeof setInterval> | undefined;
  let navalFireTick: ReturnType<typeof setInterval> | undefined;
  let invasionTick: ReturnType<typeof setInterval> | undefined;
  let auctionTick: ReturnType<typeof setInterval> | undefined;
  let endgameTick: ReturnType<typeof setInterval> | undefined;
  let territorySeasonTick: ReturnType<typeof setInterval> | undefined;
  let worldEventTick: ReturnType<typeof setInterval> | undefined;
  let combatTick: ReturnType<typeof setInterval> | undefined;
  let persistenceTick: ReturnType<typeof setInterval> | undefined;

  app.addHook("onListen", () => {
  void ensureCapturedWorldCreaturesLoaded().catch((error) => {
    log("captured_world_creatures_load_failed", {
      message: error instanceof Error ? error.message : String(error),
    });
  });
  heartbeat = setInterval(() => {
    for (const socket of sockets) {
      if (socket.readyState === socket.OPEN) socket.ping();
    }
  }, 30_000);
  heartbeat.unref();

  survivalTick = setInterval(() => players.tick(1), 1_000);
  breedingTick = setInterval(() => { void breeding.completeDue().catch((error) => log("breeding_completion_failed",{message:error instanceof Error?error.message:String(error)})); }, 1_000);
  navalFireTick = setInterval(() => { void naval.tickFires().catch((error) => log("naval_fire_tick_failed",{message:error instanceof Error?error.message:String(error)})); }, 1_000);
  invasionTick = setInterval(() => { void invasions.tick().catch((error) => log("invasion_tick_failed",{message:error instanceof Error?error.message:String(error)})); }, 1_000);
  auctionTick = setInterval(() => { void auctions.tick().catch((error) => log("auction_tick_failed",{message:error instanceof Error ? error.message : String(error)})); }, 5_000);
  endgameTick = setInterval(() => {
    void Promise.all([endgame.tick(),endgame.spawnCreaturesIfNeeded()]).catch((error)=>log("endgame_tick_failed",{message:error instanceof Error?error.message:String(error)}));
  },5_000);
  territorySeasonTick = setInterval(() => { void territorySeasons.tick().catch((error)=>log("territory_season_tick_failed",{message:error instanceof Error?error.message:String(error)})); },60_000);
  worldEventTick = setInterval(() => {
    void worldEvents.tick().then(async(changed)=>{
      if(changed===0) return;
      const events=await worldEvents.listActive();
      for(const socket of sockets) send(socket,{type:"world_event_list",requestId:"system",events});
    }).catch((error)=>log("world_event_tick_failed",{message:error instanceof Error?error.message:String(error)}));
  },1_000);
  navalFireTick.unref();
  invasionTick.unref();
  auctionTick.unref();
  worldEventTick.unref();
  endgameTick.unref();
  territorySeasonTick.unref();
  survivalTick.unref();

  combatTick = setInterval(() => {
    const tickStartedAt = process.hrtime.bigint();
    const now = Date.now();
    tickPlayerStatuses(250);

    if (capturedWorldCreaturesLoaded) {
    for (const [connectedUserId, nextActivationAt] of combatActivationNextAt) {
        if (now < nextActivationAt) continue;
        const player = players.get(connectedUserId);
        if (!player || player.health <= 0 || !userSockets.has(connectedUserId)) {
          combatActivationNextAt.delete(connectedUserId);
          continue;
        }
        const centerChunkX = Math.floor(player.x / 32);
        const centerChunkY = Math.floor(player.y / 32);
        for (let chunkY = centerChunkY - 1; chunkY <= centerChunkY + 1; chunkY += 1) {
          for (let chunkX = centerChunkX - 1; chunkX <= centerChunkX + 1; chunkX += 1) {
            for (const spawn of visibleWorldChunk(chunkX, chunkY).creatures) {
              if (defeatedCreatures.has(spawn.id) || combatTargets.has(spawn.id)) continue;
              const activationDistance = Math.hypot(player.x - spawn.x, player.y - spawn.y);
              if (activationDistance <= 8) {
                combatTargets.set(spawn.id, createCombatTarget(spawn.id, spawn.species, spawn.x, spawn.y, spawn.level));
              }
            }
          }
        }
        combatActivationNextAt.set(connectedUserId, now + 500);
      }
      }
    for (const [projectileId, projectile] of projectiles) {
      const target = combatTargets.get(projectile.targetId);
      const requestId = projectileId.slice(projectileId.indexOf(":") + 1).replace(projectile.ownerUserId + ":", "");
      const replayKey = projectile.ownerUserId + ":" + requestId;
      if (!target) {
        projectiles.delete(projectileId);
        pendingCombatRequests.delete(replayKey);
        const missedResult: Extract<ServerMessage, { type: "combat_result" }> = {
          type: "combat_result", requestId, targetId: projectile.targetId,
          damage: 0, critical: false, killed: false, targetHealth: 0, missed: true,
        };
        combatReplay.remember(projectile.ownerUserId, requestId, projectile.replayFingerprint, missedResult, now);
        for (const socket of userSockets.get(projectile.ownerUserId) ?? []) send(socket, missedResult);
        continue;
      }
      const outcome = advanceProjectile(projectile, target, 0.05, now);
      if (outcome === "flying") continue;
      projectiles.delete(projectileId);
      pendingCombatRequests.delete(replayKey);
      if (outcome === "expired") {
        const missedResult: Extract<ServerMessage, { type: "combat_result" }> = {
          type: "combat_result", requestId, targetId: target.id,
          damage: 0, critical: false, killed: false, targetHealth: Math.ceil(target.health), missed: true,
        };
        combatReplay.remember(projectile.ownerUserId, requestId, projectile.replayFingerprint, missedResult, now);
        for (const socket of userSockets.get(projectile.ownerUserId) ?? []) send(socket, missedResult);
        continue;
      }
      const result = applyDamage(target, projectile.weapon);
      addThreat(target, projectile.ownerUserId, result.amount, now);
      const combatResult: Extract<ServerMessage, { type: "combat_result" }> = {
        type: "combat_result", requestId, targetId: target.id,
        damage: result.amount, critical: result.critical, killed: result.killed,
        targetHealth: Math.ceil(target.health), status: result.statusApplied?.id,
      };
      combatReplay.remember(projectile.ownerUserId, requestId, projectile.replayFingerprint, combatResult, now);
      for (const socket of userSockets.get(projectile.ownerUserId) ?? []) send(socket, combatResult);
      if (result.killed) {
        combatTargets.delete(target.id);
        defeatedCreatures.add(target.id);
      }
    }
    for (const [targetId, target] of combatTargets) {
      tickStatuses(target, 250);
      if (target.health <= 0) {
        target.aiState = "dead";
        combatTargets.delete(targetId);
        defeatedCreatures.add(targetId);
      }
    }
    for (const connectedUserId of userSockets.keys()) {
      const player = players.get(connectedUserId);
      if (player) creatures.tickAi(connectedUserId, player);
    }
    const candidates = [...userSockets.keys()].flatMap((userId) => {
      const state = players.get(userId);
      return state && state.health > 0 ? [{ userId, x: state.x, y: state.y }] : [];
    });
    recordTick(Number(process.hrtime.bigint() - tickStartedAt) / 1e6);
    for (const target of combatTargets.values()) {
      const ai = tickCreatureAi(target, candidates, now, 250);
      const userId = ai.targetUserId;
      if (!userId || target.health <= 0) continue;
      const targetPlayer = players.get(userId);
      if (!targetPlayer || targetPlayer.health <= 0) continue;
      if (ai.state === "chase") {
        const step = target.speed * 0.25;
        target.x += ai.moveX * step;
        target.y += ai.moveY * step;
      }
      if (ai.state === "attack" && distance(target, targetPlayer) <= target.attackRange && now >= target.nextAttackAt) {
        target.nextAttackAt = now + target.attackCooldownMs;
        const immune = (invulnerableUntil.get(userId) ?? 0) > now;
        if (!immune) {
          const blocked = blocking.has(userId) && targetPlayer.stamina > 0;
          const mitigatedDamage = mitigateDamage(target.attack, targetPlayer.defense);
          const damage = blocked ? Math.max(1, Math.round(mitigatedDamage * 0.35)) : mitigatedDamage;
          targetPlayer.health = Math.max(0, targetPlayer.health - damage);
          if (blocked) {
            targetPlayer.stamina = Math.max(0, targetPlayer.stamina - 4);
            if (targetPlayer.stamina === 0) blocking.delete(userId);
          }
          players.markDirty(userId);
          for (const socket of userSockets.get(userId) ?? []) send(socket, { type: "player_state", state: serializePlayerState(targetPlayer) });
        }
      }
      if (ai.ability && distance(target, targetPlayer) <= ai.ability.range) {
        const immune = (invulnerableUntil.get(userId) ?? 0) > now;
        if (!immune) {
          const pseudoTarget = createCombatTarget(userId, "player", targetPlayer.x, targetPlayer.y, targetPlayer.level);
          pseudoTarget.health = targetPlayer.health;
          pseudoTarget.maxHealth = targetPlayer.health;
          pseudoTarget.defense = targetPlayer.defense;
          const result = creatureAbilityDamage(pseudoTarget, ai.ability);
          targetPlayer.health = Math.max(0, targetPlayer.health - result.amount);
          if (result.statusApplied) applyPlayerStatus(userId, result.statusApplied);
          players.markDirty(userId);
          for (const socket of userSockets.get(userId) ?? []) send(socket, { type: "player_state", state: serializePlayerState(targetPlayer) });
        }
      }
    }
    for (const [key, expiresAt] of pendingCombatRequests) if (expiresAt <= now) pendingCombatRequests.delete(key);
    for (const [userId, until] of invulnerableUntil) if (until <= now) invulnerableUntil.delete(userId);
  }, 250);
  combatTick.unref();

  persistenceTick = setInterval(() => {
    void Promise.all([players.persistDirty(), creatures.persistDirty(), bases.processAll()]).catch((error) => {
      log("player_persistence_failed", {
        message: error instanceof Error ? error.message : String(error),
      });
    });
  }, 10_000);
  persistenceTick.unref();

  });
  
  app.addHook("onClose", async () => {
    if (invasionTick) clearInterval(invasionTick);
    if (auctionTick) clearInterval(auctionTick);
    if (worldEventTick) clearInterval(worldEventTick);
    if (endgameTick) clearInterval(endgameTick);
    if (territorySeasonTick) clearInterval(territorySeasonTick);
    shuttingDown = true;
    if (heartbeat) clearInterval(heartbeat);
    if (survivalTick) clearInterval(survivalTick);
    if (breedingTick) clearInterval(breedingTick);
    if (navalFireTick) clearInterval(navalFireTick);
    if (persistenceTick) clearInterval(persistenceTick);
    if (combatTick) clearInterval(combatTick);
    await players.persistAll();
    await creatures.persistAll();
    await bases.processAll();
    for (const socket of sockets) socket.close(1001, "server_shutdown");
    if (ownsDb) await db.end();
  });

  app.get("/health", { schema: { tags: ["system"] }, config: { rateLimit: { max: 1000, timeWindow: "1 minute" } } }, () => ({
    status: "ok",
    service: "isles-of-mythos-server",
    environment: config.environment,
  }));

  app.get("/ready", { schema: { tags: ["system"] } }, async (_request, reply) => {
    try {
      await db.query("SELECT 1");
      return { status: "ready", database: "ok", worldCacheChunks: world.size };
    } catch (error) {
      log("database_readiness_failed", {
        message: error instanceof Error ? error.message : String(error),
      });
      return reply.code(503).send({ status: "not_ready", database: "unavailable" });
    }
  });

  app.get<{ Params: { x: string; y: string } }>(
    "/world/chunks/:x/:y",
    {
      schema: {
        tags: ["world"],
        params: {
          type: "object",
          required: ["x", "y"],
          properties: {
            x: { type: "string", pattern: "^-?\\d{1,6}$" },
            y: { type: "string", pattern: "^-?\\d{1,6}$" },
          },
        },
      },
    },
    async (request, reply) => {
      await ensureCapturedWorldCreaturesLoaded();
      const x = Number(request.params.x);
      const y = Number(request.params.y);
      if (!Number.isSafeInteger(x) || !Number.isSafeInteger(y)) {
        return reply.code(400).send({ error: "INVALID_CHUNK_COORDINATE" });
      }
      return visibleClientWorldChunk(x, y);
    },
  );

  await registerAuthRoutes(app, db);

  app.get("/shop/catalog", { schema: { tags: ["shop"] } }, () => ({
    items: SHOP_ITEMS.map(serializeShopItem),
  }));

  app.post<{ Body: { requestId: string; itemId: string; quantity: number } }>(
    "/shop/purchase",
    {
      schema: {
        tags: ["shop"],
        security: [{ bearerAuth: [] }],
        body: {
          type: "object",
          required: ["requestId", "itemId", "quantity"],
          additionalProperties: false,
          properties: {
            requestId: { type: "string", minLength: 1, maxLength: 64 },
            itemId: { type: "string", minLength: 1, maxLength: 64 },
            quantity: { type: "integer", minimum: 1, maximum: 100 },
          },
        },
      },
    },
    async (request, reply) => {
      try {
        await request.jwtVerify();
      } catch {
        return reply.code(401).send({ error: "UNAUTHORIZED", message: "Invalid credentials" });
      }

      try {
        const userId = request.user.sub;
        const item = getShopItem(request.body.itemId);
        if (!item) return reply.code(404).send({ error: "SHOP_ITEM_NOT_FOUND" });
        const totalGold = calculatePurchase(item, request.body.quantity);
        if (totalGold === null) return reply.code(400).send({ error: "INVALID_PURCHASE_QUANTITY" });
        await players.loadOrCreate(userId);
        const purchase = await players.purchase(userId, request.body.requestId, item, request.body.quantity, totalGold);
        return { requestId: request.body.requestId, transactionId: purchase.transactionId, itemId: item.id, quantity: request.body.quantity, totalGold: totalGold.toString(), state: purchase.state };
      } catch (error) {
        if (error instanceof Error && error.message === "INSUFFICIENT_GOLD") {
          return reply.code(409).send({ error: "INSUFFICIENT_GOLD" });
        }
        if (error instanceof Error && error.message === "PLAYER_NOT_FOUND") {
          return reply.code(404).send({ error: "PLAYER_NOT_FOUND" });
        }
        if (error instanceof Error && error.message === "INVENTORY_LIMIT") {
          return reply.code(409).send({ error: "INVENTORY_LIMIT" });
        }
        if (error instanceof Error && error.message === "SHOP_REQUEST_CONFLICT") {
          return reply.code(409).send({ error: "SHOP_REQUEST_CONFLICT" });
        }
        if (error instanceof Error && error.message === "INVALID_REQUEST_ID") {
          return reply.code(400).send({ error: "INVALID_REQUEST_ID" });
        }
        return reply.code(500).send({ error: "PURCHASE_FAILED" });
      }
    },
  );

  app.get("/ws", { websocket: true, config: { rateLimit: { max: 2000, timeWindow: "1 minute" } } }, (socket: WebSocket) => {
    sockets.add(socket);
    setWebSocketConnections(sockets.size);
    let userId: string | null = null;
    let messageWindowStartedAt = Date.now();
    let messageWindowCount = 0;
    let authDeadline: NodeJS.Timeout | null = setTimeout(() => {
      if (!userId && socket.readyState === socket.OPEN) socket.close(1008, "authentication_timeout");
    }, 10_000);
    authDeadline.unref();

    send(socket, { type: "server_ready", timestamp: Date.now() });

    let messageQueue = Promise.resolve();
    socket.on("message", (raw) => {
      const now = Date.now();
      if (now - messageWindowStartedAt >= 1_000) {
        messageWindowStartedAt = now;
        messageWindowCount = 0;
      }
      messageWindowCount += 1;
      if (messageWindowCount > 120) {
        send(socket, { type: "error", code: "RATE_LIMITED" });
        return;
      }
      messageQueue = messageQueue.then(async () => {
        const message = parseClientMessage(rawMessageToString(raw));

        if (!message) {
          send(socket, { type: "error", code: "INVALID_MESSAGE" });
          return;
        }

        if (message.type === "ping") {
          send(socket, { type: "pong", timestamp: Date.now() });
          return;
        }

        if (message.type === "auth") {
          try {
            if (userId) {
              send(socket, { type: "error", code: "INVALID_MESSAGE" });
              return;
            }
            const payload = app.jwt.verify<{ sub: string; username: string }>(message.token);
            if (typeof payload.sub !== "string" || payload.sub.length === 0) throw new Error("invalid_subject");
            const authenticatedUserId = payload.sub;
            const pendingUnload = pendingPlayerUnloads.get(authenticatedUserId);
            if (pendingUnload) await pendingUnload;
            const state = await players.loadOrCreate(authenticatedUserId);
            const ownedCreatures = await creatures.load(authenticatedUserId);
            const base = await bases.load(authenticatedUserId);
            userId = authenticatedUserId;
            if (authDeadline) {
              clearTimeout(authDeadline);
              authDeadline = null;
            }
            const connections = playerConnections.get(authenticatedUserId) ?? 0;
            playerConnections.set(authenticatedUserId, connections + 1);
            combatActivationNextAt.set(authenticatedUserId, Date.now());
            const socketsForUser = userSockets.get(authenticatedUserId) ?? new Set<WebSocket>();
            socketsForUser.add(socket);
            userSockets.set(authenticatedUserId, socketsForUser);
            authenticatedSocketCount += 1;
            setWebSocketAuthenticated(authenticatedSocketCount);
            setActivePlayers(userSockets.size);
            send(socket, { type: "auth_ok", userId: authenticatedUserId });
            send(socket, { type: "player_state", state: serializePlayerState(state) });
            send(socket, { type: "creature_party", creatures: ownedCreatures });
            if (base) send(socket, { type: "base_state", base });
          } catch {
            userId = null;
            send(socket, { type: "error", code: "INVALID_TOKEN" });
            socket.close(1008, "invalid_token");
          }
          return;
        }

        if (message.type === "move") {
          if (!userId) {
            send(socket, { type: "error", code: "AUTH_REQUIRED" });
            return;
          }
          const state = players.get(userId);
          if (!state) {
            send(socket, { type: "error", code: "AUTH_REQUIRED" });
            return;
          }
          if (state.health <= 0) {
            send(socket, { type: "error", code: "PLAYER_DEAD" });
            return;
          }
          if (playerHasStatus(userId, "stun")) {
            send(socket, { type: "error", code: "PLAYER_STUNNED" });
            return;
          }
          const slow = (playerStatuses.get(userId) ?? []).find((status) => status.id === "slow");
          applyPlayerInput(state, { ...message, speedMultiplier: slow ? Math.max(0, Math.min(1, 1 - slow.magnitude)) : 1 });
          players.markDirty(userId);
          send(socket, { type: "player_state", state: serializePlayerState(state) });
          return;
        }

        if (message.type === "select_hotbar") {
          if (!userId) {
            send(socket, { type: "error", code: "AUTH_REQUIRED" });
            return;
          }
          const state = players.get(userId);
          if (!state) {
            send(socket, { type: "error", code: "AUTH_REQUIRED" });
            return;
          }
          if (state.health <= 0) {
            send(socket, { type: "error", code: "PLAYER_DEAD" });
            return;
          }
          state.selectedHotbarSlot = message.slot;
          players.markDirty(userId);
          send(socket, { type: "player_state", state: serializePlayerState(state) });
          return;
        }

        if (message.type === "attack") {
          if (!userId) {
            send(socket, { type: "error", code: "AUTH_REQUIRED" });
            return;
          }
          const state = players.get(userId);
          if (!state) {
            send(socket, { type: "error", code: "AUTH_REQUIRED" });
            return;
          }
          if (state.health <= 0) {
            send(socket, { type: "error", code: "PLAYER_DEAD" });
            return;
          }
          if (playerHasStatus(userId, "stun")) {
            send(socket, { type: "error", code: "PLAYER_STUNNED" });
            return;
          }
          const replayFingerprint = message.targetId + "|" + message.facingX + "|" + message.facingY + "|" + state.selectedHotbarSlot;
          const replay = combatReplay.lookup(userId, message.requestId, replayFingerprint);
          const pendingKey = userId + ":" + message.requestId;
          if (replay.kind === "hit") {
            send(socket, replay.response);
            return;
          }
          if (replay.kind === "conflict") {
            send(socket, { type: "error", code: "INVALID_MESSAGE" });
            return;
          }
          if (pendingCombatRequests.has(pendingKey)) {
            send(socket, { type: "error", code: "COMBAT_IN_PROGRESS" });
            return;
          }
          const weapon = weaponFor(state.hotbar[state.selectedHotbarSlot]);
          if (!weapon) {
            send(socket, { type: "error", code: "INVALID_MESSAGE" });
            return;
          }
          const ammoType = weapon.ammoType;
          if (ammoType && (Number(state.inventory[ammoType] ?? 0) < 1)) {
            send(socket, { type: "error", code: "NO_AMMO" });
            return;
          }
          const now = Date.now();
          const nextAttack = attackCooldowns.get(userId) ?? 0;
          if (now < nextAttack) {
            send(socket, { type: "error", code: "COMBAT_COOLDOWN" });
            return;
          }
          if (state.stamina < weapon.staminaCost) {
            send(socket, { type: "error", code: "NO_STAMINA" });
            return;
          }
          const targetCoordinates = parseCreatureTargetId(message.targetId);
          if (!targetCoordinates) {
            send(socket, { type: "error", code: "INVALID_MESSAGE" });
            return;
          }
          const targetX = targetCoordinates.x;
          const targetY = targetCoordinates.y;
          const chunk = world.get(Math.floor(targetX / 32), Math.floor(targetY / 32));
          const spawn = chunk.creatures.find((creature) => creature.id === message.targetId);
          if (!spawn) {
            send(socket, { type: "error", code: "INVALID_MESSAGE" });
            return;
          }
          if (defeatedCreatures.has(message.targetId)) {
            send(socket, { type: "error", code: "INVALID_MESSAGE" });
            return;
          }
          let target = combatTargets.get(message.targetId);
          if (!target) {
            target = createCombatTarget(spawn.id, spawn.species, spawn.x, spawn.y, spawn.level);
            combatTargets.set(target.id, target);
          }
          if (distance(state, target) > weapon.range) {
            send(socket, { type: "error", code: "OUT_OF_RANGE" });
            return;
          }
          const facingLength = Math.hypot(message.facingX, message.facingY) || 1;
          if (weapon.delivery === "melee" && !isMeleeHit(state, target, message.facingX, message.facingY, weapon.range)) {
            send(socket, { type: "error", code: "OUT_OF_RANGE" });
            return;
          }
          if (weapon.delivery === "projectile") {
            const projectileId = "projectile:" + userId + ":" + message.requestId;
            const projectile = createProjectile(projectileId, userId, target, state, message.facingX / facingLength, message.facingY / facingLength, weapon, now, replayFingerprint);
            if (!projectile) {
              send(socket, { type: "error", code: "INVALID_MESSAGE" });
              return;
            }
            attackCooldowns.set(userId, now + weapon.cooldownMs);
            state.stamina -= weapon.staminaCost;
            if (ammoType) {
              try {
                await players.consumeInventory(userId, ammoType, 1);
              } catch (error) {
                if (error instanceof Error && error.message === "INSUFFICIENT_INVENTORY") {
                  send(socket, { type: "error", code: "NO_AMMO" });
                  return;
                }
                throw error;
              }
            }
            players.markDirty(userId);
            projectiles.set(projectileId, projectile);
            pendingCombatRequests.set(pendingKey, projectile.expiresAt);
            for (const ownerSocket of userSockets.get(userId) ?? []) send(ownerSocket, {
              type: "projectile_spawn", projectileId, ownerUserId: userId, targetId: target.id,
              x: projectile.x, y: projectile.y, vx: projectile.vx, vy: projectile.vy, expiresAt: projectile.expiresAt,
            });
            return;
          }
          attackCooldowns.set(userId, now + weapon.cooldownMs);
          state.stamina -= weapon.staminaCost;
          players.markDirty(userId);
          const result = applyDamage(target, weapon);
          addThreat(target, userId, result.amount, now);
          const combatResult: Extract<ServerMessage, { type: "combat_result" }> = {
            type: "combat_result", requestId: message.requestId, targetId: target.id, damage: result.amount,
            critical: result.critical, killed: result.killed, targetHealth: Math.ceil(target.health), status: result.statusApplied?.id,
          };
          combatReplay.remember(userId, message.requestId, replayFingerprint, combatResult);
          send(socket, combatResult);
          if (result.killed) {
            combatTargets.delete(target.id);
            defeatedCreatures.add(target.id);
          }
          return;
        }

        if (message.type === "dodge") {
          if (!userId) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
          const state = players.get(userId);
          if (!state) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
          if (state.health <= 0) { send(socket, { type: "error", code: "PLAYER_DEAD" }); return; }
          if (playerHasStatus(userId, "stun")) { send(socket, { type: "error", code: "PLAYER_STUNNED" }); return; }
          const now = Date.now();
          if ((dodgeCooldowns.get(userId) ?? 0) > now) { send(socket, { type: "error", code: "COMBAT_COOLDOWN" }); return; }
          if (state.stamina < 20) { send(socket, { type: "error", code: "NO_STAMINA" }); return; }
          const length = Math.hypot(message.facingX, message.facingY) || 1;
          state.x = Math.max(-1_000_000, Math.min(1_000_000, state.x + (message.facingX / length) * 1.25));
          state.y = Math.max(-1_000_000, Math.min(1_000_000, state.y + (message.facingY / length) * 1.25));
          state.stamina -= 20;
          players.markDirty(userId);
          dodgeCooldowns.set(userId, now + 900);
          invulnerableUntil.set(userId, now + 350);
          send(socket, { type: "player_state", state: serializePlayerState(state) });
          return;
        }

        if (message.type === "block") {
          if (!userId) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
          const state = players.get(userId);
          if (!state) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
          if (state.health <= 0) { send(socket, { type: "error", code: "PLAYER_DEAD" }); return; }
          if (playerHasStatus(userId, "stun")) { send(socket, { type: "error", code: "PLAYER_STUNNED" }); return; }
          if (message.active && state.stamina <= 0) { send(socket, { type: "error", code: "NO_STAMINA" }); return; }
          if (message.active) blocking.add(userId); else blocking.delete(userId);
          players.markDirty(userId);
          return;
        }

        if (message.type === "capture") {
          if (!userId) { send(socket,{type:"error",code:"AUTH_REQUIRED"}); return; }
          const authenticatedUserId=userId;
          const captureFingerprint=message.type+"|"+message.targetId;
          const captureReplay=creatureReplay.lookup(authenticatedUserId,message.requestId,captureFingerprint);
          if(captureReplay.kind==="hit"){send(socket,captureReplay.response);return;}
          if(captureReplay.kind==="conflict"){send(socket,{type:"error",code:"INVALID_MESSAGE"});return;}
          const pendingCapture=pendingCreatureRequests.get(authenticatedUserId+":"+message.requestId);
          if(pendingCapture){send(socket,await pendingCapture);return;}
          const state=players.get(authenticatedUserId); if(!state){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          if(state.health<=0){send(socket,{type:"error",code:"PLAYER_DEAD"});return;}
          const coords=parseCreatureTargetId(message.targetId);
          if(!coords){send(socket,{type:"error",code:"INVALID_MESSAGE"});return;}
          await ensureCapturedWorldCreaturesLoaded();
          const chunk=visibleWorldChunk(Math.floor(coords.x/32),Math.floor(coords.y/32));
          const spawn=chunk.creatures.find(c=>c.id===message.targetId);
          if(!spawn||defeatedCreatures.has(message.targetId)){send(socket,{type:"error",code:"INVALID_MESSAGE"});return;}
          let target=combatTargets.get(message.targetId);
          if(!target){target=createCombatTarget(spawn.id,spawn.species,spawn.x,spawn.y,spawn.level);combatTargets.set(target.id,target);}
          if(distance(state,target)>2.5){send(socket,{type:"error",code:"OUT_OF_RANGE"});return;}
          if(target.health>target.maxHealth*CAPTURE_HEALTH_RATIO){send(socket,{type:"error",code:"CREATURE_TOO_HEALTHY"});return;}
          const fingerprint=captureFingerprint;
          const response=await runCreatureRequest(authenticatedUserId,message.requestId,fingerprint,async()=>{
            try{
              return await players.runExclusive(authenticatedUserId, async()=>{
                const creature=await creatures.capture(authenticatedUserId,target);
                await players.reloadEconomy(authenticatedUserId);
                combatTargets.delete(target.id); defeatedCreatures.add(target.id); capturedWorldCreatures.add(target.id);
                const result: ServerMessage={type:"creature_state",requestId:message.requestId,creature};
                for(const ownerSocket of userSockets.get(authenticatedUserId)??[])send(ownerSocket,result);
                return result;
              });
            }catch(error){
              const code=errorCode(error, "CAPTURE_FAILED");
              if(code==="NO_CAPTURE_ORB")return {type:"error",code:"NO_CAPTURE_ORB"};
              if(code==="CREATURE_ALREADY_CAPTURED")return {type:"error",code:"CREATURE_ALREADY_CAPTURED"};
              if(code==="POPULATION_LIMIT_REACHED")return {type:"error",code:"POPULATION_LIMIT_REACHED"};
              throw error;
            }
          });
          if(response.type==="error"||response.type==="creature_state")send(socket,response);
          return;
        }

        if (message.type === "tame") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;
          const response=await runCreatureRequest(authenticatedUserId,message.requestId,message.type+"|"+message.creatureId,async()=>{
            try{
              return await players.runExclusive(authenticatedUserId, async()=>{
                const result=await creatures.tame(authenticatedUserId,message.creatureId);
                if(result.consumed) await players.reloadEconomy(authenticatedUserId);
                return {type:"creature_state",requestId:message.requestId,creature:result.creature};
              });
            }catch(error){
              const code=errorCode(error, "TAME_FAILED");
              if(code==="CREATURE_NOT_FOUND")return {type:"error",code:"CREATURE_NOT_FOUND"};
              if(code==="NO_CREATURE_FEED")return {type:"error",code:"NO_CREATURE_FEED"};
              throw error;
            }
          });
          send(socket,response);
          return;
        }

        if (message.type === "set_creature_party") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;
          const response=await runCreatureRequest(authenticatedUserId,message.requestId,message.type+"|"+message.creatureId+"|"+String(message.slot),async()=>{
            try{
              const creature=await creatures.setPartySlot(authenticatedUserId,message.creatureId,message.slot);
              return {type:"creature_state",requestId:message.requestId,creature};
            }catch(error){
              const code=errorCode(error, "PARTY_UPDATE_FAILED");
              if(code==="CREATURE_NOT_FOUND")return {type:"error",code:"CREATURE_NOT_FOUND"};
              if(code==="CREATURE_NOT_TAMED")return {type:"error",code:"CREATURE_NOT_TAMED"};
              if(code==="INVALID_PARTY_SLOT")return {type:"error",code:"INVALID_PARTY_SLOT"};
              throw error;
            }
          });
          send(socket,response);
          if(response.type==="creature_state")send(socket,{type:"creature_party",creatures:creatures.get(authenticatedUserId)});
          return;
        }

        if (message.type === "set_creature_ai") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;
          const response=await runCreatureRequest(authenticatedUserId,message.requestId,message.type+"|"+message.creatureId+"|"+message.mode,()=>{
            try{
              const creature=creatures.setAiMode(authenticatedUserId,message.creatureId,message.mode);
              return {type:"creature_state",requestId:message.requestId,creature};
            }catch(error){
              const code=errorCode(error, "CREATURE_AI_UPDATE_FAILED");
              if(code==="CREATURE_NOT_FOUND")return {type:"error",code:"CREATURE_NOT_FOUND"};
              if(code==="CREATURE_NOT_TAMED")return {type:"error",code:"CREATURE_NOT_TAMED"};
              throw error;
            }
          });
          send(socket,response);
          return;
        }

        if (message.type === "create_base") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;
          const response=await runBaseRequest(authenticatedUserId,message.requestId,"create_base|"+message.name+"|"+message.x+"|"+message.y,async()=>{
            try{
              const base=await bases.create(authenticatedUserId,message.name,message.x,message.y);
              return {type:"base_state",base};
            }catch(error){const code=errorCode(error,"BASE_CREATE_FAILED"); const allowed=["BASE_ALREADY_EXISTS","INVALID_BASE_COORDINATES","BASE_CREATE_FAILED"]; return {type:"error",code:(allowed.includes(code)?code:"BASE_CREATE_FAILED") as "BASE_ALREADY_EXISTS"|"INVALID_BASE_COORDINATES"|"BASE_CREATE_FAILED"};}
          });
          send(socket,response);
          return;
        }

        if (message.type === "build") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;
          const response=await runBaseRequest(authenticatedUserId,message.requestId,"build|"+message.buildingType+"|"+message.level+"|"+message.gridX+"|"+message.gridY,async()=>{
            try{
              if(!BUILDING_TYPES.includes(message.buildingType as BuildingType))throw new Error("INVALID_BUILDING_TYPE");
              const building=await bases.createBuilding(authenticatedUserId,message.buildingType as BuildingType,message.level,message.gridX,message.gridY);
              return {type:"building_state",requestId:message.requestId,building};
            }catch(error){const code=errorCode(error,"BUILD_FAILED"); const allowed=["BASE_NOT_FOUND","BASE_PERMISSION_DENIED","INVALID_BUILDING_TYPE","INVALID_BUILDING_LEVEL","INVALID_BUILDING_POSITION","BUILDING_POSITION_OCCUPIED","BUILDING_PREREQUISITE_MISSING","INSUFFICIENT_STORAGE","BUILD_FAILED","WORKER_CAPACITY_REACHED"]; return {type:"error",code:(allowed.includes(code)?code:"BUILD_FAILED") as "BASE_NOT_FOUND"|"BASE_PERMISSION_DENIED"|"INVALID_BUILDING_TYPE"|"INVALID_BUILDING_LEVEL"|"INVALID_BUILDING_POSITION"|"BUILDING_POSITION_OCCUPIED"|"BUILDING_PREREQUISITE_MISSING"|"INSUFFICIENT_STORAGE"|"BUILD_FAILED"|"WORKER_CAPACITY_REACHED"};}
          });
          send(socket,response);
          return;
        }

        if (message.type === "upgrade_building" || message.type === "storage" || message.type === "set_base_permission" || message.type === "assign_worker" || message.type === "set_work_priorities") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;
          const fingerprint=message.type+"|"+JSON.stringify(message);
          const response=await runBaseRequest(authenticatedUserId,message.requestId,fingerprint,async()=>{
            try{
              if(message.type==="upgrade_building"){
                const building=await bases.upgradeBuilding(authenticatedUserId,message.buildingId);
                return {type:"building_state",requestId:message.requestId,building};
              }
              if(message.type==="storage"){
                const storage=await bases.mutateStorage(authenticatedUserId,message.changes);
                return {type:"base_state",base:{...(bases.get(authenticatedUserId)??{}),storage}};
              }
              if(message.type==="set_base_permission"){
                if(!BASE_PERMISSIONS.includes(message.permission as BasePermission))throw new Error("BASE_PERMISSION_DENIED");
                const base=await bases.setPermission(authenticatedUserId,message.targetUserId,message.permission as BasePermission,message.enabled);
                return {type:"base_state",base};
              }
              if(message.type==="assign_worker"){
                if(!WORKER_MODES.includes(message.task as WorkerMode))throw new Error("INVALID_WORK_TASK");
                await bases.assignWorker(authenticatedUserId,message.creatureId,message.buildingId,message.task as WorkerMode);
                return {type:"base_state",base:bases.get(authenticatedUserId)};
              }
              const base=await bases.setWorkPriorities(authenticatedUserId,message.priorities);
              return {type:"base_state",base};
            }catch(error){
              const code=errorCode(error,"BASE_CREATE_FAILED");
              const allowed=["BASE_NOT_FOUND","BASE_PERMISSION_DENIED","BUILDING_NOT_FOUND","BUILDING_MAX_LEVEL","BUILDING_PREREQUISITE_MISSING","INSUFFICIENT_STORAGE","STORAGE_CAPACITY_EXCEEDED","INVALID_STORAGE_QUANTITY","INSUFFICIENT_INVENTORY","PLAYER_NOT_FOUND","INVALID_WORK_TASK","CREATURE_NOT_FOUND","CREATURE_NOT_TAMED","CREATURE_IN_PARTY","UPGRADE_FAILED","STORAGE_UPDATE_FAILED","PERMISSION_UPDATE_FAILED","WORKER_UPDATE_FAILED","PRIORITY_UPDATE_FAILED"];
              return {type:"error",code:(allowed.includes(code)?code:"BASE_CREATE_FAILED") as "BASE_NOT_FOUND"|"BASE_PERMISSION_DENIED"|"BUILDING_NOT_FOUND"|"BUILDING_MAX_LEVEL"|"BUILDING_PREREQUISITE_MISSING"|"INSUFFICIENT_STORAGE"|"STORAGE_CAPACITY_EXCEEDED"|"INVALID_STORAGE_QUANTITY"|"INVALID_WORK_TASK"|"CREATURE_NOT_FOUND"|"CREATURE_NOT_TAMED"|"CREATURE_IN_PARTY"|"UPGRADE_FAILED"|"STORAGE_UPDATE_FAILED"|"PERMISSION_UPDATE_FAILED"|"WORKER_UPDATE_FAILED"|"PRIORITY_UPDATE_FAILED"|"BASE_CREATE_FAILED"};
            }
          });
          send(socket,response);
          return;
        }

        if (message.type === "gather_resource") {
          if (!userId) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
          const authenticatedUserId = userId;
          const state = players.get(authenticatedUserId);
          if (!state) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
          if (state.health <= 0) { send(socket, { type: "error", code: "PLAYER_DEAD" }); return; }
          if (playerHasStatus(authenticatedUserId, "stun")) { send(socket, { type: "error", code: "PLAYER_STUNNED" }); return; }
          const node = world.getResourceNode(message.resourceId);
          if (!node) { send(socket, { type: "error", code: "RESOURCE_NOT_FOUND" }); return; }
          const fingerprint = resourceGatherFingerprint(node.id);
          const response = await runEconomyRequest(authenticatedUserId, message.requestId, fingerprint, async () => {
            if (distance(state, node) > 2.5) return { type: "error", code: "RESOURCE_OUT_OF_RANGE" };
            try {
              const result = await gatherResource(db, authenticatedUserId, message.requestId, fingerprint, node);
              const refreshed = await players.reloadEconomy(authenticatedUserId);
              return {
                type: "resource_gathered",
                requestId: message.requestId,
                resourceId: result.nodeId,
                itemId: result.itemId,
                quantity: result.quantity,
                respawnsAt: result.respawnsAt,
                state: serializePlayerState(refreshed),
              };
            } catch (error) {
              const code = errorCode(error, "RESOURCE_GATHER_FAILED");
              const allowed = [
                "RESOURCE_NOT_FOUND",
                "RESOURCE_DEPLETED",
                "RESOURCE_REQUEST_CONFLICT",
                "RESOURCE_NODE_MISMATCH",
                "RESOURCE_NODE_UPDATE_FAILED",
                "INVENTORY_LIMIT",
                "INSUFFICIENT_INVENTORY",
                "PLAYER_NOT_FOUND",
              ];
              if (allowed.includes(code)) return { type: "error", code } as ServerMessage;
              throw error;
            }
          });
          send(socket, response);
          return;
        }

        if (message.type === "craft") {
          if (!userId) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
          const authenticatedUserId = userId;
          const response = await runEconomyRequest(authenticatedUserId, message.requestId, "craft|" + message.recipeId, async () => {
            try {
              await players.loadOrCreate(authenticatedUserId);
              const result = await craftRecipe(db, authenticatedUserId, message.recipeId);
              const state = await players.reloadEconomy(authenticatedUserId);
              return { type: "craft_result", requestId: message.requestId, recipeId: result.recipeId, state: serializePlayerState(state) };
            } catch (error) {
              const code = errorCode(error, "CRAFT_FAILED");
              if (code === "RECIPE_NOT_FOUND" || code === "INSUFFICIENT_INVENTORY" || code === "INVENTORY_LIMIT") {
                return { type: "error", code };
              }
              throw error;
            }
          });
          send(socket, response);
          return;
        }

        if (message.type === "shop_purchase") {
          if (!userId) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
          const authenticatedUserId = userId;
          const response = await runEconomyRequest(authenticatedUserId, message.requestId, "shop_purchase|" + message.itemId + "|" + message.quantity, async () => {
            try {
              await players.loadOrCreate(authenticatedUserId);
              const item = getShopItem(message.itemId);
              if (!item) return { type: "error", code: "SHOP_ITEM_NOT_FOUND" };
              const totalGold = calculatePurchase(item, message.quantity);
              if (totalGold === null) return { type: "error", code: "INVALID_PURCHASE_QUANTITY" };
              const purchase = await players.purchase(authenticatedUserId, message.requestId, item, message.quantity, totalGold);
              return {
                type: "shop_purchase_result",
                requestId: message.requestId,
                transactionId: purchase.transactionId,
                itemId: item.id,
                quantity: message.quantity,
                totalGold: totalGold.toString(),
                state: purchase.state,
              };
            } catch (error) {
              const code = errorCode(error, "PURCHASE_FAILED");
              if (code === "INSUFFICIENT_GOLD" || code === "INVENTORY_LIMIT" || code === "PLAYER_NOT_FOUND" || code === "SHOP_REQUEST_CONFLICT" || code === "INVALID_REQUEST_ID") {
                return { type: "error", code };
              }
              throw error;
            }
          });
          send(socket, response);
          return;
        }

        if (message.type === "trade") {
          if (!userId) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
          const authenticatedUserId = userId;
          const response = await runEconomyRequest(authenticatedUserId, message.requestId, "trade|" + message.toUserId + "|" + message.gold + "|" + JSON.stringify(message.items), async () => {
            try {
              await players.loadOrCreate(authenticatedUserId);
              await players.loadOrCreate(message.toUserId);
              const result = await tradePlayers(db, {
                requestId: message.requestId,
                fromUserId: authenticatedUserId,
                toUserId: message.toUserId,
                gold: message.gold,
                items: message.items,
              });
              await players.reloadEconomy(authenticatedUserId);
              if (userSockets.has(message.toUserId)) await players.reloadEconomy(message.toUserId);
              return { type: "trade_result", requestId: message.requestId, transactionId: result.transactionId, from: result.from, to: result.to };
            } catch (error) {
              const code = errorCode(error, "TRADE_FAILED");
              const allowed = ["TRADE_REQUEST_CONFLICT", "INVALID_TRADE_REQUEST", "INVALID_TRADE_PARTICIPANTS", "INVALID_TRADE_ITEMS", "INVALID_TRADE_ITEM", "INVALID_TRADE_QUANTITY", "PLAYER_NOT_FOUND", "INSUFFICIENT_INVENTORY", "INSUFFICIENT_GOLD", "INVENTORY_LIMIT"];
              if (allowed.includes(code)) return { type: "error", code } as ServerMessage;
              throw error;
            }
          });
          send(socket, response);
          if (response.type === "trade_result" && response.to !== undefined && userSockets.has(message.toUserId)) {
            for (const recipientSocket of userSockets.get(message.toUserId) ?? []) send(recipientSocket, response);
          }
          return;
        }

        if (message.type === "start_breeding") {
          if (!userId) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
          const authenticatedUserId=userId;
          const response=await runCreatureRequest(authenticatedUserId,message.requestId,"start_breeding|"+JSON.stringify(message),async()=>{
            try {
              const job=await breeding.start(authenticatedUserId,message.baseId,message.penBuildingId,message.parentAId,message.parentBId,message.durationMs);
              return {type:"breeding_started",requestId:message.requestId,job};
            } catch(error) {
              const code=errorCode(error,"BREEDING_START_FAILED");
              const allowed=["BASE_NOT_FOUND","BREEDING_PEN_NOT_FOUND","BREEDING_CAPACITY_REACHED","BREEDING_PEN_BUSY","INVALID_BREEDING_DURATION","CREATURE_NOT_FOUND","BREEDING_PARENTS_MUST_DIFFER","INCOMPATIBLE_BREEDING_PARENTS","BREEDING_GENERATION_LIMIT","POPULATION_LIMIT_REACHED","NO_BREEDING_FEED"];
              return {type:"error",code:(allowed.includes(code)?code:"INVALID_MESSAGE") as Extract<ServerMessage,{type:"error"}>["code"]};
            }
          });
          send(socket,response); return;
        }

        if (message.type === "list_breeding") {
          if (!userId) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
          const authenticatedUserId=userId;
          const response=await runCreatureRequest(authenticatedUserId,message.requestId,"list_breeding",async()=>({type:"breeding_jobs",requestId:message.requestId,jobs:await breeding.list(authenticatedUserId)}));
          send(socket,response); return;
        }

        if (message.type === "create_guild" || message.type === "get_guild" || message.type === "list_guild_invitations" || message.type === "invite_guild_member" || message.type === "accept_guild_invite" || message.type === "decline_guild_invite" || message.type === "leave_guild" || message.type === "remove_guild_member" || message.type === "set_guild_rank" || message.type === "set_guild_permission" || message.type === "guild_bank" || message.type === "guild_bank_deposit" || message.type === "guild_bank_withdraw" || message.type === "build_guild_infrastructure") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;
          await players.loadOrCreate(authenticatedUserId);
          const response=await runBaseRequest(authenticatedUserId,message.requestId,message.type+"|"+JSON.stringify(message),async()=>{
            try{
              if(message.type==="create_guild")return {type:"guild_state",requestId:message.requestId,guild:await guilds.create(authenticatedUserId,message.name,message.tag)};
              if(message.type==="get_guild")return {type:"guild_state",requestId:message.requestId,guild:await guilds.get(authenticatedUserId)};
              if(message.type==="list_guild_invitations")return {type:"guild_invitations",requestId:message.requestId,invitations:await guilds.listInvitations(authenticatedUserId)};
              if(message.type==="invite_guild_member"){await guilds.invite(authenticatedUserId,message.guildId,message.targetUserId);return {type:"guild_operation_ok",requestId:message.requestId,guildId:message.guildId};}
              if(message.type==="accept_guild_invite")return {type:"guild_state",requestId:message.requestId,guild:await guilds.acceptInvite(authenticatedUserId,message.invitationId)};
              if(message.type==="decline_guild_invite"){await guilds.declineInvite(authenticatedUserId,message.invitationId);return {type:"guild_operation_ok",requestId:message.requestId,guildId:""};}
              if(message.type==="leave_guild"){await guilds.leave(authenticatedUserId,message.guildId);return {type:"guild_operation_ok",requestId:message.requestId,guildId:message.guildId};}
              if(message.type==="remove_guild_member"){await guilds.removeMember(authenticatedUserId,message.guildId,message.targetUserId);return {type:"guild_operation_ok",requestId:message.requestId,guildId:message.guildId};}
              if(message.type==="set_guild_rank"){await guilds.setRank(authenticatedUserId,message.guildId,message.targetUserId,message.rank);return {type:"guild_operation_ok",requestId:message.requestId,guildId:message.guildId};}
              if(message.type==="set_guild_permission"){await guilds.setPermission(authenticatedUserId,message.guildId,message.rank,message.permission,message.enabled);return {type:"guild_operation_ok",requestId:message.requestId,guildId:message.guildId};}
              if(message.type==="guild_bank")return {type:"guild_bank_state",requestId:message.requestId,guildId:message.guildId,bank:await guilds.bank(authenticatedUserId,message.guildId)};
              if(message.type==="guild_bank_deposit"){const result=await guilds.bankDeposit(authenticatedUserId,message.guildId,message.itemId,message.quantity,message.gold);return {type:"guild_operation_ok",requestId:message.requestId,guildId:message.guildId,transactionId:result.transactionId};}
              if(message.type==="guild_bank_withdraw"){const result=await guilds.bankWithdraw(authenticatedUserId,message.guildId,message.itemId,message.quantity,message.gold);return {type:"guild_operation_ok",requestId:message.requestId,guildId:message.guildId,transactionId:result.transactionId};}
              if(message.type==="build_guild_infrastructure"){const result=await guilds.buildInfrastructure(authenticatedUserId,message.guildId,message.structureType);return {type:"guild_operation_ok",requestId:message.requestId,guildId:message.guildId,transactionId:result.transactionId};}
            }catch(error){
              const code=errorCode(error,"GUILD_OPERATION_FAILED");
              const allowed=["INVALID_GUILD_NAME","INVALID_GUILD_TAG","GUILD_NAME_OR_TAG_EXISTS","GUILD_HALL_REQUIRED","ALREADY_IN_GUILD","GUILD_NOT_FOUND","GUILD_MEMBERSHIP_REQUIRED","GUILD_PERMISSION_DENIED","PLAYER_NOT_FOUND","INVALID_GUILD_INVITEE","TARGET_ALREADY_IN_GUILD","GUILD_INVITATION_NOT_FOUND","GUILD_MASTER_CANNOT_LEAVE","INVALID_GUILD_MEMBER","GUILD_MEMBER_NOT_FOUND","GUILD_MASTER_PROTECTED","INVALID_GUILD_RANK","INVALID_GUILD_PERMISSION","INVALID_GUILD_INFRASTRUCTURE","INVALID_GUILD_BANK_QUANTITY","INVALID_GUILD_BANK_DEPOSIT","INVALID_GUILD_BANK_WITHDRAW","INSUFFICIENT_GUILD_BANK","GUILD_QUEST_NOT_FOUND","GUILD_INFRASTRUCTURE_MAX","INVALID_GOLD","GOLD_OVERFLOW","INSUFFICIENT_GOLD","INVALID_ITEM_ID","INVALID_ITEM_QUANTITY","INVENTORY_LIMIT","INSUFFICIENT_INVENTORY"];
              return {type:"error",code:(allowed.includes(code)?code:"INVALID_MESSAGE") as Extract<ServerMessage,{type:"error"}>["code"]};
            }
          });
          send(socket,response);return;
        }


        if (message.type === "list_friends" || message.type === "add_friend" || message.type === "remove_friend" || message.type === "block_user" || message.type === "unblock_user" || message.type === "list_blocks" || message.type === "report_user" ||
            message.type === "chat_send" || message.type === "chat_history" || message.type === "create_party" || message.type === "get_party" || message.type === "party_invitations" ||
            message.type === "party_invite" || message.type === "party_accept" || message.type === "party_leave" || message.type === "party_kick" ||
            message.type === "auction_list" || message.type === "auction_create" || message.type === "auction_bid" || message.type === "auction_buy_now" || message.type === "auction_cancel" || message.type === "auction_history") {
          if (!userId) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
          const authenticatedUserId = userId;
          await players.loadOrCreate(authenticatedUserId);
          const response = await runBaseRequest(authenticatedUserId, message.requestId, message.type + "|" + JSON.stringify(message), async () => {
            try {
              if (message.type === "list_friends") return { type: "friends_list", requestId: message.requestId, friends: await social.friends(authenticatedUserId) };
              if (message.type === "add_friend") {
                await social.addFriend(authenticatedUserId, message.targetUserId);
                const friends = await social.friends(authenticatedUserId);
                if (userSockets.has(message.targetUserId)) for (const s of userSockets.get(message.targetUserId) ?? []) send(s, { type: "friends_list", requestId: "push", friends: await social.friends(message.targetUserId) });
                return { type: "friends_list", requestId: message.requestId, friends };
              }
              if (message.type === "remove_friend") {
                await social.removeFriend(authenticatedUserId, message.targetUserId);
                return { type: "social_operation_ok", requestId: message.requestId };
              }
              if (message.type === "block_user") {
                await social.block(authenticatedUserId, message.targetUserId);
                return { type: "social_operation_ok", requestId: message.requestId };
              }
              if (message.type === "unblock_user") {
                await social.unblock(authenticatedUserId, message.targetUserId);
                return { type: "social_operation_ok", requestId: message.requestId };
              }
              if (message.type === "list_blocks") return { type: "blocks_list", requestId: message.requestId, blockedUserIds: await social.blocked(authenticatedUserId) };
              if (message.type === "report_user") return { type: "social_reported", requestId: message.requestId, reportId: await social.report(authenticatedUserId, message.targetUserId, message.reason, message.details) };

              if (message.type === "chat_send") {
                if (message.channel === "system") throw new Error("INVALID_CHAT_CHANNEL");
                const sender = players.get(authenticatedUserId);
                if (!sender) throw new Error("PLAYER_NOT_FOUND");
                const regionId = Math.floor(sender.x / 1000) * 100000 + Math.floor(sender.y / 1000);
                let partyId: string | null = message.partyId;
                let guildId: string | null = message.guildId;
                if (message.channel === "party") {
                  const party = await social.partyForUser(authenticatedUserId);
                  if (!party || (message.partyId && party.id !== message.partyId)) throw new Error("PARTY_MEMBERSHIP_REQUIRED");
                  partyId = party.id;
                }
                if (message.channel === "guild") {
                  const guild = await db.query<{ guild_id: string }>("SELECT guild_id FROM guild_members WHERE user_id=$1", [authenticatedUserId]);
                  if (!guild.rows[0] || (message.guildId && guild.rows[0].guild_id !== message.guildId)) throw new Error("GUILD_MEMBERSHIP_REQUIRED");
                  guildId = guild.rows[0].guild_id;
                }
                const chat = await social.sendChat(authenticatedUserId, { channel: message.channel, body: message.body, recipientUserId: message.recipientUserId, guildId, partyId, regionId });
                const recipients = new Set<string>();
                if (message.channel === "whisper") recipients.add(message.recipientUserId ?? "");
                else if (message.channel === "party" && partyId) {
                  const rows = await db.query<{ user_id: string }>("SELECT user_id FROM party_members WHERE party_id=$1", [partyId]);
                  for (const row of rows.rows) recipients.add(row.user_id);
                } else if (message.channel === "guild" && guildId) {
                  const rows = await db.query<{ user_id: string }>("SELECT user_id FROM guild_members WHERE guild_id=$1", [guildId]);
                  for (const row of rows.rows) recipients.add(row.user_id);
                } else if (message.channel === "local") {
                  for (const id of userSockets.keys()) {
                    const other=players.get(id); if (other && Math.hypot(other.x-sender.x,other.y-sender.y)<=32) recipients.add(id);
                  }
                } else if (message.channel === "region") {
                  for (const id of userSockets.keys()) {
                    const other=players.get(id);
                    if (other && Math.floor(other.x/1000)*100000+Math.floor(other.y/1000)===regionId) recipients.add(id);
                  }
                } else {
                  for (const id of userSockets.keys()) recipients.add(id);
                }
                const recipientIds=[...recipients].filter(Boolean);
                if (recipientIds.length) {
                  const blocked = await db.query<{ blocker_user_id: string }>(
                    "SELECT blocker_user_id FROM social_blocks WHERE blocker_user_id=ANY($1::uuid[]) AND blocked_user_id=$2",
                    [recipientIds, authenticatedUserId],
                  );
                  const blockedSet=new Set(blocked.rows.map(x=>x.blocker_user_id));
                  for (const recipientId of recipientIds) if (!blockedSet.has(recipientId)) for (const s of userSockets.get(recipientId) ?? []) send(s,{type:"chat_message",requestId:message.requestId,message:chat});
                }
                return { type: "chat_message", requestId: message.requestId, message: chat };
              }
              if (message.type === "chat_history") {
                const sender=players.get(authenticatedUserId);const regionId=sender?Math.floor(sender.x/1000)*100000+Math.floor(sender.y/1000):null;
                const history=await social.chatHistory(authenticatedUserId,{channel:message.channel,recipientUserId:message.recipientUserId,guildId:message.guildId,partyId:message.partyId,regionId});
                return { type:"chat_history",requestId:message.requestId,messages:history };
              }

              if (message.type === "create_party") return { type:"party_state",requestId:message.requestId,party:await social.createParty(authenticatedUserId) };
              if (message.type === "get_party") return { type:"party_state",requestId:message.requestId,party:await social.partyForUser(authenticatedUserId) };
              if (message.type === "party_invitations") return { type:"party_invitations",requestId:message.requestId,invitations:await social.partyInvitations(authenticatedUserId) };
              if (message.type === "party_invite") {
                await social.inviteToParty(authenticatedUserId,message.targetUserId);
                if(userSockets.has(message.targetUserId)) for(const s of userSockets.get(message.targetUserId)??[]) send(s,{type:"party_invitations",requestId:"push",invitations:await social.partyInvitations(message.targetUserId)});
                return {type:"party_operation_ok",requestId:message.requestId};
              }
              if (message.type === "party_accept") {
                const party=await social.acceptPartyInvite(authenticatedUserId,message.invitationId);
                for(const member of party.members) for(const s of userSockets.get(member.userId)??[]) send(s,{type:"party_state",requestId:"push",party});
                return {type:"party_state",requestId:message.requestId,party};
              }
              if (message.type === "party_leave") { await social.leaveParty(authenticatedUserId); return {type:"party_operation_ok",requestId:message.requestId}; }
              if (message.type === "party_kick") { await social.kickFromParty(authenticatedUserId,message.targetUserId); return {type:"party_operation_ok",requestId:message.requestId}; }

              if (message.type === "auction_list") return {type:"auction_list",requestId:message.requestId,listings:await auctions.list({itemId:message.itemId,rarity:message.rarity,category:message.category,minLevel:message.minLevel,maxLevel:message.maxLevel,minPrice:message.minPrice,maxPrice:message.maxPrice})};
              if (message.type === "auction_create") return {type:"auction_state",requestId:message.requestId,listing:await auctions.create(authenticatedUserId,message)};
              if (message.type === "auction_bid") return {type:"auction_state",requestId:message.requestId,listing:await auctions.bid(authenticatedUserId,message.listingId,message.amount)};
              if (message.type === "auction_buy_now") return {type:"auction_state",requestId:message.requestId,listing:await auctions.buyNow(authenticatedUserId,message.listingId)};
              if (message.type === "auction_cancel") { await auctions.cancel(authenticatedUserId,message.listingId); return {type:"auction_operation_ok",requestId:message.requestId}; }
              return {type:"auction_history",requestId:message.requestId,transactions:await auctions.history(authenticatedUserId)};
            } catch (error) {
              const code=errorCode(error,"SOCIAL_OPERATION_FAILED");
              const allowed=[
                "INVALID_SOCIAL_TARGET","SOCIAL_BLOCKED","ALREADY_FRIENDS","FRIEND_REQUEST_EXISTS","PLAYER_NOT_FOUND","CHAT_RATE_LIMITED","INVALID_CHAT_CHANNEL","INVALID_CHAT_TARGET","INVALID_CHAT_CONTEXT","PARTY_MEMBERSHIP_REQUIRED","GUILD_MEMBERSHIP_REQUIRED",
                "ALREADY_IN_PARTY","PARTY_NOT_FOUND","PARTY_FULL","PARTY_INVITATION_EXISTS","TARGET_IN_PARTY","PARTY_INVITATION_NOT_FOUND","PARTY_LEADER_REQUIRED","INVALID_PARTY_TARGET","PARTY_MEMBER_NOT_FOUND",
                "INVALID_AUCTION_ITEM","INVALID_AUCTION_QUANTITY","INVALID_AUCTION_PRICE","INVALID_AUCTION_DURATION","INVALID_AUCTION_FILTER","INVALID_AUCTION_BID","AUCTION_NOT_FOUND","AUCTION_NOT_ACTIVE","AUCTION_SELF_BID","AUCTION_BID_TOO_LOW","AUCTION_NO_BUY_NOW","AUCTION_SELF_BUY","AUCTION_OWNER_REQUIRED","AUCTION_HAS_BID",
                "INVALID_GOLD","GOLD_OVERFLOW","INSUFFICIENT_GOLD","INVALID_ITEM_ID","INVALID_ITEM_QUANTITY","INSUFFICIENT_INVENTORY","INVENTORY_LIMIT"
              ];
              return {type:"error",code:(allowed.includes(code)?code:"INVALID_MESSAGE") as Extract<ServerMessage,{type:"error"}>["code"]};
            }
          });
          send(socket,response);
          return;
        }

        if (message.type === "create_army" || message.type === "list_armies" || message.type === "train_army" || message.type === "garrison_army" || message.type === "add_army_creature" || message.type === "set_army_assignment" || message.type === "set_army_formation" || message.type === "nominate_commander" || message.type === "assign_army_commander" || message.type === "issue_army_order" || message.type === "create_army_battle" || message.type === "deploy_battle_unit" || message.type === "execute_battle_turn" || message.type === "get_army_battle" || message.type === "army_tactical_action" || message.type === "build_defense" || message.type === "list_defenses") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;
          await players.loadOrCreate(authenticatedUserId);
          const response=await runBaseRequest(authenticatedUserId,message.requestId,message.type+"|"+JSON.stringify(message),async()=>{
            try{
              if(message.type==="create_army")return {type:"army_state",requestId:message.requestId,army:await armies.create(authenticatedUserId,message.name)};
              if(message.type==="list_armies")return {type:"army_list",requestId:message.requestId,armies:await armies.list(authenticatedUserId)};
              if(message.type==="train_army"){const q=await armies.train(authenticatedUserId,message.armyId,message.unitType,message.quantity);return {type:"army_training",requestId:message.requestId,queueId:q.queueId,completesAt:q.completesAt};}
              if(message.type==="garrison_army"){await armies.garrison(authenticatedUserId,message.armyId,message.baseId);return {type:"army_operation_ok",requestId:message.requestId};}
              if(message.type==="add_army_creature"){await armies.addCreature(authenticatedUserId,message.armyId,message.creatureId);return {type:"army_operation_ok",requestId:message.requestId};}
              if(message.type==="set_army_assignment")return {type:"army_state",requestId:message.requestId,army:await armies.assignment(authenticatedUserId,message.armyId,message.assignment)};
              if(message.type==="set_army_formation")return {type:"army_state",requestId:message.requestId,army:await armies.formation(authenticatedUserId,message.armyId,message.name,message.formationType,message.layout)};
              if(message.type==="nominate_commander"){await armies.nominateCommander(authenticatedUserId,message.guildId,message.targetUserId);return {type:"army_operation_ok",requestId:message.requestId};}
              if(message.type==="assign_army_commander")return {type:"army_state",requestId:message.requestId,army:await armies.commander(authenticatedUserId,message.armyId,message.commanderUserId)};
              if(message.type==="issue_army_order"){await armies.order(authenticatedUserId,message.armyId,message.battleId,message.orderType,message.targetUnitId,message.targetX,message.targetY,message.payload);return {type:"army_operation_ok",requestId:message.requestId};}
              if(message.type==="create_army_battle")return {type:"battle_state",requestId:message.requestId,battle:await armies.battleCreate(authenticatedUserId,message.attackerArmyId,message.defenderArmyId,message.targetX,message.targetY)};
              if(message.type==="deploy_battle_unit"){await armies.deploy(authenticatedUserId,message.battleId,message.unitId,message.formationSlot);return {type:"army_operation_ok",requestId:message.requestId};}
              if(message.type==="execute_battle_turn")return {type:"battle_state",requestId:message.requestId,battle:await armies.turn(authenticatedUserId,message.battleId)};
              if(message.type==="army_tactical_action")return {type:"battle_state",requestId:message.requestId,battle:await armies.action(authenticatedUserId,message.battleId,message.unitId,message.actionType,message.targetUnitId)};
              if(message.type==="get_army_battle")return {type:"battle_state",requestId:message.requestId,battle:await armies.battle(message.battleId,authenticatedUserId)};
              if(message.type==="build_defense")return {type:"defense_state",requestId:message.requestId,defense:await armies.defense(authenticatedUserId,message.baseId,message.structureType,message.gridX,message.gridY)};
              return {type:"defense_list",requestId:message.requestId,defenses:await armies.defenses(authenticatedUserId,message.baseId)};
            }catch(error){
              const code=errorCode(error,"ARMY_OPERATION_FAILED");
              const allowed=["BASE_NOT_FOUND","BARRACKS_REQUIRED","INVALID_ARMY_UNIT_TYPE","INVALID_TRAINING_QUANTITY","INSUFFICIENT_BASE_RESOURCES","ARMY_NOT_FOUND","CREATURE_NOT_FOUND","CREATURE_NOT_TAMED","CREATURE_IN_PARTY","CREATURE_ALREADY_GARRISONED","INVALID_ARMY_ASSIGNMENT","INVALID_ARMY_FORMATION","GUILD_PERMISSION_DENIED","GUILD_MEMBER_NOT_FOUND","COMMANDER_NOT_NOMINATED","COMMANDER_PERMISSION_DENIED","INVALID_COMMANDER_ORDER","ARMY_UNIT_NOT_FOUND","INVALID_COMMAND_TARGET","DEFENDER_ARMY_NOT_FOUND","INVALID_BATTLE_ARMIES","BATTLE_NOT_FOUND","BATTLE_NOT_ACTIVE","BATTLE_UNIT_NOT_FOUND","INVALID_FORMATION_SLOT","INVALID_DEFENSIVE_STRUCTURE","INVALID_DEFENSE_POSITION","DEFENSE_POSITION_OCCUPIED","BATTLE_UNIT_NOT_DEPLOYED","ARMY_UNIT_TARGET_REQUIRED","INVALID_BATTLE_TARGET","DEFENDER_GARRISON_NOT_FOUND","NO_AVAILABLE_TRAP","CANNON_UNIT_REQUIRED","DEFENSE_STRUCTURE_REQUIRED","DEFENSE_STRUCTURE_NOT_FOUND","PLAYER_NOT_FOUND","INSUFFICIENT_STORAGE"];
              return {type:"error",code:(allowed.includes(code)?code:"INVALID_MESSAGE") as Extract<ServerMessage,{type:"error"}>["code"]};
            }
          });
          send(socket,response);return;
        }

        if (message.type === "list_territory_season") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const response=await runBaseRequest(userId,message.requestId,message.type,async()=>({type:"territory_season_state",requestId:message.requestId,season:await territorySeasons.active(),standings:await territorySeasons.standings()}));
          send(socket,response);return;
        }

        if (message.type === "list_realm_wars" || message.type === "create_realm_war" || message.type === "join_realm_war" || message.type === "realm_war_action" || message.type === "list_guild_battles" || message.type === "create_guild_battle" || message.type === "join_guild_battle" || message.type === "guild_battle_action" || message.type === "list_endgame_creatures" || message.type === "engage_endgame_creature" || message.type === "list_mythic_content") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;await players.loadOrCreate(authenticatedUserId);
          const response=await runBaseRequest(authenticatedUserId,message.requestId,message.type+"|"+JSON.stringify(message),async()=>{
            try{
              if(message.type==="list_realm_wars")return {type:"realm_war_list",requestId:message.requestId,wars:await endgame.realmWars()};
              if(message.type==="create_realm_war")return {type:"realm_war_state",requestId:message.requestId,war:await endgame.createRealmWar(authenticatedUserId,message.attackerRealmId,message.defenderRealmId,message.targetTerritoryId)};
              if(message.type==="join_realm_war"){await endgame.joinRealmWar(authenticatedUserId,message.warId,message.guildId,message.realmId);return {type:"realm_war_state",requestId:message.requestId,war:(await endgame.realmWars()).find(w=>w.id===message.warId)!};}
              if(message.type==="realm_war_action")return {type:"realm_war_state",requestId:message.requestId,war:await endgame.realmWarAction(authenticatedUserId,message.warId,message.guildId,message.armyId)};
              if(message.type==="list_guild_battles")return {type:"guild_battle_list",requestId:message.requestId,battles:await endgame.guildBattles()};
              if(message.type==="create_guild_battle")return {type:"guild_battle_state",requestId:message.requestId,battle:await endgame.createGuildBattle(authenticatedUserId,message.attackerGuildId,message.defenderGuildId,message.targetTerritoryId)};
              if(message.type==="join_guild_battle"){await endgame.joinGuildBattle(authenticatedUserId,message.battleId,message.armyId);return {type:"guild_battle_state",requestId:message.requestId,battle:(await endgame.guildBattles()).find(b=>b.id===message.battleId)!};}
              if(message.type==="guild_battle_action")return {type:"guild_battle_state",requestId:message.requestId,battle:await endgame.guildBattleAction(authenticatedUserId,message.battleId,message.armyId)};
              if(message.type==="list_endgame_creatures")return {type:"endgame_creature_list",requestId:message.requestId,creatures:await endgame.creatures()};
              if(message.type==="engage_endgame_creature"){
                const player=players.get(authenticatedUserId);if(!player)throw new Error("PLAYER_NOT_FOUND");
                const creature=await endgame.engageCreature(authenticatedUserId,message.creatureId,player.level);
                await players.reloadEconomy(authenticatedUserId);
                const state=players.get(authenticatedUserId);if(state)for(const playerSocket of userSockets.get(authenticatedUserId)??[])send(playerSocket,{type:"player_state",state:serializePlayerState(state)});
                return {type:"endgame_creature_state",requestId:message.requestId,creature};
              }
              return {type:"mythic_content_list",requestId:message.requestId,content:await endgame.mythic()};
            }catch(error){
              const code=errorCode(error,"ENDGAME_OPERATION_FAILED");
              const allowed=["ENDGAME_LEVEL_REQUIRED","ENDGAME_INVALID_SCORE","ENDGAME_INVALID_CREATURE","ENDGAME_INVALID_REALM_SIDES","ENDGAME_INVALID_GUILD_SIDES","ENDGAME_TARGET_NOT_DEFENDER_TERRITORY","ENDGAME_WAR_ALREADY_ACTIVE","ENDGAME_WAR_NOT_FOUND","ENDGAME_WAR_NOT_ACTIVE","ENDGAME_ALREADY_PARTICIPATING","ENDGAME_INVALID_REALM_SIDE","ENDGAME_NO_ARMY_POWER","ENDGAME_GUILD_NOT_PARTICIPANT","ENDGAME_GUILD_BATTLE_ALREADY_ACTIVE","ENDGAME_GUILD_BATTLE_NOT_FOUND","ENDGAME_GUILD_BATTLE_NOT_ACTIVE","ENDGAME_ARMY_NOT_DEPLOYED","ENDGAME_CREATURE_NOT_FOUND","ENDGAME_CREATURE_DEFEATED","GUILD_PERMISSION_DENIED","GUILD_MEMBERSHIP_REQUIRED","ARMY_NOT_FOUND","ARMY_NOT_OWNED","PLAYER_NOT_FOUND","TERRITORY_NOT_FOUND"];
              return {type:"error",code:(allowed.includes(code)?code:"INVALID_MESSAGE") as Extract<ServerMessage,{type:"error"}>["code"]};
            }
          });
          send(socket,response);return;
        }

        if (message.type === "list_realms" || message.type === "list_territories" || message.type === "list_realm_fortresses" || message.type === "territory_at" || message.type === "claim_guild_territory" || message.type === "change_realm_reputation" || message.type === "my_realm_reputation" || message.type === "create_trade_route" || message.type === "list_trade_routes" || message.type === "tick_realm_ai") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;await players.loadOrCreate(authenticatedUserId);
          const response=await runBaseRequest(authenticatedUserId,message.requestId,message.type+"|"+JSON.stringify(message),async()=>{
            try{
              if(message.type==="list_realms")return {type:"realm_list",requestId:message.requestId,realms:await realms.list()};
              if(message.type==="list_territories")return {type:"territory_list",requestId:message.requestId,territories:await realms.territories()};
              if(message.type==="list_realm_fortresses")return {type:"fortress_list",requestId:message.requestId,fortresses:await realms.fortresses()};
              if(message.type==="territory_at")return {type:"territory_state",requestId:message.requestId,territory:await realms.territoryAt(message.x,message.y)};
              if(message.type==="claim_guild_territory"){await realms.claimGuildTerritory(authenticatedUserId,message.territoryId,message.guildId);return {type:"realm_operation_ok",requestId:message.requestId};}
              if(message.type==="change_realm_reputation")return {type:"realm_reputation",requestId:message.requestId,reputation:await realms.reputation(authenticatedUserId,message.realm,message.delta)};
              if(message.type==="my_realm_reputation")return {type:"realm_reputation",requestId:message.requestId,reputation:await realms.myReputation(authenticatedUserId)};
              if(message.type==="create_trade_route"){const route=await realms.createTradeRoute(authenticatedUserId,message.sourceTerritoryId,message.destinationTerritoryId,message.resourceKey,message.quantity,message.travelSeconds,message.guildId,message.realmId);return {type:"trade_route_state",requestId:message.requestId,route};}
              if(message.type==="list_trade_routes")return {type:"trade_route_list",requestId:message.requestId,routes:await realms.routes()};
              await realms.tickAI();return {type:"realm_operation_ok",requestId:message.requestId};
            }catch(error){const code=errorCode(error,"REALM_OPERATION_FAILED");const allowed=["INVALID_TERRITORY_COORDINATES","TERRITORY_NOT_FOUND","INSUFFICIENT_TERRITORY_INFLUENCE","INVALID_REPUTATION_DELTA","REALM_NOT_FOUND","INVALID_TRADE_ROUTE","INVALID_TRADE_ROUTE_ENDPOINTS","GUILD_PERMISSION_DENIED","GUILD_MEMBERSHIP_REQUIRED","PLAYER_NOT_FOUND"];return {type:"error",code:(allowed.includes(code)?code:"INVALID_MESSAGE") as Extract<ServerMessage,{type:"error"}>["code"]};}
          });send(socket,response);return;
        }

        if (message.type === "list_world_events" || message.type === "world_event_contribute" || message.type === "world_event_reward") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;
          await players.loadOrCreate(authenticatedUserId);
          const response=await runBaseRequest(authenticatedUserId,message.requestId,message.type+"|"+JSON.stringify(message),async()=>{
            try{
              if(message.type==="list_world_events") return {type:"world_event_list",requestId:message.requestId,events:await worldEvents.listActive()};
              if(message.type==="world_event_contribute"){
                const event=await worldEvents.contribute(authenticatedUserId,message.eventId);
                return {type:"world_event_state",requestId:message.requestId,event};
              }
              const reward=await worldEvents.claimReward(authenticatedUserId,message.eventId);
              await players.reloadEconomy(authenticatedUserId);
              const state=players.get(authenticatedUserId);
              if(state) for(const playerSocket of userSockets.get(authenticatedUserId)??[]) send(playerSocket,{type:"player_state",state:serializePlayerState(state)});
              return {type:"world_event_reward",requestId:message.requestId,eventId:message.eventId,gold:reward.gold,items:reward.items};
            }catch(error){return {type:"error",code:errorCode(error,"WORLD_EVENT_OPERATION_FAILED")} as ServerMessage}
          });
          send(socket,response);
          return;
        }

        if (message.type === "list_invasions" || message.type === "get_invasion_waves" || message.type === "join_invasion" || message.type === "invasion_action") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;await players.loadOrCreate(authenticatedUserId);
          const response=await runBaseRequest(authenticatedUserId,message.requestId,message.type+"|"+JSON.stringify(message),async()=>{
            try{
              if(message.type==="list_invasions")return {type:"invasion_list",requestId:message.requestId,invasions:await invasions.list(message.territoryId)};
              if(message.type==="get_invasion_waves")return {type:"invasion_waves",requestId:message.requestId,invasionId:message.invasionId,waves:await invasions.waves(message.invasionId)};
              if(message.type==="join_invasion"){await invasions.join(authenticatedUserId,message.invasionId,message.armyId,message.role);return {type:"invasion_operation_ok",requestId:message.requestId,invasionId:message.invasionId};}
              const invasion=await invasions.act(authenticatedUserId,message.invasionId,message.action,message.waveId);
              return {type:"invasion_state",requestId:message.requestId,invasion};
            }catch(error){
              const code=errorCode(error,"INVASION_OPERATION_FAILED");
              const allowed=["INVALID_INVASION_ROLE","INVASION_ALREADY_PARTICIPATING","INVALID_INVASION_THREAT","INVALID_INVASION_SOURCE","INVASION_ALREADY_ACTIVE","INVASION_NOT_FOUND","INVASION_NOT_JOINABLE","ARMY_NOT_FOUND","ARMY_NOT_OWNED","ARMY_ALREADY_IN_INVASION","INVASION_NOT_IN_BATTLE","INVASION_NOT_PARTICIPANT","INVASION_WAVE_REQUIRED","INVASION_WAVE_NOT_FOUND","INVASION_WAVE_NOT_ACTIVE","PLAYER_NOT_FOUND"];
              return {type:"error",code:(allowed.includes(code)?code:"INVALID_MESSAGE") as Extract<ServerMessage,{type:"error"}>["code"]};
            }
          });
          send(socket,response);return;
        }

        if (message.type === "create_ship" || message.type === "list_ships" || message.type === "ship_inventory" || message.type === "ship_cargo" || message.type === "create_fleet" || message.type === "list_fleets" || message.type === "add_fleet_ship" || message.type === "remove_fleet_ship" || message.type === "sail" || message.type === "assign_ship_crew" || message.type === "assign_ship_npc_crew" || message.type === "fire_cannon" || message.type === "board_ship" || message.type === "repair_ship" || message.type === "retreat_ship" || message.type === "fight_ship_fire") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          const authenticatedUserId=userId;
          const response=await runBaseRequest(authenticatedUserId,message.requestId,message.type+"|"+JSON.stringify(message),async()=>{
            try{
              if(message.type==="create_ship"){
                if(!Object.hasOwn(SHIP_CLASSES,message.shipClass))throw new Error("INVALID_SHIP_CLASS");
                const ship=await ships.create(authenticatedUserId,message.name,message.shipClass as ShipClass);
                return {type:"ship_state",requestId:message.requestId,ship};
              }
              if(message.type==="list_ships")return {type:"ship_list",requestId:message.requestId,ships:await ships.list(authenticatedUserId)};
              if(message.type==="ship_inventory")return {type:"ship_inventory",requestId:message.requestId,shipId:message.shipId,items:await ships.inventory(authenticatedUserId,message.shipId)};
              if(message.type==="ship_cargo")return {type:"ship_inventory",requestId:message.requestId,shipId:message.shipId,items:await shipInventory.mutate(authenticatedUserId,message.shipId,message.itemId,message.quantity)};
              if(message.type==="create_fleet")return {type:"fleet_state",requestId:message.requestId,fleet:await fleets.create(authenticatedUserId,message.name,message.shipId)};
              if(message.type==="list_fleets")return {type:"fleet_list",requestId:message.requestId,fleets:await fleets.list(authenticatedUserId)};
              if(message.type==="add_fleet_ship")return {type:"fleet_state",requestId:message.requestId,fleet:await fleets.addShip(authenticatedUserId,message.fleetId,message.shipId)};
              if(message.type==="remove_fleet_ship")return {type:"fleet_state",requestId:message.requestId,fleet:await fleets.removeShip(authenticatedUserId,message.fleetId,message.shipId)};
              if(message.type==="sail")return {type:"ship_state",requestId:message.requestId,ship:await ships.sail(authenticatedUserId,message.shipId,message.dx,message.dy,message.dt)};
              if(message.type==="assign_ship_crew"){
                if(!CREW_ROLES.includes(message.role as CrewRole))throw new Error("INVALID_CREW_ASSIGNMENT");
                return {type:"ship_crew",requestId:message.requestId,crew:await ships.assignCrew(authenticatedUserId,message.shipId,message.creatureId,message.role as CrewRole,message.skill,message.morale)};
              }
              if(message.type==="assign_ship_npc_crew")return {type:"ship_crew",requestId:message.requestId,crew:await naval.assignNpcCrew(authenticatedUserId,message.shipId,message.npcType,message.role as CrewRole,message.skill,message.morale)};
              if(message.type==="board_ship")return {type:"naval_combat_result",requestId:message.requestId,...await naval.boardShip(authenticatedUserId,message.shipId,message.targetShipId)};
              if(message.type==="repair_ship")return {type:"ship_state",requestId:message.requestId,ship:await naval.repairShip(authenticatedUserId,message.shipId)};
              if(message.type==="retreat_ship")return {type:"ship_state",requestId:message.requestId,ship:await naval.retreatShip(authenticatedUserId,message.shipId)};
              if(message.type==="fight_ship_fire")return {type:"ship_state",requestId:message.requestId,ship:await naval.fightFire(authenticatedUserId,message.shipId)};
              const result=await naval.fireCannon(authenticatedUserId,message.shipId,message.targetShipId);
              return {type:"naval_combat_result",requestId:message.requestId,...result};
            }catch(error){
              const code=errorCode(error,"SHIP_OPERATION_FAILED");
              const allowed=["BASE_NOT_FOUND","INVALID_SHIP_CLASS","SHIPYARD_REQUIRED","INSUFFICIENT_SHIPYARD_RESOURCES","INVALID_SAIL_INPUT","SHIP_NOT_FOUND","SHIP_NOT_ACTIVE","INSUFFICIENT_SHIP_FUEL","INVALID_SHIP_CARGO","INSUFFICIENT_SHIP_CARGO","SHIP_CARGO_CAPACITY_EXCEEDED","FLEET_NOT_FOUND","SHIP_ALREADY_IN_FLEET","SHIP_NOT_IN_FLEET","FLEET_COMMANDER_REQUIRED","INVALID_CREW_ASSIGNMENT","SHIP_CREW_CAPACITY_REACHED","CREW_CREATURE_NOT_FOUND","CREW_CREATURE_NOT_TAMED","CREW_CREATURE_IN_PARTY","CREW_ALREADY_ASSIGNED","INVALID_NAVAL_TARGET","TARGET_SHIP_NOT_ACTIVE","NAVAL_TARGET_OUT_OF_RANGE","CANNON_COOLDOWN","NO_CANNON_AMMO","CANNON_OUTSIDE_ARC","SHIP_RETREATING","TARGET_SHIP_RETREATING","BOARDING_OUT_OF_RANGE","SHIP_FULL_HEALTH","NO_REPAIR_LUMBER","SHIP_NOT_ON_FIRE","INVALID_WIND"];
              return {type:"error",code:(allowed.includes(code)?code:"INVALID_MESSAGE") as Extract<ServerMessage,{type:"error"}>["code"]};
            }
          });
          send(socket,response);return;
        }

        if (message.type === "subscribe_chunks") {
          if (!userId) {
            send(socket, { type: "error", code: "AUTH_REQUIRED" });
            return;
          }

          for (const coordinate of message.chunks) {
            send(socket, {
              type: "world_chunk",
              requestId: message.requestId,
              chunk: await visibleClientWorldChunk(coordinate.x, coordinate.y),
            });
          }
        }
      }).catch((error) => {
        log("websocket_message_failed", {
          message: error instanceof Error ? error.message : String(error),
        });
        send(socket, { type: "error", code: "INTERNAL_SERVER_ERROR" });
      });
    });

    socket.on("close", () => {
      if (authDeadline) {
        clearTimeout(authDeadline);
        authDeadline = null;
      }
      sockets.delete(socket);
      setWebSocketConnections(sockets.size);
      if (userId !== null) {
        authenticatedSocketCount = Math.max(0, authenticatedSocketCount - 1);
        setWebSocketAuthenticated(authenticatedSocketCount);
      }
      if (shuttingDown || !userId) return;
      const disconnectedUserId=userId;
      const connections = (playerConnections.get(disconnectedUserId) ?? 1) - 1;
      const socketsForUser = userSockets.get(disconnectedUserId);
      socketsForUser?.delete(socket);
      if (socketsForUser && socketsForUser.size === 0) userSockets.delete(disconnectedUserId);
      setActivePlayers(userSockets.size);
      if (connections <= 0) {
        playerConnections.delete(disconnectedUserId);
        attackCooldowns.delete(disconnectedUserId);
        dodgeCooldowns.delete(disconnectedUserId);
        blocking.delete(disconnectedUserId);
        invulnerableUntil.delete(disconnectedUserId);
        playerStatuses.delete(disconnectedUserId);
        combatActivationNextAt.delete(disconnectedUserId);
        for (const [key] of pendingCombatRequests) if (key.startsWith(disconnectedUserId + ":")) pendingCombatRequests.delete(key);
        const pendingMessageWork = messageQueue.catch(() => undefined);
        const pendingCreatureWork = pendingCreatureOperations.get(disconnectedUserId) ?? Promise.resolve();
        const pendingBaseWork = bases.persistAndUnload(disconnectedUserId).catch((error) => { log("base_disconnect_persistence_failed",{message:error instanceof Error?error.message:String(error)}); return null; });
        const unloadPromise = pendingMessageWork.then(() => pendingCreatureWork).then(() => pendingBaseWork).then(
          () => creatures.unload(disconnectedUserId),
          () => creatures.unload(disconnectedUserId),
        ).then(
          () => players.unload(disconnectedUserId),
          (error) => {
            log("creature_disconnect_persistence_failed",{message:error instanceof Error?error.message:String(error)});
            return players.unload(disconnectedUserId);
          },
        ).catch((error) => {
          log("player_disconnect_persistence_failed", {
            message: error instanceof Error ? error.message : String(error),
          });
        });
        pendingPlayerUnloads.set(disconnectedUserId, unloadPromise);
        void unloadPromise.finally(() => {
          if (pendingPlayerUnloads.get(disconnectedUserId) === unloadPromise) pendingPlayerUnloads.delete(disconnectedUserId);
        });
      } else {
        playerConnections.set(disconnectedUserId, connections);
      }
    });
    socket.on("error", (error) => {
      log("websocket_error", { message: error.message });
      sockets.delete(socket);
    });
  });

  registerFrontendRoutes(app, clientDistDir);

  return app;
}
