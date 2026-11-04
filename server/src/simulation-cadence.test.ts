import { afterAll, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { buildApp } from "./app.js";
import { resetTickRateWindowForTests } from "./metrics.js";
import {
  AUTHORITATIVE_SIMULATION_HZ,
  AUTHORITATIVE_SIMULATION_TICK_MS,
  AUTHORITATIVE_TICK_RATE_MAX_HZ,
  AUTHORITATIVE_TICK_RATE_MIN_HZ,
  authoritativeTickRateAccepted,
  nextAuthoritativeTickDelayMs,
} from "./simulation-cadence.js";

function metricValue(metrics: string, name: string): number {
  const match = new RegExp("^" + name + " ([0-9.eE+-]+)$", "m").exec(metrics);
  if (!match) throw new Error("Missing metric " + name);
  return Number(match[1]);
}

describe("20 Hz authoritative simulation contract", () => {
  it("pins the simulation step at 50 ms and rejects the old 33 ms combat timer", () => {
    expect(AUTHORITATIVE_SIMULATION_HZ).toBe(20);
    expect(AUTHORITATIVE_SIMULATION_TICK_MS).toBe(50);
    expect(authoritativeTickRateAccepted(20)).toBe(true);
    expect(authoritativeTickRateAccepted(19)).toBe(true);
    expect(authoritativeTickRateAccepted(22)).toBe(true);
    expect(authoritativeTickRateAccepted(18.99)).toBe(false);
    expect(authoritativeTickRateAccepted(22.01)).toBe(false);
    // Measured on the previous main: tickRateHz 30.026 from a 33 ms interval.
    expect(authoritativeTickRateAccepted(30.026603186457024)).toBe(false);
    expect(authoritativeTickRateAccepted(1_000 / 33)).toBe(false);
    expect(AUTHORITATIVE_TICK_RATE_MIN_HZ).toBe(19);
    expect(AUTHORITATIVE_TICK_RATE_MAX_HZ).toBe(22);
  });

  it("schedules one fixed step and does not burst when a callback is late", () => {
    const stepNs = 50_000_000n;
    const started = nextAuthoritativeTickDelayMs(0n, 0n);
    expect(started.delayMs).toBe(50);
    expect(started.deadlineNs).toBe(stepNs);

    const onTime = nextAuthoritativeTickDelayMs(stepNs, started.deadlineNs);
    expect(onTime.delayMs).toBe(50);
    expect(onTime.deadlineNs).toBe(stepNs * 2n);

    const late = nextAuthoritativeTickDelayMs(130_000_000n, stepNs);
    expect(late.delayMs).toBe(50);
    expect(late.deadlineNs).toBe(180_000_000n);
    expect(() => nextAuthoritativeTickDelayMs(0n, 0n, 0)).toThrow("INVALID_SIMULATION_TICK");
  });
});

function idleDb(): Pool {
  const empty = Promise.resolve({ rows: [], rowCount: 0 });
  const client = {
    query: () => empty,
    release: () => undefined,
  };
  return {
    query: () => empty,
    connect: () => Promise.resolve(client),
    end: () => Promise.resolve(),
    on: () => undefined,
  } as unknown as Pool;
}

describe("live authoritative tick metric", () => {
  let app: FastifyInstance | undefined;

  afterAll(async () => {
    if (app) await app.close();
  });

  it("records about 20 Hz from the server metrics endpoint, not ~30 Hz", async () => {
    app = await buildApp({ db: idleDb(), realmAiTickMs: 0 });
    await app.listen({ host: "127.0.0.1", port: 0 });
    resetTickRateWindowForTests();
    await new Promise((resolve) => setTimeout(resolve, 1_600));
    const response = await app.inject({ method: "GET", url: "/metrics" });
    expect(response.statusCode).toBe(200);
    const hz = metricValue(response.body, "isles_tick_rate_hz");
    const windowSeconds = metricValue(response.body, "isles_tick_rate_window_seconds");
    expect(windowSeconds).toBeGreaterThanOrEqual(1);
    expect(hz).toBeGreaterThanOrEqual(AUTHORITATIVE_TICK_RATE_MIN_HZ);
    expect(hz).toBeLessThanOrEqual(AUTHORITATIVE_TICK_RATE_MAX_HZ);
    expect(hz).toBeLessThan(25);
  });
});
