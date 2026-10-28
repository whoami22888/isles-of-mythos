import { randomUUID } from "node:crypto";
import { Redis } from "ioredis";
import pg from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AntiCheatService } from "./anti-cheat.js";
import {
  PostgresAntiCheatEvidenceSink,
  listStoredEvidence,
  sanitizeEvidence,
} from "./anti-cheat-evidence-store.js";
import { MemoryAntiCheatStateStore, RedisAntiCheatStateStore } from "./anti-cheat-store.js";

const REDIS_URL = process.env.REDIS_URL?.trim() || "redis://127.0.0.1:6379";
const DATABASE_URL = process.env.DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:5432/isles_test";
// Nothing listens here; used to prove Redis failure degrades detection without changing authority.
const DEAD_REDIS_URL = "redis://127.0.0.1:1";

let admin: Redis;
let pool: pg.Pool;
const createdUsers: string[] = [];

function newUser(): string {
  const id = randomUUID();
  createdUsers.push(id);
  return id;
}

function redisService(extra: { sink?: PostgresAntiCheatEvidenceSink } = {}): AntiCheatService {
  return new AntiCheatService({ store: new RedisAntiCheatStateStore({ url: REDIS_URL }), ...extra });
}

async function purgeEvidenceFor(userIds: string[]): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SET LOCAL isles.anti_cheat_retention = 'on'");
    await client.query("DELETE FROM anti_cheat_evidence WHERE user_id = ANY($1::uuid[])", [userIds]);
    await client.query("COMMIT");
  } finally {
    client.release();
  }
}

beforeAll(async () => {
  admin = new Redis(REDIS_URL, { maxRetriesPerRequest: 1 });
  // Fail loudly: a missing Redis must never turn these tests into silent skips.
  expect(await admin.ping()).toBe("PONG");
  pool = new pg.Pool({ connectionString: DATABASE_URL, max: 4 });
  await pool.query("SELECT 1 FROM anti_cheat_evidence LIMIT 1");
});

afterAll(async () => {
  await purgeEvidenceFor(createdUsers);
  await pool.end();
  await admin.quit();
});

