import Fastify from "fastify";
import cors from "@fastify/cors";
import websocket from "@fastify/websocket";
import type { WebSocket } from "ws";
import { config } from "./config.js";
import { log } from "./logger.js";

const app = Fastify({ logger: false });

await app.register(cors, { origin: true });
await app.register(websocket);

app.get("/health", async () => ({
  status: "ok",
  service: "isles-of-mythos-server",
  environment: config.environment,
}));

app.get("/ready", async () => ({ status: "ready" }));

app.get("/ws", { websocket: true }, (socket: WebSocket) => {
  socket.send(JSON.stringify({ type: "server_ready", timestamp: Date.now() }));

  socket.on("message", (raw) => {
    try {
      const message = JSON.parse(raw.toString()) as { type?: string };

      if (message.type === "ping") {
        socket.send(JSON.stringify({ type: "pong", timestamp: Date.now() }));
      }
    } catch {
      socket.send(JSON.stringify({ type: "error", code: "INVALID_MESSAGE" }));
    }
  });

  socket.on("error", (error) => {
    log("websocket_error", { message: error.message });
  });
});

await app.listen({ host: config.host, port: config.port });
log("server_started", { host: config.host, port: config.port });
