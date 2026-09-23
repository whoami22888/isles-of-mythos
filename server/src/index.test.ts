import { describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import type { AddressInfo } from "node:net";
import { buildApp } from "./app.js";
import { config } from "./config.js";
import { parseClientMessage } from "./protocol.js";

function waitForMessage(socket: WebSocket): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Timed out waiting for WebSocket message")), 2_000);

    socket.once("message", (raw) => {
      clearTimeout(timer);
      try {
        resolve(JSON.parse(raw.toString()) as unknown);
      } catch (error) {
        reject(error);
      }
    });

    socket.once("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

describe("server foundation", () => {
  it("uses a valid port", () => {
    expect(config.port).toBeGreaterThan(0);
    expect(config.port).toBeLessThanOrEqual(65535);
  });

  it("builds the Fastify application", async () => {
    const app = await buildApp();

    const health = await app.inject({ method: "GET", url: "/health" });
    expect(health.statusCode).toBe(200);
    expect(health.json()).toMatchObject({
      status: "ok",
      service: "isles-of-mythos-server",
    });

    const ready = await app.inject({ method: "GET", url: "/ready" });
    expect(ready.statusCode).toBe(200);
    expect(ready.json()).toEqual({ status: "ready" });

    await app.close();
  });

  it("accepts only the supported ping message", () => {
    expect(parseClientMessage('{"type":"ping"}')).toEqual({ type: "ping" });
    expect(parseClientMessage('{"type":"unknown"}')).toBeNull();
    expect(parseClientMessage("not-json")).toBeNull();
  });

  it("serves the WebSocket protocol end to end", async () => {
    const app = await buildApp();
    await app.listen({ host: "127.0.0.1", port: 0 });

    const address = app.server.address();
    if (address === null || typeof address === "string") {
      await app.close();
      throw new Error("Test server did not expose a TCP address");
    }

    const { port } = address as AddressInfo;
    const socket = new WebSocket(`ws://127.0.0.1:${port}/ws`);

    try {
      await new Promise<void>((resolve, reject) => {
        socket.once("open", () => resolve());
        socket.once("error", reject);
      });

      await expect(waitForMessage(socket)).resolves.toMatchObject({
        type: "server_ready",
      });

      socket.send(JSON.stringify({ type: "ping" }));
      await expect(waitForMessage(socket)).resolves.toMatchObject({
        type: "pong",
      });

      socket.send(JSON.stringify({ type: "unsupported" }));
      await expect(waitForMessage(socket)).resolves.toEqual({
        type: "error",
        code: "INVALID_MESSAGE",
      });
    } finally {
      socket.close();
      await app.close();
    }
  });
});
