import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";

async function waitFor(socket: WebSocket, predicate: (message: Record<string, unknown>) => boolean): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("GODOT_GATEWAY_INTEGRATION_TIMEOUT")), 2_000);
    const onMessage = (raw: Buffer) => {
      let message: unknown;
      try { message = JSON.parse(raw.toString()); } catch { return; }
      if (typeof message !== "object" || message === null || Array.isArray(message) || !predicate(message as Record<string, unknown>)) return;
      clearTimeout(timer);
      socket.off("message", onMessage);
      socket.off("error", onError);
      resolve(message as Record<string, unknown>);
    };
    const onError = (error: Error) => {
      clearTimeout(timer);
      socket.off("message", onMessage);
      socket.off("error", onError);
      reject(error);
    };
    socket.on("message", onMessage);
    socket.once("error", onError);
  });
}

describe("Godot authoritative command gateway contract", () => {
  it("uses the real Fastify WebSocket and rejects unauthenticated or malformed commands", async () => {
    const db = createDbPool();
    const app = await buildApp({ db });
    const unique = randomUUID().replace(/-/g, "").slice(0, 20);
    let socket: WebSocket | undefined;
    try {
      const registration = await app.inject({
        method: "POST",
        url: "/auth/register",
        payload: { username: `godot_${unique}`, email: `godot_${unique}@example.com`, password: "Correct-Horse-Battery-9" },
      });
      expect(registration.statusCode).toBe(201);
      const body = JSON.parse(registration.body) as { accessToken: string };

      await app.listen({ host: "127.0.0.1", port: 0 });
      const address = app.server.address();
      if (address === null || typeof address === "string") throw new Error("GODOT_GATEWAY_SERVER_NOT_LISTENING");
      socket = new WebSocket(`ws://127.0.0.1:${address.port}/ws`);
      await waitFor(socket, (message) => message.type === "server_ready");

      socket.send(JSON.stringify({ type: "get_guild", requestId: "before-auth" }));
      await expect(waitFor(socket, (message) => message.type === "error" && message.code === "AUTH_REQUIRED")).resolves.toMatchObject({ type: "error", code: "AUTH_REQUIRED" });

      socket.send(JSON.stringify({ type: "auth", token: body.accessToken }));
      await waitFor(socket, (message) => message.type === "auth_ok");
      socket.send(JSON.stringify({ type: "get_guild", requestId: "godot-read-1" }));
      await expect(waitFor(socket, (message) => message.type === "guild_state" && message.requestId === "godot-read-1")).resolves.toMatchObject({ type: "guild_state", requestId: "godot-read-1" });

      socket.send(JSON.stringify({ type: "not_a_server_command", requestId: "godot-invalid-1" }));
      await expect(waitFor(socket, (message) => message.type === "error" && message.code === "INVALID_MESSAGE")).resolves.toMatchObject({ type: "error", code: "INVALID_MESSAGE" });
      socket.send("not-json");
      await expect(waitFor(socket, (message) => message.type === "error" && message.code === "INVALID_MESSAGE")).resolves.toMatchObject({ type: "error", code: "INVALID_MESSAGE" });
    } finally {
      socket?.close();
      await app.close();
      await db.end();
    }
  });
});
