import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { config } from "./config.js";
import { parseClientMessage } from "./protocol.js";

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
});
