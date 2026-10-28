import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import pg from "pg";
import { parseRealmAiIntervalMs, runRealmAiTickOnce, startRealmAiScheduler, REALM_AI_DEFAULT_INTERVAL_MS, REALM_AI_MIN_INTERVAL_MS } from "./realm-ai-scheduler.js";
import { RealmStore } from "./realm.js";

describe("parseRealmAiIntervalMs", () => {
  it("defaults when unset, empty or invalid", () => {
    for (const raw of [undefined, "", "  ", "abc", "-5", "1.5", "1e3", "99999999999999999999", "2147483648", "9007199254740991"]) expect(parseRealmAiIntervalMs(raw), String(raw)).toBe(REALM_AI_DEFAULT_INTERVAL_MS);
  });
  it("0 disables; small values clamp to the minimum; larger pass through", () => {
    expect(parseRealmAiIntervalMs("0")).toBe(0);
    expect(parseRealmAiIntervalMs("1")).toBe(REALM_AI_MIN_INTERVAL_MS);
    expect(parseRealmAiIntervalMs("30000")).toBe(30_000);
    expect(parseRealmAiIntervalMs("2147483647")).toBe(2_147_483_647);
  });
});

describe("startRealmAiScheduler", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());
  it("runs once per interval and leaves no timer after stop()", async () => {
    const run = vi.fn().mockResolvedValue(true);
    const s = startRealmAiScheduler({ run, intervalMs: 10_000 });
    await vi.advanceTimersByTimeAsync(30_000);
    expect(run).toHaveBeenCalledTimes(3);
    void s.stop();
    expect(vi.getTimerCount()).toBe(0);
    await vi.advanceTimersByTimeAsync(30_000);
    expect(run).toHaveBeenCalledTimes(3);
  });
  it("is single-flight: a slow run is not overlapped", async () => {
    let release!: () => void;
    const run = vi.fn(() => new Promise<boolean>((resolve) => { release = () => resolve(true); }));
    const s = startRealmAiScheduler({ run, intervalMs: 5_000 });
    await vi.advanceTimersByTimeAsync(20_000);
    expect(run).toHaveBeenCalledTimes(1);
    release();
    await vi.advanceTimersByTimeAsync(5_000);
    expect(run).toHaveBeenCalledTimes(2);
    void s.stop();
  });
  it("a throwing logger never causes an unhandled rejection and ticks keep running", async () => {
    const unhandled: unknown[] = [];
    const onUnhandled = (reason: unknown): void => { unhandled.push(reason); };
    process.on("unhandledRejection", onUnhandled);
    try {
      const log = vi.fn(() => { throw new Error("logger exploded"); });
      const run = vi.fn().mockRejectedValue(new Error("boom"));
      const s = startRealmAiScheduler({ run, intervalMs: 5_000, log });
      await vi.advanceTimersByTimeAsync(20_000);
      await vi.advanceTimersByTimeAsync(0);
      vi.useRealTimers();
      await new Promise<void>((resolve) => setImmediate(resolve));
      expect(log).toHaveBeenCalled();
      expect(run).toHaveBeenCalledTimes(4);
      expect(unhandled).toEqual([]);
      void s.stop();
    } finally {
      process.off("unhandledRejection", onUnhandled);
    }
  });
  it("stop() waits for an in-flight run to settle and no new run starts afterwards", async () => {
    let settle!: () => void;
    const run = vi.fn(() => new Promise<boolean>((resolve) => { settle = () => resolve(true); }));
    const s = startRealmAiScheduler({ run, intervalMs: 5_000 });
    await vi.advanceTimersByTimeAsync(5_000);
    expect(run).toHaveBeenCalledTimes(1);
    let stopped = false;
    const stopping = s.stop().then(() => { stopped = true; });
    await vi.advanceTimersByTimeAsync(1_000);
    expect(stopped).toBe(false);
    settle();
    await stopping;
    expect(stopped).toBe(true);
    await vi.advanceTimersByTimeAsync(30_000);
    expect(run).toHaveBeenCalledTimes(1);
  });
  it("stop() on a never-settling run aborts, waits a second grace, then rejects (fail closed) and logs both", async () => {
    const log = vi.fn();
    const run = vi.fn(() => new Promise<boolean>(() => {}));
    const s = startRealmAiScheduler({ run, intervalMs: 5_000, log, drainTimeoutMs: 2_000 });
    await vi.advanceTimersByTimeAsync(5_000);
    let outcome = "pending";
    const stopping = s.stop().then(() => { outcome = "resolved"; }, (e: Error) => { outcome = e.message; });
    await vi.advanceTimersByTimeAsync(1_999);
    expect(outcome).toBe("pending");
    await vi.advanceTimersByTimeAsync(2_001);
    await stopping;
    expect(outcome).toBe("realm_ai_tick_unsettled");
    expect(log).toHaveBeenCalledWith("realm_ai_stop_drain_timeout", {});
    expect(log).toHaveBeenCalledWith("realm_ai_tick_unsettled", {});
    expect(vi.getTimerCount()).toBe(0);
  });
  it("stop() with nothing in flight resolves immediately and leaves no timer", async () => {
    const run = vi.fn().mockResolvedValue(true);
    const s = startRealmAiScheduler({ run, intervalMs: 5_000 });
    await s.stop();
    expect(vi.getTimerCount()).toBe(0);
    expect(run).not.toHaveBeenCalled();
  });
  it("logs failures, keeps running, and intervalMs 0 starts nothing", async () => {
    const log = vi.fn();
    const run = vi.fn().mockRejectedValue(new Error("boom"));
    const s = startRealmAiScheduler({ run, intervalMs: 5_000, log });
    await vi.advanceTimersByTimeAsync(10_000);
    expect(log).toHaveBeenCalledWith("realm_ai_tick_failed", { message: "boom" });
    expect(run).toHaveBeenCalledTimes(2);
    void s.stop();
    const off = startRealmAiScheduler({ run, intervalMs: 0 });
    expect(vi.getTimerCount()).toBe(0);
    void off.stop();
  });
});

