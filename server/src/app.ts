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
import { WorldChunkCache } from "./world.js";

function send(socket: WebSocket, message: ServerMessage): void {
  if (socket.readyState === socket.OPEN) socket.send(JSON.stringify(message));
}

export interface BuildAppOptions {
  db?: Pool;
}

export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const db = options.db ?? createDbPool();
  const ownsDb = options.db === undefined;
  const world = new WorldChunkCache(256);
  const sockets = new Set<WebSocket>();
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

  app.addHook("onClose", async () => {
    clearInterval(heartbeat);
    for (const socket of sockets) socket.close(1001, "server_shutdown");
    if (ownsDb) await db.end();
  });

  app.get("/health", { schema: { tags: ["system"] } }, async () => ({
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

  app.get("/ws", { websocket: true }, (socket: WebSocket) => {
    sockets.add(socket);
    let userId: string | null = null;

    send(socket, { type: "server_ready", timestamp: Date.now() });

    socket.on("message", (raw) => {
      const message = parseClientMessage(raw.toString());

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
          const payload = app.jwt.verify<{ sub: string; username: string }>(message.token);
          userId = payload.sub;
          send(socket, { type: "auth_ok", userId });
        } catch {
          send(socket, { type: "error", code: "INVALID_TOKEN" });
          socket.close(1008, "invalid_token");
        }
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
    });

    socket.on("close", () => sockets.delete(socket));
    socket.on("error", (error) => {
      log("websocket_error", { message: error.message });
      sockets.delete(socket);
    });
  });

  return app;
}
