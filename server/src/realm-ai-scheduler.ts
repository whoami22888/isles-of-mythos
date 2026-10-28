import type { Pool } from "pg";
import type { RealmStore } from "./realm.js";

/** Postgres advisory-lock key reserved for the realm AI tick (arbitrary, unique within this codebase). */
export const REALM_AI_LOCK_KEY = 18018;
export const REALM_AI_DEFAULT_INTERVAL_MS = 60_000;
export const REALM_AI_MIN_INTERVAL_MS = 5_000;

/**
 * Parses REALM_AI_TICK_MS. Unset/invalid -> default; "0" -> disabled (0);
 * otherwise clamped to at least REALM_AI_MIN_INTERVAL_MS.
 */
export function parseRealmAiIntervalMs(raw: string | undefined): number {
  if (raw === undefined || raw.trim() === "") return REALM_AI_DEFAULT_INTERVAL_MS;
  if (!/^\d+$/.test(raw.trim())) return REALM_AI_DEFAULT_INTERVAL_MS;
  const value = Number(raw.trim());
  if (!Number.isSafeInteger(value)) return REALM_AI_DEFAULT_INTERVAL_MS;
  if (value === 0) return 0;
  return Math.max(REALM_AI_MIN_INTERVAL_MS, value);
}

/**
 * Runs at most one realm AI tick across all server instances per window.
 * One dedicated connection carries the transaction-level advisory lock, the freshness check and
 * the tick itself, so a pool of size 1 cannot deadlock. The lock is released automatically at
 * COMMIT/ROLLBACK. A tick is skipped when the newest 'tick' event is younger than 90% of the
 * interval, so staggered instances do not double-tick a window. Returns true when a tick ran.
 */
export async function runRealmAiTickOnce(db: Pool, realms: Pick<RealmStore, "tickAI">, intervalMs: number): Promise<boolean> {
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    const got = await client.query<{ locked: boolean }>("SELECT pg_try_advisory_xact_lock($1) AS locked", [REALM_AI_LOCK_KEY]);
    if (got.rows[0]?.locked !== true) {
      await client.query("ROLLBACK");
      return false;
    }
    const recent = await client.query<{ fresh: boolean }>(
      "SELECT EXISTS(SELECT 1 FROM realm_ai_events WHERE event_type='tick' AND created_at > CURRENT_TIMESTAMP - ($1::double precision * interval '1 millisecond')) AS fresh",
      [Math.floor(intervalMs * 0.9)],
    );
    if (recent.rows[0]?.fresh === true) {
      await client.query("ROLLBACK");
      return false;
    }
    await realms.tickAI(client);
    await client.query("COMMIT");
    return true;
  } catch (error) {
    try { await client.query("ROLLBACK"); } catch { /* best effort; never mask the original error */ }
    throw error;
  } finally {
    client.release();
  }
}

export const REALM_AI_DEFAULT_DRAIN_TIMEOUT_MS = 10_000;

export interface RealmAiScheduler {
  /** Stops scheduling and resolves once any in-flight run has settled (bounded by drainTimeoutMs). */
  stop(): Promise<void>;
}

/**
 * Starts the server-owned realm AI scheduler. `intervalMs` 0 disables it (returns a no-op handle).
 * Single-flight within one process; the timer is unref'd and cleared by stop(), which also
 * waits (bounded) for an in-flight run so no tick executes after shutdown returns.
 */
export function startRealmAiScheduler(options: {
  run: () => Promise<boolean>;
  intervalMs: number;
  log?: (event: string, fields: Record<string, unknown>) => void;
  drainTimeoutMs?: number;
}): RealmAiScheduler {
  if (options.intervalMs <= 0) return { stop: () => Promise.resolve() };
  let inFlight: Promise<void> | undefined;
  let stopped = false;
  const safeLog = (event: string, fields: Record<string, unknown>): void => {
    try { options.log?.(event, fields); } catch { /* logging is best-effort and must never break the scheduler */ }
  };
  const timer = setInterval(() => {
    if (stopped || inFlight) return;
    const current: Promise<void> = Promise.resolve()
      .then(() => options.run())
      .then(() => undefined, (error: unknown) => safeLog("realm_ai_tick_failed", { message: error instanceof Error ? error.message : String(error) }))
      .finally(() => { if (inFlight === current) inFlight = undefined; });
    inFlight = current;
  }, options.intervalMs);
  timer.unref();
  return {
    async stop(): Promise<void> {
      stopped = true;
      clearInterval(timer);
      const pending = inFlight;
      if (!pending) return;
      const limit = Math.min(options.drainTimeoutMs ?? REALM_AI_DEFAULT_DRAIN_TIMEOUT_MS, REALM_AI_DEFAULT_DRAIN_TIMEOUT_MS);
      let deadline: NodeJS.Timeout | undefined;
      const timedOut = new Promise<boolean>((resolve) => {
        deadline = setTimeout(() => resolve(true), limit);
        deadline.unref();
      });
      try {
        if (await Promise.race([pending.then(() => false), timedOut])) safeLog("realm_ai_stop_drain_timeout", {});
      } finally {
        clearTimeout(deadline);
      }
    },
  };
}
