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
      const body = JSON.parse(registration.body) as { accessToken: string; user: { id: string } };
      const x = 100_000 + Number.parseInt(unique.slice(0, 4), 16) % 50_000;
      const y = -100_000 - Number.parseInt(unique.slice(4, 8), 16) % 50_000;

      await app.listen({ host: "127.0.0.1", port: 0 });
      const address = app.server.address();
      if (address === null || typeof address === "string") throw new Error("GODOT_GATEWAY_SERVER_NOT_LISTENING");
      socket = new WebSocket(`ws://127.0.0.1:${address.port}/ws`);
      await waitFor(socket, (message) => message.type === "server_ready");

      socket.send(JSON.stringify({ type: "get_guild", requestId: "before-auth" }));
      const unauthenticated = await waitFor(socket, (message) => message.type === "error" && message.code === "AUTH_REQUIRED");
      expect(unauthenticated).toMatchObject({ type: "error", code: "AUTH_REQUIRED" });
      expect(unauthenticated).not.toHaveProperty("requestId");

      socket.send(JSON.stringify({ type: "auth", token: body.accessToken }));
      await waitFor(socket, (message) => message.type === "auth_ok");
      socket.send(JSON.stringify({ type: "get_party", requestId: "godot-read-1" }));
      await expect(waitFor(socket, (message) => message.type === "party_state" && message.requestId === "godot-read-1")).resolves.toMatchObject({ type: "party_state", requestId: "godot-read-1", party: null });

      socket.send(JSON.stringify({ type: "create_base", requestId: "godot-base-1", name: "Godot Gateway Base", x, y }));
      await expect(waitFor(socket, (message) => message.type === "base_state" && message.requestId === "godot-base-1")).resolves.toMatchObject({ type: "base_state", requestId: "godot-base-1" });

      // Same player, new request id: the server still refuses a second base, and the refusal names that request.
      socket.send(JSON.stringify({ type: "create_base", requestId: "godot-base-dup", name: "Other Outpost", x: x + 1, y: y - 1 }));
      await expect(waitFor(socket, (message) => message.type === "error" && message.requestId === "godot-base-dup")).resolves.toMatchObject({
        type: "error",
        code: "BASE_ALREADY_EXISTS",
        requestId: "godot-base-dup",
      });
      // Replay of the same id and fingerprint returns the stored refusal. It must not create another base.
      socket.send(JSON.stringify({ type: "create_base", requestId: "godot-base-dup", name: "Other Outpost", x: x + 1, y: y - 1 }));
      await expect(waitFor(socket, (message) => message.type === "error" && message.requestId === "godot-base-dup")).resolves.toMatchObject({
        type: "error",
        code: "BASE_ALREADY_EXISTS",
        requestId: "godot-base-dup",
      });
      const bases = await db.query<{ count: string }>("SELECT count(*)::text AS count FROM player_bases WHERE owner_user_id = $1", [body.user.id]);
      expect(bases.rows[0]?.count).toBe("1");

      // Exact frames the Godot gateway serialises (required nullable fields are explicit nulls).
      socket.send(JSON.stringify({ type: "chat_history", requestId: "godot-chat-1", channel: "local", recipientUserId: null, guildId: null, partyId: null }));
      await expect(waitFor(socket, (message) => message.type === "chat_history" && message.requestId === "godot-chat-1")).resolves.toMatchObject({ type: "chat_history", requestId: "godot-chat-1" });
      socket.send(JSON.stringify({ type: "auction_list", requestId: "godot-auction-1", itemId: null, rarity: null, category: null, minLevel: null, maxLevel: null, minPrice: null, maxPrice: null }));
      await expect(waitFor(socket, (message) => message.type === "auction_list" && message.requestId === "godot-auction-1")).resolves.toMatchObject({ type: "auction_list", requestId: "godot-auction-1" });
      // Omitting a required nullable field is invalid on the wire, which is why the gateway must serialise nulls.
      socket.send(JSON.stringify({ type: "chat_history", requestId: "godot-chat-omitted", channel: "local" }));
      const omitted = await waitFor(socket, (message) => message.type === "error" && message.code === "INVALID_MESSAGE");
      expect(omitted).toMatchObject({ code: "INVALID_MESSAGE" });
      expect(omitted).not.toHaveProperty("requestId");

      socket.send(JSON.stringify({ type: "not_a_server_command", requestId: "godot-invalid-1" }));
      const unknown = await waitFor(socket, (message) => message.type === "error" && message.code === "INVALID_MESSAGE");
      expect(unknown).toMatchObject({ type: "error", code: "INVALID_MESSAGE" });
      expect(unknown).not.toHaveProperty("requestId");
      socket.send("not-json");
      const malformed = await waitFor(socket, (message) => message.type === "error" && message.code === "INVALID_MESSAGE");
      expect(malformed).toMatchObject({ type: "error", code: "INVALID_MESSAGE" });
      expect(malformed).not.toHaveProperty("requestId");
    } finally {
      socket?.close();
      await app.close();
      await db.end();
    }
  });

  it("rejects admin and refresh JWTs on the gameplay socket", async () => {
    const db = createDbPool();
    const app = await buildApp({ db, realmAiTickMs: 0 });
    let socket: WebSocket | undefined;
    try {
      await app.listen({ host: "127.0.0.1", port: 0 });
      const address = app.server.address();
      if (address === null || typeof address === "string") throw new Error("GODOT_GATEWAY_SERVER_NOT_LISTENING");
      const connect = async (): Promise<WebSocket> => {
        const ws = new WebSocket(`ws://127.0.0.1:${address.port}/ws`);
        await waitFor(ws, (message) => message.type === "server_ready");
        return ws;
      };
      socket = await connect();
      socket.send(JSON.stringify({
        type: "auth",
        token: app.jwt.sign({ sub: "11111111-1111-4111-8111-111111111111", username: "op", role: "admin", typ: "access" }),
      }));
      await expect(waitFor(socket, (message) => message.type === "error")).resolves.toMatchObject({ type: "error", code: "INVALID_TOKEN" });
      socket.close();
      socket = await connect();
      socket.send(JSON.stringify({
        type: "auth",
        token: app.jwt.sign({ sub: "11111111-1111-4111-8111-111111111111", username: "op", role: "player", typ: "refresh" }),
      }));
      await expect(waitFor(socket, (message) => message.type === "error")).resolves.toMatchObject({ type: "error", code: "INVALID_TOKEN" });
    } finally {
      socket?.close();
      await app.close();
      await db.end();
    }
  });
});