describe("shared detection state across backend instances (Redis)", () => {
  it("reproduces the original defect: process-local state cannot aggregate across instances", async () => {
    const userId = newUser();
    const a = new AntiCheatService({ store: new MemoryAntiCheatStateStore() });
    const b = new AntiCheatService({ store: new MemoryAntiCheatStateStore() });
    const results = [];
    for (let i = 0; i < 3; i += 1) results.push(await a.observeRejectedAction(userId, "RESOURCE_RANGE_ABUSE", {}, 1_000 + i));
    for (let i = 0; i < 2; i += 1) results.push(await b.observeRejectedAction(userId, "RESOURCE_RANGE_ABUSE", {}, 2_000 + i));
    // Five hostile rejections in total, but no instance ever sees the threshold.
    expect(results.every((r) => r === null)).toBe(true);
  });

  it("aggregates rejections observed by different instances and emits exactly once", async () => {
    const userId = newUser();
    const a = redisService();
    const b = redisService();
    try {
      const results = [];
      for (let i = 0; i < 3; i += 1) results.push(await a.observeRejectedAction(userId, "RESOURCE_RANGE_ABUSE", { distance: 9 }, 1_000 + i * 10));
      for (let i = 0; i < 2; i += 1) results.push(await b.observeRejectedAction(userId, "RESOURCE_RANGE_ABUSE", { distance: 9 }, 1_100 + i * 10));
      const emitted = results.filter((r) => r !== null);
      expect(emitted).toHaveLength(1);
      expect(emitted[0]).toMatchObject({ type: "RESOURCE_RANGE_ABUSE", evidence: { rejectedCount: 5 } });
      // A further rejection inside the cooldown, from the other instance, does not emit again.
      expect(await a.observeRejectedAction(userId, "RESOURCE_RANGE_ABUSE", { distance: 9 }, 1_200)).toBeNull();
    } finally {
      await a.close();
      await b.close();
    }
  });

  it("stays consistent under concurrent observations from several instances (atomic windows)", async () => {
    const userId = newUser();
    const services = [redisService(), redisService(), redisService(), redisService()];
    try {
      const calls: Promise<unknown>[] = [];
      for (let i = 0; i < 80; i += 1) {
        const service = services[i % services.length];
        if (!service) throw new Error("missing service");
        calls.push(service.observeRejectedAction(userId, "INVENTORY_MUTATION_REJECTED", { action: "craft", reason: "INSUFFICIENT_INVENTORY" }, 5_000));
      }
      const results = (await Promise.all(calls)) as Array<{ evidence: { rejectedCount: number } } | null>;
      const emitted = results.filter((r) => r !== null);
      expect(emitted).toHaveLength(1);
      expect(emitted[0]?.evidence.rejectedCount).toBe(5);
    } finally {
      await Promise.all(services.map((s) => s.close()));
    }
  });

  it("shares decayed suspicion between instances and survives a service restart", async () => {
    const userId = newUser();
    const first = redisService();
    await first.record(userId, "MOVEMENT_RATE_LIMIT", "HIGH", {}, 10_000);
    await first.close();
    const restarted = redisService();
    try {
      expect(await restarted.suspicionScore(userId, 10_000)).toBe(5);
      expect(await restarted.suspicionScore(userId, 12_000)).toBe(3);
      await restarted.record(userId, "MOVEMENT_RATE_LIMIT", "HIGH", {}, 10_000);
      expect(await restarted.suspicionScore(userId, 10_000)).toBe(10);
    } finally {
      await restarted.close();
    }
  });

  it("shares the multi-socket emission cooldown so several instances do not each emit", async () => {
    const userId = newUser();
    const a = redisService();
    const b = redisService();
    try {
      const first = await a.observeMultiSocket(userId, 4, 20_000);
      const second = await b.observeMultiSocket(userId, 5, 20_100);
      expect(first).toMatchObject({ type: "MULTI_SOCKET_ABUSE" });
      expect(second).toBeNull();
      // Cooldown expiry in Redis is real-time (PX TTL); it is covered by the key-expiry test below and, with
      // simulated time, by the memory-store tests.
    } finally {
      await a.close();
      await b.close();
    }
  });

  it("counts sockets across instances and detects abuse no single instance can see", async () => {
    const userId = newUser();
    const a = redisService();
    const b = redisService();
    try {
      // 2 sockets on each of 2 instances: neither instance sees more than 2, the shared lease set sees 4.
      expect(await a.connectSocket(userId, "a-1")).toBeNull();
      expect(await a.connectSocket(userId, "a-2")).toBeNull();
      expect(await b.connectSocket(userId, "b-1")).toBeNull();
      expect(await b.connectSocket(userId, "b-2")).toMatchObject({ type: "MULTI_SOCKET_ABUSE", evidence: { connectionCount: 4 } });
    } finally {
      await a.reset(userId);
      await a.close();
      await b.close();
    }
  });

  it("stops counting a socket on disconnect and when its instance releases leases on shutdown", async () => {
    const userId = newUser();
    const a = redisService();
    const b = redisService();
    try {
      for (const id of ["a-1", "a-2", "a-3"]) await a.connectSocket(userId, id);
      await a.disconnectSocket(userId, "a-3");
      await b.connectSocket(userId, "b-1");
      await b.connectSocket(userId, "b-2");
    } catch (error) {
      await a.close();
      await b.close();
      throw error;
    }
    const probe = new RedisAntiCheatStateStore({ url: REDIS_URL });
    try {
      const lease = (socketId: string) => probe.leaseSocket({ userId, socketId, ttlMs: 60_000 });
      // a-3 was released; a-1, a-2, b-1, b-2 remain -> a fresh probe makes 5.
      expect(await lease("probe")).toBe(5);
      await a.close(); // releases a-1 and a-2
      expect(await lease("probe")).toBe(3); // b-1, b-2, probe
      await probe.releaseSocket(userId, "probe");
    } finally {
      await probe.clearUser(userId);
      await probe.close();
      await b.close();
    }
  });

  it("lets leases of a crashed instance expire instead of counting forever", async () => {
    const userId = newUser();
    const store = new RedisAntiCheatStateStore({ url: REDIS_URL });
    try {
      for (const id of ["dead-1", "dead-2", "dead-3"]) await store.leaseSocket({ userId, socketId: id, ttlMs: 100, nowMs: 1_000 });
      // Far past the lease TTL, with no heartbeat refresh: only the new socket counts.
      expect(await store.leaseSocket({ userId, socketId: "live", ttlMs: 100, nowMs: 5_000 })).toBe(1);
    } finally {
      await store.clearUser(userId);
      await store.close();
    }
  });

  it("bounds lease state per user under a reconnect storm", async () => {
    const userId = newUser();
    const store = new RedisAntiCheatStateStore({ url: REDIS_URL });
    try {
      let count = 0;
      for (let i = 0; i < 120; i += 1) count = await store.leaseSocket({ userId, socketId: "s" + i, ttlMs: 60_000 });
      expect(count).toBe(64);
      expect(await admin.ttl("ac:v1:{" + userId + "}:sockets")).toBeGreaterThan(0);
    } finally {
      await store.clearUser(userId);
      await store.close();
    }
  });

  it("uses the Redis clock when no time is supplied, so skewed instance clocks agree", async () => {
    const userId = newUser();
    const a = redisService();
    const b = redisService();
    try {
      for (let i = 0; i < 3; i += 1) await a.observeRejectedAction(userId, "RESOURCE_RANGE_ABUSE", {});
      await b.observeRejectedAction(userId, "RESOURCE_RANGE_ABUSE", {});
      const last = await b.observeRejectedAction(userId, "RESOURCE_RANGE_ABUSE", {});
      expect(last).toMatchObject({ type: "RESOURCE_RANGE_ABUSE", evidence: { rejectedCount: 5 } });
    } finally {
      await a.close();
      await b.close();
    }
  });

  it("clears every key for a user on reset", async () => {
    const userId = newUser();
    const service = redisService();
    try {
      await service.observeRejectedAction(userId, "RESOURCE_RANGE_ABUSE", {}, 1_000);
      await service.record(userId, "MOVEMENT_RATE_LIMIT", "HIGH", {}, 1_000);
      await service.reset(userId);
      expect(await service.suspicionScore(userId, 1_000)).toBe(0);
      const left = await admin.keys("ac:v1:{" + userId + "}:*");
      expect(left).toHaveLength(0);
    } finally {
      await service.close();
    }
  });
});

