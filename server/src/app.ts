import Fastify, { type FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import rateLimit from "@fastify/rate-limit";
import swagger from "@fastify/swagger";
import swaggerUi from "@fastify/swagger-ui";
import websocket from "@fastify/websocket";
import type { WebSocket } from "ws";
import type { Pool } from "pg";
import { config } from "./config.js";
import { createDbPool } from "./db.js";
import { registerAuthRoutes } from "./auth.js";
import { log } from "./logger.js";
import { parseClientMessage, type ServerMessage } from "./protocol.js";
import { PlayerStore, applyPlayerInput } from "./player.js";
import { WorldChunkCache } from "./world.js";
import { SHOP_ITEMS, calculatePurchase, getShopItem } from "./shop.js";
import { addThreat, applyDamage, createCombatTarget, creatureAbilityDamage, createProjectile, advanceProjectile, isMeleeHit, distance, mitigateDamage, tickCreatureAi, tickStatusEffects, tickStatuses, weaponFor, type CombatProjectile, type CombatTarget, type StatusEffect } from "./combat.js";
import { CombatReplayCache } from "./combat-replay.js";
import { CAPTURE_HEALTH_RATIO, CreatureStore } from "./creature.js";\nimport { BaseStore, BUILDING_TYPES, type BuildingType } from "./base.js";

function errorCode(error: unknown, fallback: string): string {
  return error instanceof Error ? error.message : fallback;
}

function send(socket: WebSocket, message: ServerMessage): void {
  if (socket.readyState === socket.OPEN) socket.send(JSON.stringify(message));
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
}

export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const db = options.db ?? createDbPool();
  const ownsDb = options.db === undefined;
  const world = new WorldChunkCache(256);
  const players = new PlayerStore(db);
  const creatures = new CreatureStore(db);\n  const bases = new BaseStore(db);
  const sockets = new Set<WebSocket>();
  const playerConnections = new Map<string, number>();
  const userSockets = new Map<string, Set<WebSocket>>();
  const combatTargets = new Map<string, CombatTarget>();
  const defeatedCreatures = new Set<string>();
  const capturedWorldCreatures = new Set<string>();
  const capturedRows = await db.query<{ wild_source_id: string }>("SELECT wild_source_id FROM player_creatures");
  for (const row of capturedRows.rows) capturedWorldCreatures.add(row.wild_source_id);
  const visibleWorldChunk = (x: number, y: number) => {
    const chunk = world.get(x, y);
    if (capturedWorldCreatures.size === 0) return chunk;
    const creatures = chunk.creatures.filter((spawn) => !capturedWorldCreatures.has(spawn.id));
    return creatures.length === chunk.creatures.length ? chunk : { ...chunk, creatures };
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
  const pendingCreatureRequests = new Map<string, Promise<ServerMessage>>();
  const pendingCreatureOperations = new Map<string, Promise<void>>();
  const pendingPlayerUnloads = new Map<string, Promise<void>>();
  let shuttingDown = false;
  const app = Fastify({ logger: false });

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
        for (const socket of userSockets.get(userId) ?? []) send(socket, { type: "player_state", state: player });
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

  const heartbeat = setInterval(() => {
    for (const socket of sockets) {
      if (socket.readyState === socket.OPEN) socket.ping();
    }
  }, 30_000);
  heartbeat.unref();

  const survivalTick = setInterval(() => players.tick(1), 1_000);
  survivalTick.unref();

  const combatTick = setInterval(() => {
    const now = Date.now();
    tickPlayerStatuses(250);

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
          for (const socket of userSockets.get(userId) ?? []) send(socket, { type: "player_state", state: targetPlayer });
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
          for (const socket of userSockets.get(userId) ?? []) send(socket, { type: "player_state", state: targetPlayer });
        }
      }
    }
    for (const [key, expiresAt] of pendingCombatRequests) if (expiresAt <= now) pendingCombatRequests.delete(key);
    for (const [userId, until] of invulnerableUntil) if (until <= now) invulnerableUntil.delete(userId);
  }, 250);
  combatTick.unref();

  const persistenceTick = setInterval(() => {
    void Promise.all([players.persistDirty(), creatures.persistDirty()]).catch((error) => {
      log("player_persistence_failed", {
        message: error instanceof Error ? error.message : String(error),
      });
    });
  }, 10_000);
  persistenceTick.unref();

  app.addHook("onClose", async () => {
    shuttingDown = true;
    clearInterval(heartbeat);
    clearInterval(survivalTick);
    clearInterval(persistenceTick);
    clearInterval(combatTick);
    await players.persistAll();
    await creatures.persistAll();
    for (const socket of sockets) socket.close(1001, "server_shutdown");
    if (ownsDb) await db.end();
  });

  app.get("/health", { schema: { tags: ["system"] } }, () => ({
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
      const x = Number(request.params.x);
      const y = Number(request.params.y);
      if (!Number.isSafeInteger(x) || !Number.isSafeInteger(y)) {
        return reply.code(400).send({ error: "INVALID_CHUNK_COORDINATE" });
      }
      return visibleWorldChunk(x, y);
    },
  );

  await registerAuthRoutes(app, db);

  app.get("/shop/catalog", { schema: { tags: ["shop"] } }, () => ({
    items: SHOP_ITEMS,
  }));

  app.post<{ Body: { itemId: string; quantity: number } }>(
    "/shop/purchase",
    {
      schema: {
        tags: ["shop"],
        security: [{ bearerAuth: [] }],
        body: {
          type: "object",
          required: ["itemId", "quantity"],
          additionalProperties: false,
          properties: {
            itemId: { type: "string", minLength: 1, maxLength: 64 },
            quantity: { type: "integer", minimum: 1, maximum: 100 },
          },
        },
      },
    },
    async (request, reply) => {
      try {
        await request.jwtVerify();
        const userId = request.user.sub;
        const item = getShopItem(request.body.itemId);
        if (!item) return reply.code(404).send({ error: "SHOP_ITEM_NOT_FOUND" });
        const totalGold = calculatePurchase(item, request.body.quantity);
        if (totalGold === null) return reply.code(400).send({ error: "INVALID_PURCHASE_QUANTITY" });
        const state = await players.purchase(userId, item, request.body.quantity, totalGold);
        return { itemId: item.id, quantity: request.body.quantity, totalGold, state };
      } catch (error) {
        if (error instanceof Error && error.message === "INSUFFICIENT_GOLD") {
          return reply.code(409).send({ error: "INSUFFICIENT_GOLD" });
        }
        if (error instanceof Error && error.message === "PLAYER_NOT_FOUND") {
          return reply.code(404).send({ error: "PLAYER_NOT_FOUND" });
        }
        log("shop_purchase_failed", { message: error instanceof Error ? error.message : String(error) });
        return reply.code(500).send({ error: "PURCHASE_FAILED" });
      }
    },
  );

  app.get("/ws", { websocket: true }, (socket: WebSocket) => {
    sockets.add(socket);
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
            send(socket, { type: "auth_ok", userId: authenticatedUserId });
            send(socket, { type: "player_state", state });
            send(socket, { type: "creature_party", creatures: ownedCreatures });
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
          send(socket, { type: "player_state", state });
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
          send(socket, { type: "player_state", state });
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
            if (ammoType) state.inventory[ammoType] = Number(state.inventory[ammoType] ?? 0) - 1;
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
          send(socket, { type: "player_state", state });
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
                state.inventory["capture.orb"]=Math.max(0,Number(state.inventory["capture.orb"]??0)-1);
                players.markDirty(authenticatedUserId);
                combatTargets.delete(target.id); defeatedCreatures.add(target.id); capturedWorldCreatures.add(target.id);
                const result: ServerMessage={type:"creature_state",requestId:message.requestId,creature};
                for(const ownerSocket of userSockets.get(authenticatedUserId)??[])send(ownerSocket,result);
                return result;
              });
            }catch(error){
              const code=errorCode(error, "CAPTURE_FAILED");
              if(code==="NO_CAPTURE_ORB")return {type:"error",code:"NO_CAPTURE_ORB"};
              if(code==="CREATURE_ALREADY_CAPTURED")return {type:"error",code:"CREATURE_ALREADY_CAPTURED"};
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
                const player=players.get(authenticatedUserId);
                if(result.consumed&&player) { player.inventory["creature.feed"]=Math.max(0,Number(player.inventory["creature.feed"]??0)-1); players.markDirty(authenticatedUserId); }
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

        if (message.type === "create_base") {\n          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}\n          try{\n            const base=await bases.create(userId,message.name,message.x,message.y);\n            send(socket,{type:"base_state",base});\n          }catch(error){const code=errorCode(error,"BASE_CREATE_FAILED"); const allowed=["BASE_ALREADY_EXISTS","INVALID_BASE_COORDINATES","BASE_CREATE_FAILED"]; send(socket,{type:"error",code:(allowed.includes(code)?code:"BASE_CREATE_FAILED") as "BASE_ALREADY_EXISTS"|"INVALID_BASE_COORDINATES"|"BASE_CREATE_FAILED"});}\n          return;\n        }\n\n        if (message.type === "build") {\n          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}\n          try{\n            if(!BUILDING_TYPES.includes(message.type as BuildingType))throw new Error("INVALID_BUILDING_TYPE");\n            const building=await bases.createBuilding(userId,message.type as BuildingType,message.level,message.gridX,message.gridY);\n            send(socket,{type:"building_state",requestId:message.requestId,building});\n          }catch(error){const code=errorCode(error,"BUILD_FAILED"); const allowed=["BASE_NOT_FOUND","BASE_PERMISSION_DENIED","INVALID_BUILDING_TYPE","INVALID_BUILDING_LEVEL","INVALID_BUILDING_POSITION","BUILDING_POSITION_OCCUPIED","BUILDING_PREREQUISITE_MISSING","BUILD_FAILED"]; send(socket,{type:"error",code:(allowed.includes(code)?code:"BUILD_FAILED") as "BASE_NOT_FOUND"|"BASE_PERMISSION_DENIED"|"INVALID_BUILDING_TYPE"|"INVALID_BUILDING_LEVEL"|"INVALID_BUILDING_POSITION"|"BUILDING_POSITION_OCCUPIED"|"BUILDING_PREREQUISITE_MISSING"|"BUILD_FAILED"});}\n          return;\n        }\n\n        if (message.type === "subscribe_chunks") {
          if (!userId) {
            send(socket, { type: "error", code: "AUTH_REQUIRED" });
            return;
          }

          for (const coordinate of message.chunks) {
            send(socket, {
              type: "world_chunk",
              requestId: message.requestId,
              chunk: visibleWorldChunk(coordinate.x, coordinate.y),
            });
          }
        }
      }).catch((error) => {
        log("websocket_message_failed", {
          message: error instanceof Error ? error.message : String(error),
        });
        send(socket, { type: "error", code: "INVALID_MESSAGE" });
      });
    });

    socket.on("close", () => {
      if (authDeadline) {
        clearTimeout(authDeadline);
        authDeadline = null;
      }
      sockets.delete(socket);
      if (shuttingDown || !userId) return;
      const disconnectedUserId=userId;
      const connections = (playerConnections.get(disconnectedUserId) ?? 1) - 1;
      const socketsForUser = userSockets.get(disconnectedUserId);
      socketsForUser?.delete(socket);
      if (socketsForUser && socketsForUser.size === 0) userSockets.delete(disconnectedUserId);
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
        const unloadPromise = pendingMessageWork.then(() => pendingCreatureWork).then(
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

  return app;
}
