import pg from "pg";
import type { Pool } from "pg";
import type { RealmStore } from "./realm.js";

/** Postgres advisory-lock key reserved for the realm AI tick (arbitrary, unique within this codebase). */
export const REALM_AI_LOCK_KEY = 18018;
export const REALM_AI_DEFAULT_INTERVAL_MS = 60_000;
export const REALM_AI_MIN_INTERVAL_MS = 5_000;
/** Node coerces setInterval delays above 2^31-1 ms to 1 ms, so larger values must never reach the timer. */
export const REALM_AI_MAX_INTERVAL_MS = 2_147_483_647;

/**
 * Parses REALM_AI_TICK_MS. Unset/invalid -> default; "0" -> disabled (0);
 * values above REALM_AI_MAX_INTERVAL_MS (setInterval overflow) -> default; otherwise clamped to at least REALM_AI_MIN_INTERVAL_MS.
 */
export function parseRealmAiIntervalMs(raw: string | undefined): number {
  if (raw === undefined || raw.trim() === "") return REALM_AI_DEFAULT_INTERVAL_MS;
  if (!/^\d+$/.test(raw.trim())) return REALM_AI_DEFAULT_INTERVAL_MS;
  const value = Number(raw.trim());
  if (!Number.isSafeInteger(value)) return REALM_AI_DEFAULT_INTERVAL_MS;
  if (value === 0) return 0;
  if (value > REALM_AI_MAX_INTERVAL_MS) return REALM_AI_DEFAULT_INTERVAL_MS;
  return Math.max(REALM_AI_MIN_INTERVAL_MS, value);
}

/**
 * Terminates a backend from a separate, short-lived connection (a pool of size 1 has no spare client).
 * The server closes the socket, which ends the client stream cleanly and rolls the transaction back.
 * Returns false when that was not possible so the caller can fall back to destroying the socket.
 */
async function terminateBackend(db: Pool, pid: number | undefined): Promise<boolean> {
  if (pid === undefined || !db.options) return false;
  const killer = new pg.Client({ ...db.options, connectionTimeoutMillis: 2_000 });
  killer.on("error", () => undefined);
  try {
    await killer.connect();
    const res = await killer.query<{ ok: boolean }>("SELECT pg_terminate_backend($1) AS ok", [pid]);
    return res.rows[0]?.ok === true;
  } catch {
    return false;
  } finally {
    await killer.end().catch(() => undefined);
  }
}

/**
 * Runs at most one realm AI tick across all server instances per window.
 * One dedicated connection carries the transaction-level advisory lock, the freshness check and
 * the tick itself, so a pool of size 1 cannot deadlock. The lock is released automatically at
 * COMMIT/ROLLBACK. A tick is skipped when the newest 'tick' event is younger than 90% of the
 * interval, so staggered instances do not double-tick a window. Returns true when a tick ran.
 */
export async function runRealmAiTickOnce(db: Pool, realms: Pick<RealmStore, "tickAI">, intervalMs: number, signal?: AbortSignal, lockKey: number = REALM_AI_LOCK_KEY): Promise<boolean> {
  const client = await db.connect();
  let released = false;
  let aborted = false;
  let commitSent = false;
  let killing: Promise<void> = Promise.resolve();
  const forceRelease = (): void => {
    if (released) return;
    released = true;
    client.release(new Error("realm_ai_tick_aborted"));
  };
  // Abort before COMMIT is sent = terminate the tick's backend from a second connection: the server rolls
  // back the open transaction, no COMMIT can follow, and the client stream ends cleanly (so the pg parser
  // promise settles). If the backend cannot be terminated the socket is destroyed instead. Once COMMIT has
  // been issued the outcome is decided by PostgreSQL, so abort is ignored and the acknowledgment is awaited.
  // Retry safety does not depend on any of this: the freshness guard skips a window that already has a tick.
  const onAbort = (): void => {
    if (aborted || commitSent) return;
    aborted = true;
    killing = terminateBackend(db, (client as unknown as { processID?: number }).processID).then((ok) => { if (!ok) forceRelease(); });
  };
  if (signal?.aborted) onAbort();
  else signal?.addEventListener("abort", onAbort, { once: true });
  try {
    if (aborted) throw new Error("realm_ai_tick_aborted");
    await client.query("BEGIN");
    const got = await client.query<{ locked: boolean }>("SELECT pg_try_advisory_xact_lock($1) AS locked", [lockKey]);
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
    if (aborted) throw new Error("realm_ai_tick_aborted");
    commitSent = true;
    await client.query("COMMIT");
    return true;
  } catch (error) {
    if (!aborted) {
      try { await client.query("ROLLBACK"); } catch { /* best effort; never mask the original error */ }
    }
    throw error;
  } finally {
    signal?.removeEventListener("abort", onAbort);
    if (aborted) {
      await killing;
      forceRelease();
    } else if (!released) {
      released = true;
      client.release();
    }
  }
}

export const REALM_AI_DEFAULT_DRAIN_TIMEOUT_MS = 10_000;

export interface RealmAiScheduler {
  /**
   * Stops scheduling and resolves only once any in-flight run has settled. If the run does not settle
   * within drainTimeoutMs its AbortSignal is fired (the DB connection is destroyed, so it cannot commit)
   * and a second bounded grace applies. Rejects with `realm_ai_tick_unsettled` if it still has not settled,
   * so callers must never treat a resolved stop() as anything but "no tick is running".
   */
  stop(): Promise<void>;
}

/**
 * Starts the server-owned realm AI scheduler. `intervalMs` 0 disables it (returns a no-op handle).
 * Single-flight within one process; the timer is unref'd and cleared by stop(), which also
 * waits (bounded) for an in-flight run so no tick executes after shutdown returns.
 */
export function startRealmAiScheduler(options: {
  run: (signal: AbortSignal) => Promise<boolean>;
  intervalMs: number;
  log?: (event: string, fields: Record<string, unknown>) => void;
  drainTimeoutMs?: number;
}): RealmAiScheduler {
  if (options.intervalMs <= 0) return { stop: () => Promise.resolve() };
  let inFlight: Promise<void> | undefined;
  let stopped = false;
  const abort = new AbortController();
  const safeLog = (event: string, fields: Record<string, unknown>): void => {
    try { options.log?.(event, fields); } catch { /* logging is best-effort and must never break the scheduler */ }
  };
  const timer = setInterval(() => {
    if (stopped || inFlight) return;
    const current: Promise<void> = Promise.resolve()
      .then(() => options.run(abort.signal))
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
      const settledWithin = async (ms: number): Promise<boolean> => {
        let finish: () => void = () => undefined;
        const timedOut = new Promise<boolean>((resolve) => {
          const deadline = setTimeout(() => resolve(false), ms);
          deadline.unref();
          // Settle the timer promise on exit so no pending promise outlives the race.
          finish = () => { clearTimeout(deadline); resolve(false); };
        });
        try {
          return await Promise.race([pending.then(() => true), timedOut]);
        } finally {
          finish();
        }
      };
      if (await settledWithin(limit)) return;
      safeLog("realm_ai_stop_drain_timeout", {});
      abort.abort();
      if (await settledWithin(limit)) return;
      safeLog("realm_ai_tick_unsettled", {});
      throw new Error("realm_ai_tick_unsettled");
    },
  };
}