describe("Redis failure never changes gameplay authority", () => {
  it("degrades to process-local detection without throwing", async () => {
    const userId = newUser();
    let degradedReason = "";
    const service = new AntiCheatService({
      store: new RedisAntiCheatStateStore({ url: DEAD_REDIS_URL, commandTimeoutMs: 100, connectTimeoutMs: 100 }),
      onDegraded: (reason) => {
        degradedReason = reason;
      },
    });
    try {
      const results = [];
      for (let i = 0; i < 5; i += 1) results.push(await service.observeRejectedAction(userId, "RESOURCE_RANGE_ABUSE", {}, 1_000 + i));
      // Local fallback still detects (per-instance), and the failure is visible to operators.
      expect(results.filter((r) => r !== null)).toHaveLength(1);
      expect(degradedReason).not.toBe("");
      expect(service.degradedObservations()).toBeGreaterThan(0);
      expect(await service.suspicionScore(userId, 1_004)).toBeGreaterThan(0);
    } finally {
      await service.close();
    }
  });

  it("keeps the gather/economy path authoritative when anti-cheat storage is down", async () => {
    // Anti-cheat observations are fire-and-forget; the authoritative mutation result must be identical
    // whether detection storage is healthy, slow or dead. The decision never consults suspicion state.
    const service = new AntiCheatService({
      store: new RedisAntiCheatStateStore({ url: DEAD_REDIS_URL, commandTimeoutMs: 50, connectTimeoutMs: 50 }),
    });
    try {
      const userId = newUser();
      const started = Date.now();
      await Promise.all(Array.from({ length: 50 }, () => service.observeRequestDuplicate(userId, "REPLAYED", 1_000)));
      // A dead store must not stall observation callers for 50 x timeout.
      expect(Date.now() - started).toBeLessThan(1_500);
    } finally {
      await service.close();
    }
  });
});

