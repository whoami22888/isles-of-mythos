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
      socket.send(JSON.stringify({ type: "get_party", requestId: "godot-read-1" }));
      await expect(waitFor(socket, (message) => message.type === "party_state" && message.requestId === "godot-read-1")).resolves.toMatchObject({ type: "party_state", requestId: "godot-read-1", party: null });

      socket.send(JSON.stringify({ type: "create_base", requestId: "godot-base-1", name: "Godot Gateway Base", x: 70123, y: -70123 }));
      await expect(waitFor(socket, (message) => message.type === "base_state" && message.requestId === "godot-base-1")).resolves.toMatchObject({ type: "base_state", requestId: "godot-base-1" });

      // Exact frames the Godot gateway serialises (required nullable fields are explicit nulls).
      socket.send(JSON.stringify({ type: "chat_history", requestId: "godot-chat-1", channel: "local", recipientUserId: null, guildId: null, partyId: null }));
      await expect(waitFor(socket, (message) => message.type === "chat_history" && message.requestId === "godot-chat-1")).resolves.toMatchObject({ type: "chat_history", requestId: "godot-chat-1" });
      socket.send(JSON.stringify({ type: "auction_list", requestId: "godot-auction-1", itemId: null, rarity: null, category: null, minLevel: null, maxLevel: null, minPrice: null, maxPrice: null }));
      await expect(waitFor(socket, (message) => message.type === "auction_list" && message.requestId === "godot-auction-1")).resolves.toMatchObject({ type: "auction_list", requestId: "godot-auction-1" });
      // Omitting a required nullable field is invalid on the wire, which is why the gateway must serialise nulls.
      socket.send(JSON.stringify({ type: "chat_history", requestId: "godot-chat-omitted", channel: "local" }));
      await expect(waitFor(socket, (message) => message.type === "error" && message.code === "INVALID_MESSAGE")).resolves.toMatchObject({ code: "INVALID_MESSAGE" });

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
