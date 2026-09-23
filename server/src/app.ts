import Fastify, { type FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import websocket from "@fastify/websocket";
import type { WebSocket } from "ws";
import { config } from "./config.js";
import { log } from "./logger.js";
import { parseClientMessage, type ServerMessage } from "./protocol.js";

function send(socket: WebSocket, message: ServerMessage): void {
  if (socket.readyState === socket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });

  await app.register(cors, { origin: true });
  await app.register(websocket, {
    options: {
      maxPayload: config.websocketMaxPayloadBytes,
      perMessageDeflate: false,
    },
  });

  app.get("/health", async () => ({
    status: "ok",
    service: "isles-of-mythos-server",
    environment: config.environment,
  }));

  app.get("/ready", async () => ({ status: "ready" }));

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
