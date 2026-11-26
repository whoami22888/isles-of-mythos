import { Redis } from "ioredis";

/** Prompt 021: ephemeral request locks and a high-frequency session write-back buffer. */
export const REQUEST_LOCK_PREFIX = "lock:request:";
export const SESSION_DIRTY_SET = "session:dirty";
export const SESSION_STATE_PREFIX = "session:state:";
export const REQUEST_LOCK_TTL_SECONDS = 10;
export const FLUSH_INTERVAL_MS = 45_000;
export const REQUEST_DUPLICATE = "REQUEST_DUPLICATE";

export type RequestLockResult = "acquired" | "duplicate";

export interface SessionStatePatch {
  x?: number;
  y?: number;
  health?: number;
  updatedAtMs?: number;
}

export type SessionStateFlush = (userId: string, state: Required<Pick<SessionStatePatch, "updatedAtMs">> & SessionStatePatch) => Promise<void>;

/** Minimal surface used by the buffer so unit tests can inject a clock-aware fake. */
export interface RedisBufferClient {
  set(key: string, value: string, expiryMode: "EX", ttlSeconds: number, notExists: "NX"): Promise<"OK" | null>;
  del(...keys: string[]): Promise<number>;
  hset(key: string, values: Record<string, string>): Promise<number>;
  hgetall(key: string): Promise<Record<string, string>>;
  sadd(key: string, member: string): Promise<number>;
  smembers(key: string): Promise<string[]>;
  srem(key: string, ...members: string[]): Promise<number>;
  quit(): Promise<string>;
}

export function requestLockKey(requestId: string): string {
  return `${REQUEST_LOCK_PREFIX}${sanitizeRequestId(requestId)}`;
}

export function sessionStateKey(userId: string): string {
  return `${SESSION_STATE_PREFIX}${sanitizeRequestId(userId)}`;
}

export function sanitizeRequestId(value: string): string {
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > 64) throw new Error("INVALID_REQUEST_ID");
  return trimmed;
}

export class RedisWriteBackBuffer {
  readonly lockTtlSeconds: number;
  readonly flushIntervalMs: number;
  private readonly redis: RedisBufferClient;
  private readonly flushToPostgres: SessionStateFlush;
  private readonly now: () => number;
  private readonly ownsRedis: boolean;
  private timer: ReturnType<typeof setInterval> | null = null;
  private flushing: Promise<number> | null = null;

  constructor(options: {
    redis: RedisBufferClient;
    flushToPostgres: SessionStateFlush;
    lockTtlSeconds?: number;
    flushIntervalMs?: number;
    now?: () => number;
    ownsRedis?: boolean;
  }) {
    this.redis = options.redis;
    this.flushToPostgres = options.flushToPostgres;
    this.lockTtlSeconds = options.lockTtlSeconds ?? REQUEST_LOCK_TTL_SECONDS;
    this.flushIntervalMs = options.flushIntervalMs ?? FLUSH_INTERVAL_MS;
    this.now = options.now ?? Date.now;
    this.ownsRedis = options.ownsRedis ?? false;
  }

  /** SET NX EX 10 on `lock:request:{requestId}`. Rejects a second holder of the same key. */
  async acquireRequestLock(requestId: string): Promise<RequestLockResult> {
    const result = await this.redis.set(requestLockKey(requestId), "1", "EX", this.lockTtlSeconds, "NX");
    return result === "OK" ? "acquired" : "duplicate";
  }

  async releaseRequestLock(requestId: string): Promise<void> {
    await this.redis.del(requestLockKey(requestId));
  }

  /**
   * Run `fn` under the request lock. Simultaneous duplicates throw REQUEST_DUPLICATE.
   * The lock is released after `fn` settles so durable Postgres idempotency can still
   * replay a completed requestId; a 10s TTL covers a crash mid-handler.
   */
  async withRequestLock<T>(requestId: string, fn: () => Promise<T>): Promise<T> {
    const result = await this.acquireRequestLock(requestId);
    if (result === "duplicate") throw new Error(REQUEST_DUPLICATE);
    try {
      return await fn();
    } finally {
      await this.releaseRequestLock(requestId);
    }
  }

  /** Buffer high-frequency session fields (position, health) in Redis until the next flush. */
  async bufferSessionState(userId: string, patch: SessionStatePatch): Promise<void> {
    const id = sanitizeRequestId(userId);
    const key = sessionStateKey(id);
    const existing = await this.redis.hgetall(key);
    const merged: Record<string, string> = { ...existing };
    if (patch.x !== undefined) merged.x = String(patch.x);
    if (patch.y !== undefined) merged.y = String(patch.y);
    if (patch.health !== undefined) merged.health = String(patch.health);
    merged.updatedAtMs = String(patch.updatedAtMs ?? this.now());
    await this.redis.hset(key, merged);
    await this.redis.sadd(SESSION_DIRTY_SET, id);
  }

  /** Flush dirty session rows to PostgreSQL in one transactional batch (caller supplies the writer). */
  async flushDirty(): Promise<number> {
    if (this.flushing) return this.flushing;
    this.flushing = this.flushDirtyOnce().finally(() => {
      this.flushing = null;
    });
    return this.flushing;
  }

  start(): void {
    if (this.timer) return;
    this.timer = setInterval(() => {
      void this.flushDirty();
    }, this.flushIntervalMs);
    this.timer.unref();
  }

  async close(): Promise<void> {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    await this.flushDirty();
    if (this.ownsRedis) await this.redis.quit();
  }

  private async flushDirtyOnce(): Promise<number> {
    const userIds = await this.redis.smembers(SESSION_DIRTY_SET);
    if (userIds.length === 0) return 0;
    const flushed: string[] = [];
    for (const userId of userIds) {
      const raw = await this.redis.hgetall(sessionStateKey(userId));
      if (!raw || Object.keys(raw).length === 0) {
        flushed.push(userId);
        continue;
      }
      const state: SessionStatePatch & { updatedAtMs: number } = {
        updatedAtMs: Number(raw.updatedAtMs ?? this.now()),
      };
      if (raw.x !== undefined) state.x = Number(raw.x);
      if (raw.y !== undefined) state.y = Number(raw.y);
      if (raw.health !== undefined) state.health = Number(raw.health);
      await this.flushToPostgres(userId, state);
      await this.redis.del(sessionStateKey(userId));
      flushed.push(userId);
    }
    if (flushed.length > 0) await this.redis.srem(SESSION_DIRTY_SET, ...flushed);
    return flushed.length;
  }
}

export function connectRedisBufferClient(url: string): RedisBufferClient {
  const redis = new Redis(url, { maxRetriesPerRequest: 1, lazyConnect: true });
  return {
    set: (key, value, expiryMode, ttlSeconds, notExists) => redis.set(key, value, expiryMode, ttlSeconds, notExists),
    del: (...keys) => redis.del(...keys),
    hset: (key, values) => redis.hset(key, values),
    hgetall: (key) => redis.hgetall(key),
    sadd: (key, member) => redis.sadd(key, member),
    smembers: (key) => redis.smembers(key),
    srem: (key, ...members) => redis.srem(key, ...members),
    quit: () => redis.quit(),
  };
}