const url = process.env.DATABASE_URL;
async function expectLockFree(pool: pg.Pool): Promise<void> {
  const c = await pool.connect();
  try {
    const lock = await c.query<{ locked: boolean }>("SELECT pg_try_advisory_lock(18018) AS locked");
    expect(lock.rows[0].locked).toBe(true);
    await c.query("SELECT pg_advisory_unlock(18018)");
  } finally { c.release(); }
}
describe.skipIf(!url)("runRealmAiTickOnce (real Postgres)", () => {
  let pool: pg.Pool;
  beforeEach(async () => { pool = new pg.Pool({ connectionString: url }); await pool.query("DELETE FROM realm_ai_events WHERE event_type='tick'"); });
  afterEach(async () => { await pool.end(); });

  it("ticks once per window even when two schedulers race, and releases the lock", async () => {
    const realms = new RealmStore(pool);
    const spy = vi.spyOn(realms, "tickAI");
    const results = await Promise.all([runRealmAiTickOnce(pool, realms, 60_000), runRealmAiTickOnce(pool, realms, 60_000)]);
    expect(results.filter(Boolean)).toHaveLength(1);
    expect(spy).toHaveBeenCalledTimes(1);
    // inside the window: skipped; lock must be free (a later attempt must not be blocked by a leaked lock)
    expect(await runRealmAiTickOnce(pool, realms, 60_000)).toBe(false);
    await expectLockFree(pool);
  });

  it("completes with a single-connection pool (DB_POOL_MAX=1) without deadlocking", async () => {
    const one = new pg.Pool({ connectionString: url, max: 1 });
    try {
      const realms = new RealmStore(one);
      const spy = vi.spyOn(realms, "tickAI");
      let timer: NodeJS.Timeout | undefined;
      const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error("deadlock: runRealmAiTickOnce did not finish with max=1")), 5_000); });
      try {
        expect(await Promise.race([runRealmAiTickOnce(one, realms, 60_000), timeout])).toBe(true);
      } finally { clearTimeout(timer); }
      expect(spy).toHaveBeenCalledTimes(1);
      const ticks = await one.query<{ n: string }>("SELECT COUNT(*)::text n FROM realm_ai_events WHERE event_type='tick'");
      expect(Number(ticks.rows[0].n)).toBeGreaterThan(0);
    } finally {
      await one.end();
    }
  });

  it("rolls back a failed tick (no partial tick rows) and leaves the lock free", async () => {
    const failing: Pick<RealmStore, "tickAI"> = {
      tickAI: async (executor) => {
        const realm = await executor!.query<{ id: string }>("SELECT id FROM realms LIMIT 1");
        await executor!.query("INSERT INTO realm_ai_events(realm_id,event_type,payload) VALUES($1,'tick','{}'::jsonb)", [realm.rows[0].id]);
        throw new Error("tick failed midway");
      },
    };
    await expect(runRealmAiTickOnce(pool, failing, 60_000)).rejects.toThrow("tick failed midway");
    const rows = await pool.query<{ n: string }>("SELECT COUNT(*)::text n FROM realm_ai_events WHERE event_type='tick'");
    expect(rows.rows[0].n).toBe("0");
    await expectLockFree(pool);
    // and a later healthy run still works
    expect(await runRealmAiTickOnce(pool, new RealmStore(pool), 60_000)).toBe(true);
  });
});