describe("durable evidence (PostgreSQL)", () => {
  it("persists evidence that survives a full service and connection restart", async () => {
    const userId = newUser();
    const sink = new PostgresAntiCheatEvidenceSink(pool, { flushIntervalMs: 60_000 });
    const service = new AntiCheatService({ store: new MemoryAntiCheatStateStore(), sink });
    await service.record(userId, "IMPOSSIBLE_MOVEMENT", "HIGH", { distance: 99, maxDistance: 0.4 }, 1_700_000_000_000);
    await service.close();

    const reopened = new pg.Pool({ connectionString: DATABASE_URL, max: 1 });
    try {
      const rows = await listStoredEvidence(reopened, userId);
      expect(rows).toHaveLength(1);
      expect(rows[0]).toMatchObject({
        type: "IMPOSSIBLE_MOVEMENT",
        severity: "HIGH",
        suspicion: 5,
        suppressedCount: 0,
        evidence: { distance: 99, maxDistance: 0.4 },
        occurredAt: new Date(1_700_000_000_000).toISOString(),
      });
    } finally {
      await reopened.end();
    }
  });

  it("throttles persisted volume under sustained hostile traffic and counts what it suppressed", async () => {
    const userId = newUser();
    const sink = new PostgresAntiCheatEvidenceSink(pool, { flushIntervalMs: 60_000 });
    const service = new AntiCheatService({ store: new MemoryAntiCheatStateStore(), sink });
    for (let i = 0; i < 500; i += 1) {
      await service.observeMovement(userId, { accepted: false, reason: "RATE_LIMITED", sequenceGap: 0, serverDt: 0 }, 100_000 + i * 5);
    }
    await service.record(userId, "MOVEMENT_RATE_LIMIT", "HIGH", {}, 110_000);
    await service.close();
    const rows = await listStoredEvidence(pool, userId);
    // 500 hostile events in 2.5 s => one persisted row; the next window carries the suppressed count.
    expect(rows).toHaveLength(2);
    const newest = rows[0];
    expect(newest?.suppressedCount).toBe(499);
  });

  it("bounds the in-memory queue when the database is unavailable and reports drops", async () => {
    const brokenPool = {
      query: () => Promise.reject(new Error("database unavailable")),
    } as unknown as pg.Pool;
    const sink = new PostgresAntiCheatEvidenceSink(brokenPool, { maxQueue: 50, batchSize: 1_000_000, flushIntervalMs: 60_000 });
    const userId = randomUUID();
    for (let i = 0; i < 5_000; i += 1) {
      sink.enqueue({ userId, type: "MOVEMENT_RATE_LIMIT", severity: "HIGH", suspicion: 5, suppressedCount: 0, evidence: {}, occurredAtMs: i });
    }
    expect(sink.queuedCount()).toBe(50);
    expect(sink.droppedCount()).toBe(4_950);
    await expect(sink.flush()).rejects.toThrow();
    expect(sink.queuedCount()).toBeLessThanOrEqual(50);
    await sink.close();
  });

  it("rejects updates and unmarked deletes, but retention can remove expired rows", async () => {
    const userId = newUser();
    const sink = new PostgresAntiCheatEvidenceSink(pool, { flushIntervalMs: 60_000, retentionDays: 30 });
    const now = Date.now();
    sink.enqueue({ userId, type: "IMPOSSIBLE_MOVEMENT", severity: "HIGH", suspicion: 5, suppressedCount: 0, evidence: {}, occurredAtMs: now - 40 * 86_400_000 });
    sink.enqueue({ userId, type: "IMPOSSIBLE_MOVEMENT", severity: "HIGH", suspicion: 5, suppressedCount: 0, evidence: {}, occurredAtMs: now });
    await sink.flush();

    await expect(pool.query("UPDATE anti_cheat_evidence SET severity='LOW' WHERE user_id=$1", [userId])).rejects.toThrow(/append-only/);
    await expect(pool.query("DELETE FROM anti_cheat_evidence WHERE user_id=$1", [userId])).rejects.toThrow(/retention routine/);
    expect(await listStoredEvidence(pool, userId)).toHaveLength(2);

    const removed = await sink.purgeExpired(now);
    expect(removed).toBeGreaterThanOrEqual(1);
    const remaining = await listStoredEvidence(pool, userId);
    expect(remaining).toHaveLength(1);
    expect(new Date(remaining[0]?.occurredAt ?? 0).getTime()).toBeGreaterThan(now - 86_400_000);
    await sink.close();
  });

  it("enforces severity, suspicion and size constraints at the database", async () => {
    const userId = newUser();
    await expect(
      pool.query("INSERT INTO anti_cheat_evidence (user_id,event_type,severity,suspicion,occurred_at) VALUES ($1,'X','BOGUS',1,now())", [userId]),
    ).rejects.toThrow(/severity_check/);
    await expect(
      pool.query("INSERT INTO anti_cheat_evidence (user_id,event_type,severity,suspicion,occurred_at) VALUES ($1,'X','LOW',101,now())", [userId]),
    ).rejects.toThrow(/suspicion_check|numeric field overflow/);
    await expect(
      pool.query("INSERT INTO anti_cheat_evidence (user_id,event_type,severity,suspicion,evidence,occurred_at) VALUES ($1,'X','LOW',1,$2::jsonb,now())", [
        userId,
        JSON.stringify({ blob: "x".repeat(5_000) }),
      ]),
    ).rejects.toThrow(/size_check/);
  });

  it("never lets one bad row poison the queue: invalid ids are refused and constraint violations are isolated", async () => {
    const goodUser = newUser();
    const sink = new PostgresAntiCheatEvidenceSink(pool, { flushIntervalMs: 60_000 });
    const base = { type: "IMPOSSIBLE_MOVEMENT", severity: "HIGH" as const, suspicion: 5, suppressedCount: 0, occurredAtMs: Date.now() };
    sink.enqueue({ ...base, userId: "not-a-uuid", evidence: {} });
    sink.enqueue({ ...base, userId: goodUser, evidence: { n: 1 } });
    sink.enqueue({ ...base, userId: goodUser, severity: "BOGUS" as unknown as "HIGH", evidence: {} });
    sink.enqueue({ ...base, userId: goodUser, evidence: { n: 2 } });
    await sink.flush();
    expect(sink.rejectedCount()).toBe(2);
    expect(sink.queuedCount()).toBe(0);
    const stored = await listStoredEvidence(pool, goodUser);
    expect(stored.map((row) => row.evidence.n).sort()).toEqual([1, 2]);
    await sink.close();
  });

  it("keeps every unattempted row when a transient DB error interrupts poison-row isolation", async () => {
    const user = newUser();
    let injected = false;
    // Real pool, except the first single-row insert of n=4 fails with a transient (non-data) error.
    const flaky = {
      query: (sql: string, values?: unknown[]) => {
        if (!injected && Array.isArray(values) && values.length === 7 && String(values[5]).includes('"n":4')) {
          injected = true;
          return Promise.reject(Object.assign(new Error("terminating connection"), { code: "57P01" }));
        }
        return pool.query(sql, values);
      },
      connect: () => pool.connect(),
    } as unknown as pg.Pool;
    const sink = new PostgresAntiCheatEvidenceSink(flaky, { flushIntervalMs: 60_000, batchSize: 100 });
    const base = { type: "IMPOSSIBLE_MOVEMENT", severity: "HIGH" as const, suspicion: 5, suppressedCount: 0, occurredAtMs: Date.now(), userId: user };
    for (const n of [1, 2]) sink.enqueue({ ...base, evidence: { n } });
    sink.enqueue({ ...base, severity: "BOGUS" as unknown as "HIGH", evidence: { n: 3 } });
    for (const n of [4, 5, 6]) sink.enqueue({ ...base, evidence: { n } });
    await expect(sink.flush()).rejects.toThrow("terminating connection");
    // n=4 (failed) and the never-attempted n=5, n=6 must all still be queued; nothing silently lost.
    expect(sink.queuedCount()).toBe(3);
    expect(sink.droppedCount()).toBe(0);
    await sink.flush();
    expect(sink.queuedCount()).toBe(0);
    const stored = await listStoredEvidence(pool, user);
    expect(stored.map((row) => row.evidence.n).sort()).toEqual([1, 2, 4, 5, 6]);
    expect(sink.rejectedCount()).toBe(1);
    await sink.close();
  });

  it("persists evidence from observations still in flight when the service is closed", async () => {
    const user = newUser();
    class SlowStore extends MemoryAntiCheatStateStore {
      override async addSuspicion(...args: Parameters<MemoryAntiCheatStateStore["addSuspicion"]>) {
        await new Promise((resolve) => setTimeout(resolve, 150));
        return super.addSuspicion(...args);
      }
    }
    const sink = new PostgresAntiCheatEvidenceSink(pool, { flushIntervalMs: 60_000 });
    const service = new AntiCheatService({ store: new SlowStore(), sink });
    // Handlers fire observations without awaiting them; shutdown begins while one is still waiting on its store.
    void service.record(user, "IMPOSSIBLE_MOVEMENT", "HIGH", { n: 1 });
    await service.close();
    const stored = await listStoredEvidence(pool, user);
    expect(stored.map((row) => row.evidence.n)).toEqual([1]);
  });

  it("keeps escape-heavy evidence under the database size limit instead of failing the insert", async () => {
    const userId = newUser();
    const sink = new PostgresAntiCheatEvidenceSink(pool, { flushIntervalMs: 60_000 });
    const hostile: Record<string, string> = {};
    for (let i = 0; i < 16; i += 1) hostile["k" + i] = "\u0001\"".repeat(40).slice(0, 128) + "\n\u0002".repeat(30);
    const cleaned = sanitizeEvidence(hostile);
    expect(JSON.stringify(cleaned).length).toBeLessThanOrEqual(3_000);
    sink.enqueue({ userId, type: "IMPOSSIBLE_MOVEMENT", severity: "HIGH", suspicion: 5, suppressedCount: 0, evidence: hostile, occurredAtMs: Date.now() });
    await sink.flush();
    expect(await listStoredEvidence(pool, userId)).toHaveLength(1);
    expect(sink.rejectedCount()).toBe(0);
    await sink.close();
  });

  it("strips credentials and request/socket/inventory identifiers from persisted evidence", () => {
    const cleaned = sanitizeEvidence({
      action: "craft",
      accessToken: "should-not-persist",
      password: "nope",
      requestId: "abc",
      socketId: "s1",
      itemId: "i1",
      distance: 4,
      huge: "y".repeat(1_000),
      bad: Number.NaN,
    });
    expect(cleaned).toEqual({ action: "craft", distance: 4, huge: "y".repeat(128) });
  });
});

