import type { PoolClient } from "pg";
import { afterEach, describe, expect, it, vi } from "vitest";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { RealmStore } from "./realm.js";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// Vitest runs each test file in its own worker, so a spy on the prototype only sees this file's apps.
// Counting calls (not DB rows) keeps this test independent of other files that also write realm_ai_events.
describe("realm AI is server-scheduled (NET-04 slice 2b)", () => {
  afterEach(() => vi.restoreAllMocks());

  it("ticks on the server timer after listen and stops ticking after close", async () => {
    const calls = vi.spyOn(RealmStore.prototype, "tickAI");
    const db = createDbPool();
    const app = await buildApp({ db, realmAiTickMs: 100 });
    try {
      await app.listen({ host: "127.0.0.1", port: 0 });
      for (let i = 0; i < 100 && calls.mock.calls.length === 0; i++) await sleep(100);
      expect(calls.mock.calls.length, "server scheduler called tickAI without any client message").toBeGreaterThan(0);
    } finally {
      await app.close();
    }
    const afterClose = calls.mock.calls.length;
    await sleep(500);
    expect(calls.mock.calls.length).toBe(afterClose);
    await db.end();
  }, 30_000);

  it("marks shutdown and clears every gameplay timer BEFORE waiting for an in-flight realm AI tick", async () => {
    let release!: () => void;
    const gate = new Promise<void>((r) => { release = r; });
    let started!: () => void;
    const inFlight = new Promise<void>((r) => { started = r; });
    vi.spyOn(RealmStore.prototype, "tickAI").mockImplementation(async () => { started(); await gate; return undefined; });
    const cleared = vi.spyOn(globalThis, "clearInterval");
    const db = createDbPool();
    const app = await buildApp({ db, realmAiTickMs: 100 });
    try {
      await app.listen({ host: "127.0.0.1", port: 0 });
      await Promise.race([inFlight, sleep(15_000).then(() => { throw new Error("tick never started"); })]);
      cleared.mockClear();
      const closing = app.close();
      await sleep(400);
      const whileDraining = cleared.mock.calls.length;
      release();
      await closing;
      expect(whileDraining, "all interval timers must be cleared before the drain wait").toBe(cleared.mock.calls.length);
      expect(whileDraining).toBeGreaterThanOrEqual(10);
    } finally {
      release();
      await db.end().catch(() => undefined);
    }
  }, 40_000);

  it("aborts a tick that outlives the drain deadline and does not finish shutdown until it has settled", async () => {
    // The scheduler's tick connection is an isolated in-memory fake (identified by its call stack) so this
    // test never holds the shared Postgres advisory lock that other test files contend on.
    const real = createDbPool();
    let hangReject: ((e: Error) => void) | undefined;
    let released: Error | undefined;
    let started!: () => void;
    const inFlight = new Promise<void>((r) => { started = r; });
    const fakeClient = {
      query: (text: string): Promise<unknown> => {
        if (text.includes("pg_try_advisory_xact_lock")) return Promise.resolve({ rows: [{ locked: true }] });
        if (text.includes("realm_ai_events")) return Promise.resolve({ rows: [{ fresh: false }] });
        if (text === "HANG") { started(); return new Promise((_res, rej) => { hangReject = rej; }); }
        return Promise.resolve({ rows: [] });
      },
      release: (err?: Error) => { released = err; hangReject?.(err ?? new Error("released")); },
    };
    const db = new Proxy(real, {
      get(target, prop, receiver) {
        if (prop === "connect") {
          return (...args: unknown[]) => (new Error().stack ?? "").includes("runRealmAiTickOnce")
            ? Promise.resolve(fakeClient)
            : (target.connect as (...a: unknown[]) => unknown)(...args);
        }
        const value: unknown = Reflect.get(target, prop, receiver);
        return typeof value === "function" ? (value as (...a: unknown[]) => unknown).bind(target) : value;
      },
    });
    let settled = false;
    vi.spyOn(RealmStore.prototype, "tickAI").mockImplementation(async (executor?: PoolClient) => {
      try { await executor?.query("HANG"); } finally { settled = true; }
      return undefined;
    });
    const app = await buildApp({ db, realmAiTickMs: 100, realmAiDrainTimeoutMs: 300 });
    try {
      await app.listen({ host: "127.0.0.1", port: 0 });
      await Promise.race([inFlight, sleep(15_000).then(() => { throw new Error("tick never started"); })]);
      const t0 = Date.now();
      await app.close();
      expect(settled, "tick must have settled before app.close() resolves").toBe(true);
      expect(released?.message, "the tick connection must be destroyed, not returned to the pool").toBe("realm_ai_tick_aborted");
      expect(Date.now() - t0).toBeLessThan(5_000);
    } finally {
      await real.end().catch(() => undefined);
    }
  }, 40_000);
});
