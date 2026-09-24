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
import { addThreat, applyDamage, createCombatTarget, creatureAbilityDamage, distance, tickCreatureAi, tickStatuses, weaponFor, type CombatTarget } from "./combat.js";

function send(socket: WebSocket, message: ServerMessage): void {
  if (socket.readyState === socket.OPEN) socket.send(JSON.stringify(message));
}

function rawMessageToString(raw: WebSocket.RawData): string {
  if (typeof raw === "string") return raw;
  if (Buffer.isBuffer(raw)) return raw.toString("utf8");
  if (raw instanceof ArrayBuffer) return new TextDecoder().decode(new Uint8Array(raw));
  return Buffer.concat(raw).toString("utf8");
}

export interface BuildAppOptions {
  db?: Pool;
}

export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const db = options.db ?? createDbPool();
  const ownsDb = options.db === undefined;
  const world = new WorldChunkCache(256);
  const players = new PlayerStore(db);
  const sockets = new Set<WebSocket>();
  const playerConnections = new Map<string, number>();
  const userSockets = new Map<string, Set<WebSocket>>();
  const combatTargets = new Map<string, CombatTarget>();
  const attackCooldowns = new Map<string, number>();
  const dodgeCooldowns = new Map<string, number>();
  const blocking = new Set<string>();
  const invulnerableUntil = new Map<string, number>();
  const app = Fastify({ logger: false });

  await app.register(cors, { origin: true });
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
    for (const [targetId, target] of combatTargets) {
      tickStatuses(target, 250);
      if (target.health <= 0) {
        target.aiState = "dead";
        combatTargets.delete(targetId);
      }
    }
    const candidates = [...userSockets.keys()].flatMap((userId) => {
      const state = players.get(userId);
      return state ? [{ userId, x: state.x, y: state.y }] : [];
    });
    for (const target of combatTargets.values()) {
      const ai = tickCreatureAi(target, candidates, now, 250);
      const userId = ai.targetUserId;
      if (!userId || target.health <= 0) continue;
      const targetPlayer = players.get(userId);
      if (!targetPlayer) continue;
      if (ai.state === "chase") {
        const step = target.speed * 0.25;
        target.x += ai.moveX * step;
        target.y += ai.moveY * step;
      }
      if (ai.state === "attack" && distance(target, targetPlayer) <= target.attackRange) {
        const immune = (invulnerableUntil.get(userId) ?? 0) > now;
        if (!immune) {
          const blocked = blocking.has(userId);
          const damage = blocked ? Math.max(1, Math.round(target.attack * 0.35)) : target.attack;
          targetPlayer.health = Math.max(0, targetPlayer.health - damage);
          if (blocked) targetPlayer.stamina = Math.max(0, targetPlayer.stamina - 4);
          for (const socket of userSockets.get(userId) ?? []) send(socket, { type: "player_state", state: targetPlayer });
        }
      }
      if (ai.ability && distance(target, targetPlayer) <= ai.ability.range) {
        const immune = (invulnerableUntil.get(userId) ?? 0) > now;
        if (!immune) {
          const pseudoTarget = createCombatTarget(userId, "player", targetPlayer.x, targetPlayer.y, targetPlayer.level);
          pseudoTarget.health = targetPlayer.health;
          pseudoTarget.maxHealth = targetPlayer.health;
          pseudoTarget.defense = 0;
          const result = creatureAbilityDamage(pseudoTarget, ai.ability);
          targetPlayer.health = Math.max(0, targetPlayer.health - result.amount);
          for (const socket of userSockets.get(userId) ?? []) send(socket, { type: "player_state", state: targetPlayer });
        }
      }
    }
    for (const [userId, until] of invulnerableUntil) if (until <= now) invulnerableUntil.delete(userId);
  }, 250);
  combatTick.unref();

  const persistenceTick = setInterval(() => {
    void players.persistAll().catch((error) => {
      log("player_persistence_failed", {
        message: error instanceof Error ? error.message : String(error),
      });
    });
  }, 10_000);
  persistenceTick.unref();

  app.addHook("onClose", async () => {
    clearInterval(heartbeat);
    clearInterval(survivalTick);
    clearInterval(persistenceTick);
    clearInterval(combatTick);
    await players.persistAll();
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
      return world.get(x, y);
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

    send(socket, { type: "server_ready", timestamp: Date.now() });

    let messageQueue = Promise.resolve();
    socket.on("message", (raw) => {
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
          const state = await players.loadOrCreate(authenticatedUserId);
          userId = authenticatedUserId;
          const connections = playerConnections.get(authenticatedUserId) ?? 0;
          playerConnections.set(authenticatedUserId, connections + 1);
          const socketsForUser = userSockets.get(authenticatedUserId) ?? new Set<WebSocket>();
          socketsForUser.add(socket);
          userSockets.set(authenticatedUserId, socketsForUser);
          send(socket, { type: "auth_ok", userId: authenticatedUserId });
          send(socket, { type: "player_state", state });
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
        applyPlayerInput(state, message);
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
        state.selectedHotbarSlot = message.slot;
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
        const weapon = weaponFor(state.hotbar[state.selectedHotbarSlot]);
        if (!weapon) {
          send(socket, { type: "error", code: "INVALID_MESSAGE" });
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
        attackCooldowns.set(userId, now + weapon.cooldownMs);

        const match = /^creature:(-?\d+):(-?\d+)$/.exec(message.targetId);
        if (!match) {
          send(socket, { type: "error", code: "INVALID_MESSAGE" });
          return;
        }
        const targetX = Number(match[1]);
        const targetY = Number(match[2]);
        const chunk = world.get(Math.floor(targetX / 32), Math.floor(targetY / 32));
        const spawn = chunk.creatures.find((creature) => creature.id === message.targetId);
        if (!spawn) {
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
        state.stamina -= weapon.staminaCost;
        const result = applyDamage(target, weapon);
        addThreat(target, userId, result.amount);
        send(socket, {
          type: "combat_result",
          targetId: target.id,
          damage: result.amount,
          critical: result.critical,
          killed: result.killed,
          targetHealth: Math.ceil(target.health),
          status: result.statusApplied?.id,
        });
        if (result.killed) combatTargets.delete(target.id);
        return;
      }

      if (message.type === "dodge") {
        if (!userId) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
        const state = players.get(userId);
        if (!state) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
        const now = Date.now();
        if ((dodgeCooldowns.get(userId) ?? 0) > now) { send(socket, { type: "error", code: "COMBAT_COOLDOWN" }); return; }
        if (state.stamina < 20) { send(socket, { type: "error", code: "NO_STAMINA" }); return; }
        const length = Math.hypot(message.facingX, message.facingY) || 1;
        state.x = Math.max(-1_000_000, Math.min(1_000_000, state.x + (message.facingX / length) * 1.25));
        state.y = Math.max(-1_000_000, Math.min(1_000_000, state.y + (message.facingY / length) * 1.25));
        state.stamina -= 20;
        dodgeCooldowns.set(userId, now + 900);
        invulnerableUntil.set(userId, now + 350);
        send(socket, { type: "player_state", state });
        return;
      }

      if (message.type === "block") {
        if (!userId) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
        const state = players.get(userId);
        if (!state) { send(socket, { type: "error", code: "AUTH_REQUIRED" }); return; }
        if (message.active && state.stamina <= 0) { send(socket, { type: "error", code: "NO_STAMINA" }); return; }
        if (message.active) blocking.add(userId); else blocking.delete(userId);
        return;
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
            chunk: world.get(coordinate.x, coordinate.y),
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
      sockets.delete(socket);
      if (!userId) return;
      const connections = (playerConnections.get(userId) ?? 1) - 1;
      const socketsForUser = userSockets.get(userId);
      socketsForUser?.delete(socket);
      if (socketsForUser && socketsForUser.size === 0) userSockets.delete(userId);
      if (connections <= 0) {
        playerConnections.delete(userId);
        attackCooldowns.delete(userId);
        dodgeCooldowns.delete(userId);
        blocking.delete(userId);
        invulnerableUntil.delete(userId);
        void players.unload(userId).catch((error) => {
          log("player_disconnect_persistence_failed", {
            message: error instanceof Error ? error.message : String(error),
          });
        });
      } else {
        playerConnections.set(userId, connections);
      }
    });
    socket.on("error", (error) => {
      log("websocket_error", { message: error.message });
      sockets.delete(socket);
    });
  });

  return app;
}