describe("startRealmAiScheduler stop() fail-closed drain", () => {
  it("aborts the run's signal after the drain deadline and resolves only after the run settled", async () => {
    vi.useFakeTimers();
    try {
      let settled = false;
      let sawAbort = false;
      const scheduler = startRealmAiScheduler({
        intervalMs: 1000,
        drainTimeoutMs: 200,
        run: (signal) => new Promise<boolean>((resolve) => {
          signal.addEventListener("abort", () => { sawAbort = true; settled = true; resolve(false); });
        }),
      });
      await vi.advanceTimersByTimeAsync(1000);
      const stopping = scheduler.stop();
      await vi.advanceTimersByTimeAsync(250);
      await stopping;
      expect(sawAbort).toBe(true);
      expect(settled).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });

  it("rejects with realm_ai_tick_unsettled when the run ignores abort", async () => {
    vi.useFakeTimers();
    try {
      const logged: string[] = [];
      const scheduler = startRealmAiScheduler({
        intervalMs: 1000,
        drainTimeoutMs: 200,
        log: (e) => logged.push(e),
        run: () => new Promise<boolean>(() => undefined),
      });
      await vi.advanceTimersByTimeAsync(1000);
      const stopping = scheduler.stop();
      const assertion = expect(stopping).rejects.toThrow("realm_ai_tick_unsettled");
      await vi.advanceTimersByTimeAsync(500);
      await assertion;
      expect(logged).toContain("realm_ai_stop_drain_timeout");
    } finally {
      vi.useRealTimers();
    }
  });
});

// Real-PostgreSQL abort semantics. A test-only advisory-lock key keeps these off the production key that
// other test files contend on, and a private witness table makes the durable outcome observable.
describe.skipIf(!url)("runRealmAiTickOnce abort semantics (real Postgres)", () => {
  const TEST_LOCK_KEY = 18_019_001;
  const witness = `realm_ai_abort_witness_${process.pid}`;
  let pool: pg.Pool;
  beforeEach(async () => {
    pool = new pg.Pool({ connectionString: url });
    await pool.query(`CREATE TABLE IF NOT EXISTS ${witness}(id serial PRIMARY KEY, note text)`);
    await pool.query(`TRUNCATE ${witness}`);
  });
  afterEach(async () => {
    await pool.query(`DROP TABLE IF EXISTS ${witness}`);
    await pool.end();
  });
  const count = async (): Promise<number> => Number((await pool.query<{ n: string }>(`SELECT COUNT(*)::text n FROM ${witness}`)).rows[0]?.n);
  const realmsWriting = (afterInsert: (c: pg.PoolClient) => Promise<void>) => ({
    tickAI: async (c?: pg.PoolClient) => {
      await c!.query(`INSERT INTO ${witness}(note) VALUES('tick')`);
      await afterInsert(c!);
    },
  });
  // Real clocks: the other describes in this file use fake timers only inside their own scope.
  beforeEach(() => vi.useRealTimers());

  it("abort while the transaction is blocked destroys the connection, settles, and never persists the tick", async () => {
    const abort = new AbortController();
    const realms = realmsWriting(async (c) => { await c.query("SELECT pg_sleep(1.5)"); });
    const run = runRealmAiTickOnce(pool, realms, 1, abort.signal, TEST_LOCK_KEY);
    await new Promise((r) => setTimeout(r, 300));
    abort.abort();
    await expect(run).rejects.toThrow();
    // The backend finishes its sleep, finds the client gone and rolls back; nothing may ever become durable.
    for (let i = 0; i < 40; i++) await new Promise((r) => setTimeout(r, 100));
    expect(await count()).toBe(0);
    const lock = await pool.query<{ n: string }>("SELECT COUNT(*)::text n FROM pg_locks WHERE locktype='advisory' AND objid=$1", [TEST_LOCK_KEY]);
    expect(Number(lock.rows[0]?.n)).toBe(0);
  }, 20_000);

  it("abort while COMMIT is in flight does not destroy the connection: the tick commits exactly once", async () => {
    const abort = new AbortController();
    let commitStarted!: () => void;
    const started = new Promise<void>((r) => { commitStarted = r; });
    let openGate!: () => void;
    const gate = new Promise<void>((r) => { openGate = r; });
    const delayedCommitDb = {
      connect: async () => {
        const c = await pool.connect();
        const query = c.query.bind(c) as (...a: unknown[]) => Promise<unknown>;
        (c as unknown as { query: unknown }).query = async (...a: unknown[]) => {
          if (a[0] === "COMMIT") { commitStarted(); await gate; }
          return query(...a);
        };
        return c;
      },
    };
    const realms = realmsWriting(() => Promise.resolve());
    const run = runRealmAiTickOnce(delayedCommitDb as never, realms, 1, abort.signal, TEST_LOCK_KEY);
    await started;
    abort.abort();
    openGate();
    expect(await run).toBe(true);
    expect(await count()).toBe(1);
  }, 20_000);
});
