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

function send(socket: WebSocket, message: ServerMessage): void {
  if (socket.readyState === socket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

export interface BuildAppOptions {
  db?: Pool;
}

export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const db = options.db ?? createDbPool();
  const ownsDb = options.db === undefined;
  const app = Fastify({ logger: false });

  await app.register(cors, { origin: true });
  await app.register(rateLimit, {
    max: 120,
    timeWindow: "1 minute",
  });
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
          bearerAuth: {
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT",
          },
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

  app.addHook("onClose", async () => {
    if (ownsDb) {
      await db.end();
    }
  });

  app.get("/health", {
    schema: {
      tags: ["system"],
    },
  }, async () => ({
    status: "ok",
    service: "isles-of-mythos-server",
    environment: config.environment,
  }));

  app.get("/ready", {
    schema: {
      tags: ["system"],
    },
  }, async (_request, reply) => {
    try {
      await db.query("SELECT 1");
      return { status: "ready", database: "ok" };
    } catch (error) {
      log("database_readiness_failed", {
        message: error instanceof Error ? error.message : String(error),
      });
      return reply.code(503).send({
        status: "not_ready",
        database: "unavailable",
      });
    }
  });

  await registerAuthRoutes(app, db);

  app.get("/ws", { websocket: true }, (socket: WebSocket) => {
    send(socket, { type: "server_ready", timestamp: Date.now() });

    socket.on("message", (raw) => {
      const message = parseClientMessage(raw.toString());

      if (message?.type === "ping") {
        send(socket, { type: "pong", timestamp: Date.now() });
        return;
      }

      send(socket, { type: "error", code: "INVALID_MESSAGE" });
    });

    socket.on("error", (error) => {
      log("websocket_error", { message: error.message });
    });
  });

  return app;
}