describe("Redis memory stays bounded under hostile traffic", () => {
  it("gives every detection key a TTL and expires all of them after the window", async () => {
    // The production per-command timeout (250 ms) intentionally degrades detection under saturation. This test
    // deliberately issues many commands while the whole suite runs in parallel, so it uses a roomy timeout and
    // chunked bursts; the timeout is not what is being verified here (TTL/expiry is).
    const store = new RedisAntiCheatStateStore({ url: REDIS_URL, commandTimeoutMs: 10_000 });
    const users = Array.from({ length: 300 }, () => newUser());
    const prefixes = users.map((userId) => "ac:v1:{" + userId + "}:");
    const keysFor = async (): Promise<string[]> => {
      const found: string[] = [];
      for (const prefix of prefixes) found.push(...(await admin.keys(prefix + "*")));
      return found;
    };
    try {
      for (let offset = 0; offset < users.length; offset += 50) {
        await Promise.all(
          users.slice(offset, offset + 50).flatMap((userId) => [
            store.observeWindow({ key: "ac:v1:{" + userId + "}:t:a:b", windowMs: 500, threshold: 5, cooldownMs: 500 }),
            store.acquireCooldown({ key: "ac:v1:{" + userId + "}:persist:t", cooldownMs: 500 }),
          ]),
        );
      }
      // Independent of timing/load: no key that still exists may be persistent, and none may outlive 2 x window.
      for (const key of await keysFor()) {
        const ttl = await admin.pttl(key);
        expect(ttl).not.toBe(-1);
        expect(ttl).toBeLessThanOrEqual(1_000);
      }
      const deadline = Date.now() + 10_000;
      let remaining = await keysFor();
      while (remaining.length > 0 && Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 100));
        remaining = await keysFor();
      }
      expect(remaining).toEqual([]);
    } finally {
      await store.close();
    }
  });

  it("caps each window's memory at the threshold no matter how many events arrive", async () => {
    const userId = newUser();
    const store = new RedisAntiCheatStateStore({ url: REDIS_URL });
    try {
      const key = "ac:v1:{" + userId + "}:flood:a:b";
      for (let i = 0; i < 400; i += 1) await store.observeWindow({ key, nowMs: 1_000 + i, windowMs: 60_000, threshold: 8, cooldownMs: 60_000 });
      expect(await admin.zcard(key + ":w")).toBe(8);
      await store.clearUser(userId);
    } finally {
      await store.close();
    }
  });

  it("bounds the local fallback maps under a flood of distinct keys", async () => {
    const store = new MemoryAntiCheatStateStore({ maxWindows: 100, maxCooldowns: 100, maxSuspicion: 100 });
    for (let i = 0; i < 5_000; i += 1) {
      const userId = "u" + i;
      await store.observeWindow({ key: "ac:v1:{" + userId + "}:t:a:b", nowMs: i, windowMs: 1_000, threshold: 5, cooldownMs: 1_000 });
      await store.acquireCooldown({ key: "ac:v1:{" + userId + "}:persist:t", nowMs: i, cooldownMs: 1_000 });
      await store.addSuspicion({ userId, nowMs: i, increment: 1, decayPerSecond: 1, max: 100 });
    }
    expect(store.sizes()).toEqual({ windows: 100, cooldowns: 100, suspicion: 100 });
  });
});
