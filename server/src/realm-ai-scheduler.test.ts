import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import pg from "pg";
import { parseRealmAiIntervalMs, runRealmAiTickOnce, startRealmAiScheduler, REALM_AI_DEFAULT_INTERVAL_MS, REALM_AI_MIN_INTERVAL_MS } from "./realm-ai-scheduler.js";
import { RealmStore } from "./realm.js";

describe("parseRealmAiIntervalMs", () => {
  it("defaults when unset, empty or invalid", () => {
    for (const raw of [undefined, "", "  ", "abc", "-5", "1.5", "1e3", "99999999999999999999"]) expect(parseRealmAiIntervalMs(raw), String(raw)).toBe(REALM_AI_DEFAULT_INTERVAL_MS);
  });
  it("0 disables; small values clamp to the minimum; larger pass through", () => {
    expect(parseRealmAiIntervalMs("0")).toBe(0);
    expect(parseRealmAiIntervalMs("1")).toBe(REALM_AI_MIN_INTERVAL_MS);
    expect(parseRealmAiIntervalMs("30000")).toBe(30_000);
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
    s.stop();
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
    s.stop();
  });
  it("logs failures, keeps running, and intervalMs 0 starts nothing", async () => {
    const log = vi.fn();
    const run = vi.fn().mockRejectedValue(new Error("boom"));
    const s = startRealmAiScheduler({ run, intervalMs: 5_000, log });
    await vi.advanceTimersByTimeAsync(10_000);
    expect(log).toHaveBeenCalledWith("realm_ai_tick_failed", { message: "boom" });
    expect(run).toHaveBeenCalledTimes(2);
    s.stop();
    const off = startRealmAiScheduler({ run, intervalMs: 0 });
    expect(vi.getTimerCount()).toBe(0);
    off.stop();
  });
});

const url = process.env.DATABASE_URL;
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
    const lock = await pool.query<{ locked: boolean }>("SELECT pg_try_advisory_lock(18018) AS locked");
    expect(lock.rows[0].locked).toBe(true);
    await pool.query("SELECT pg_advisory_unlock(18018)");
  });
});
