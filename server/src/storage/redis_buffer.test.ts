import { describe, expect, it } from "vitest";
import {
  FLUSH_INTERVAL_MS,
  REQUEST_DUPLICATE,
  REQUEST_LOCK_PREFIX,
  REQUEST_LOCK_TTL_SECONDS,
  RedisWriteBackBuffer,
  requestLockKey,
  type RedisBufferClient,
} from "./redis_buffer.js";

class MemoryRedis implements RedisBufferClient {
  readonly strings = new Map<string, { value: string; expiresAtMs: number | null }>();
  readonly hashes = new Map<string, Record<string, string>>();
  readonly sets = new Map<string, Set<string>>();
  nowMs = 0;

  private expired(expiresAtMs: number | null): boolean {
    return expiresAtMs !== null && expiresAtMs <= this.nowMs;
  }

  set(key: string, value: string, expiryMode: "EX", ttlSeconds: number, notExists: "NX"): Promise<"OK" | null> {
    if (expiryMode !== "EX" || notExists !== "NX") throw new Error("unsupported set mode");
    const existing = this.strings.get(key);
    if (existing && !this.expired(existing.expiresAtMs)) return Promise.resolve(null);
    this.strings.set(key, { value, expiresAtMs: this.nowMs + ttlSeconds * 1000 });
    return Promise.resolve("OK");
  }

  del(...keys: string[]): Promise<number> {
    let removed = 0;
    for (const key of keys) {
      if (this.strings.delete(key)) removed += 1;
      if (this.hashes.delete(key)) removed += 1;
      if (this.sets.delete(key)) removed += 1;
    }
    return Promise.resolve(removed);
  }

  hset(key: string, values: Record<string, string>): Promise<number> {
    const current = this.hashes.get(key) ?? {};
    Object.assign(current, values);
    this.hashes.set(key, current);
    return Promise.resolve(Object.keys(values).length);
  }

  hgetall(key: string): Promise<Record<string, string>> {
    return Promise.resolve({ ...(this.hashes.get(key) ?? {}) });
  }

  sadd(key: string, member: string): Promise<number> {
    const set = this.sets.get(key) ?? new Set<string>();
    const added = set.has(member) ? 0 : 1;
    set.add(member);
    this.sets.set(key, set);
    return Promise.resolve(added);
  }

  smembers(key: string): Promise<string[]> {
    return Promise.resolve([...(this.sets.get(key) ?? new Set<string>())]);
  }

  srem(key: string, ...members: string[]): Promise<number> {
    const set = this.sets.get(key);
    if (!set) return Promise.resolve(0);
    let removed = 0;
    for (const member of members) {
      if (set.delete(member)) removed += 1;
    }
    return Promise.resolve(removed);
  }

  quit(): Promise<string> {
    return Promise.resolve("OK");
  }
}

function createBuffer(redis: MemoryRedis, flushToPostgres: (userId: string, state: { x?: number; y?: number; health?: number; updatedAtMs: number }) => Promise<void>) {
  return new RedisWriteBackBuffer({
    redis,
    flushToPostgres,
    now: () => redis.nowMs,
  });
}

describe("Redis request lock and write-back buffer (Prompt 021)", () => {
  it("uses the lock:request:{requestId} key pattern and a 10-second TTL", async () => {
    expect(requestLockKey("abc-1")).toBe(`${REQUEST_LOCK_PREFIX}abc-1`);
    expect(REQUEST_LOCK_TTL_SECONDS).toBe(10);
    expect(FLUSH_INTERVAL_MS).toBe(45_000);
    const redis = new MemoryRedis();
    const buffer = createBuffer(redis, () => Promise.resolve());
    expect(await buffer.acquireRequestLock("shop-1")).toBe("acquired");
    const held = redis.strings.get(requestLockKey("shop-1"));
    expect(held?.expiresAtMs).toBe(10_000);
  });

  it("rejects a second simultaneous transactional request with the same requestId", async () => {
    const redis = new MemoryRedis();
    const buffer = createBuffer(redis, () => Promise.resolve());
    const started: string[] = [];
    const first = buffer.withRequestLock("tx-same", async () => {
      started.push("first");
      const raced = await buffer.withRequestLock("tx-same", () => Promise.resolve("second-should-not-run"));
      return raced;
    });
    await expect(first).rejects.toThrow(REQUEST_DUPLICATE);
    expect(started).toEqual(["first"]);
    // After the in-flight lock is released, the requestId is free again (durable Postgres idempotency can replay).
    await expect(buffer.withRequestLock("tx-same", () => Promise.resolve("ok"))).resolves.toBe("ok");
  });

  it("rejects a parallel acquire of the same requestId while the lock is held", async () => {
    const redis = new MemoryRedis();
    const buffer = createBuffer(redis, () => Promise.resolve());
    const first = buffer.acquireRequestLock("pay-1");
    const second = buffer.acquireRequestLock("pay-1");
    await expect(Promise.all([first, second])).resolves.toEqual(["acquired", "duplicate"]);
  });

  it("expires a crashed in-flight lock after 10 seconds so the requestId can be retried", async () => {
    const redis = new MemoryRedis();
    const buffer = createBuffer(redis, () => Promise.resolve());
    expect(await buffer.acquireRequestLock("hung")).toBe("acquired");
    redis.nowMs = 9_999;
    expect(await buffer.acquireRequestLock("hung")).toBe("duplicate");
    redis.nowMs = 10_000;
    expect(await buffer.acquireRequestLock("hung")).toBe("acquired");
  });

  it("buffers position and health ticks and flushes them in one transactional batch every 45 seconds", async () => {
    const redis = new MemoryRedis();
    const writes: Array<{ userId: string; x?: number; y?: number; health?: number }> = [];
    const buffer = new RedisWriteBackBuffer({
      redis,
      flushIntervalMs: FLUSH_INTERVAL_MS,
      now: () => redis.nowMs,
      flushToPostgres: (userId, state) => {
        writes.push({ userId, x: state.x, y: state.y, health: state.health });
        return Promise.resolve();
      },
    });
    await buffer.bufferSessionState("user-a", { x: 1, y: 2, health: 90 });
    await buffer.bufferSessionState("user-a", { x: 3, y: 4 });
    await buffer.bufferSessionState("user-b", { health: 70 });
    expect(writes).toEqual([]);
    expect(await buffer.flushDirty()).toBe(2);
    expect(writes).toEqual([
      { userId: "user-a", x: 3, y: 4, health: 90 },
      { userId: "user-b", x: undefined, y: undefined, health: 70 },
    ]);
    expect(await buffer.flushDirty()).toBe(0);
  });

  it("starts a 45-second flush interval", async () => {
    const redis = new MemoryRedis();
    const buffer = createBuffer(redis, () => Promise.resolve());
    expect(buffer.flushIntervalMs).toBe(45_000);
    buffer.start();
    await buffer.close();
  });
});
