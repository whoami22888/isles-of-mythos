import { describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import type { AddressInfo } from "node:net";
import { buildApp } from "./app.js";
import { config } from "./config.js";
import { parseClientMessage } from "./protocol.js";

function waitForMessage(socket: WebSocket): Promise<unknown> {
  return waitForMatchingMessage(socket, () => true);
}

function waitForMatchingMessage(
  socket: WebSocket,
  predicate: (message: unknown) => boolean,
): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Timed out waiting for WebSocket message")), 2_000);

    const onMessage = (raw: Buffer) => {
      let message: unknown;
      try {
        message = JSON.parse(raw.toString()) as unknown;
      } catch (error) {
        clearTimeout(timer);
        socket.off("message", onMessage);
        reject(error);
        return;
      }
      if (!predicate(message)) return;
      clearTimeout(timer);
      socket.off("message", onMessage);
      resolve(message);
    };

    const onError = (error: Error) => {
      clearTimeout(timer);
      socket.off("message", onMessage);
      reject(error);
    };

    socket.on("message", onMessage);
    socket.once("error", onError);
  });
}

async function openSocket(app: Awaited<ReturnType<typeof buildApp>>): Promise<WebSocket> {
  await app.listen({ host: "127.0.0.1", port: 0 });
  const address = app.server.address();
  if (address === null || typeof address === "string") throw new Error("Test server has no TCP address");
  return new WebSocket(`ws://127.0.0.1:${(address as AddressInfo).port}/ws`);
}

describe("server foundation", () => {
  it("uses a valid port", () => {
    expect(config.port).toBeGreaterThan(0);
    expect(config.port).toBeLessThanOrEqual(65535);
  });

  it("builds the Fastify application and exposes readiness", async () => {
    const app = await buildApp();

    try {
      expect((await app.inject({ method: "GET", url: "/health" })).statusCode).toBe(200);
      const ready = await app.inject({ method: "GET", url: "/ready" });
      expect(ready.statusCode).toBe(200);
      expect(ready.json()).toMatchObject({ status: "ready", database: "ok" });

      const docs = await app.inject({ method: "GET", url: "/documentation/json" });
      expect(docs.statusCode).toBe(200);
      expect(docs.json().info.title).toBe("Isles of Mythos API");

      const chunk = await app.inject({ method: "GET", url: "/world/chunks/0/0" });
      expect(chunk.statusCode).toBe(200);
      expect(chunk.json().size).toBe(32);
    } finally {
      await app.close();
    }
  });

  it("parses only supported protocol messages", () => {
    expect(parseClientMessage('{"type":"ping"}')).toEqual({ type: "ping" });
    expect(parseClientMessage('{"type":"auth","token":"abc"}')).toEqual({ type: "auth", token: "abc" });
    expect(parseClientMessage('{"type":"subscribe_chunks","requestId":"r1","chunks":[{"x":0,"y":0}]}')).toEqual({
      type: "subscribe_chunks",
      requestId: "r1",
      chunks: [{ x: 0, y: 0 }],
    });
    expect(parseClientMessage('{"type":"move","dx":1,"dy":0,"dt":0.1}')).toEqual({
      type: "move",
      dx: 1,
      dy: 0,
      dt: 0.1,
    });
    expect(parseClientMessage('{"type":"select_hotbar","slot":7}')).toEqual({
      type: "select_hotbar",
      slot: 7,
    });
    expect(parseClientMessage('{"type":"select_hotbar","slot":8}')).toBeNull();
    expect(parseClientMessage('{"type":"move","dx":2,"dy":0,"dt":0.1}')).toBeNull();
    expect(parseClientMessage('{"type":"subscribe_chunks","requestId":"r1","chunks":[]}')).toBeNull();
    expect(parseClientMessage("not-json")).toBeNull();
  });

  it("authenticates a WebSocket before allowing world subscriptions", async () => {
    const app = await buildApp();
    const unique = Date.now();
    const register = await app.inject({
      method: "POST",
      url: "/auth/register",
      payload: {
        username: `ws_${unique}`,
        email: `ws_${unique}@example.com`,
        password: "Correct-Horse-Battery-9",
      },
    });
    expect(register.statusCode).toBe(201);
    const token = register.json().accessToken as string;

    const socket = await openSocket(app);

    try {
      const ready = waitForMessage(socket);
      await new Promise<void>((resolve, reject) => {
        socket.once("open", () => resolve());
        socket.once("error", reject);
      });
      await expect(ready).resolves.toMatchObject({ type: "server_ready" });

      const denied = waitForMessage(socket);
      socket.send(JSON.stringify({
        type: "subscribe_chunks",
        requestId: "denied",
        chunks: [{ x: 0, y: 0 }],
      }));
      await expect(denied).resolves.toEqual({ type: "error", code: "AUTH_REQUIRED" });

      const authenticated = waitForMessage(socket);
      const playerState = waitForMatchingMessage(socket, (message) => {
        return typeof message === "object" && message !== null && (message as { type?: unknown }).type === "player_state";
      });
      socket.send(JSON.stringify({ type: "auth", token }));
      await expect(authenticated).resolves.toMatchObject({ type: "auth_ok" });
      await expect(playerState).resolves.toMatchObject({
        type: "player_state",
        state: { userId: expect.any(String), health: 100, hunger: 100, oxygen: 100 },
      });

      const moved = waitForMessage(socket);
      socket.send(JSON.stringify({ type: "move", dx: 1, dy: 0, dt: 0.25 }));
      await expect(moved).resolves.toMatchObject({
        type: "player_state",
        state: { x: expect.any(Number), y: expect.any(Number) },
      });

      const selected = waitForMessage(socket);
      socket.send(JSON.stringify({ type: "select_hotbar", slot: 1 }));
      await expect(selected).resolves.toMatchObject({
        type: "player_state",
        state: { selectedHotbarSlot: 1 },
      });

      const chunk = waitForMessage(socket);
      socket.send(JSON.stringify({
        type: "subscribe_chunks",
        requestId: "world-1",
        chunks: [{ x: 0, y: 0 }],
      }));
      await expect(chunk).resolves.toMatchObject({
        type: "world_chunk",
        requestId: "world-1",
        chunk: { x: 0, y: 0, size: 32 },
      });
    } finally {
      socket.close();
      await app.close();
    }
  });
});
