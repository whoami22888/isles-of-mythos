import { Redis } from "ioredis";

/**
 * Detection-state storage for the anti-cheat service.
 *
 * This store only holds short-lived *detection* state (sliding windows, emission cooldowns and decayed
 * suspicion). It is never consulted by hard gameplay validation: movement, combat, gathering, inventory
 * and economy mutations are accepted or rejected by the authoritative server transactions regardless of
 * what this store says or whether it is reachable.
 */
export interface WindowObservation {
  /** Number of observations (including this one) currently inside the sliding window, capped at `threshold`. */
  count: number;
  /** True when the threshold is reached and the emission cooldown has elapsed; the cooldown is armed atomically. */
  emit: boolean;
}

export interface WindowRequest {
  key: string;
  nowMs?: number;
  windowMs: number;
  threshold: number;
  cooldownMs: number;
}

export interface CooldownRequest {
  key: string;
  nowMs?: number;
  cooldownMs: number;
}

export interface CooldownResult {
  /** True when the caller may emit/persist now. */
  emit: boolean;
  /** Number of observations suppressed since the last emission (reset when `emit` is true). */
  suppressed: number;
}

export interface SuspicionRequest {
  userId: string;
  nowMs?: number;
  increment: number;
  decayPerSecond: number;
  max: number;
}

export interface AntiCheatStateStore {
  readonly kind: "memory" | "redis";
  observeWindow(request: WindowRequest): Promise<WindowObservation>;
  /** Atomic per-key emission throttle used to keep persisted evidence volume bounded. */
  acquireCooldown(request: CooldownRequest): Promise<CooldownResult>;
  addSuspicion(request: SuspicionRequest): Promise<number>;
  getSuspicion(userId: string, decayPerSecond: number, nowMs?: number): Promise<number>;
  clearUser(userId: string): Promise<void>;
  close(): Promise<void>;
}

export const MAX_KEY_PART_LENGTH = 64;

/** Restricts externally derived key components so key cardinality and content stay bounded. */
export function sanitizeKeyPart(value: string): string {
  const cleaned = value.replace(/[^A-Za-z0-9_.-]/g, "_");
  return cleaned.length > MAX_KEY_PART_LENGTH ? cleaned.slice(0, MAX_KEY_PART_LENGTH) : cleaned;
}

const NEVER = Number.NEGATIVE_INFINITY;

interface MemoryWindow {
  timestampsMs: number[];
  lastEmittedMs: number;
}

interface MemoryCooldown {
  lastEmittedMs: number;
  suppressed: number;
}

interface MemorySuspicion {
  score: number;
  lastUpdatedMs: number;
}

export interface MemoryStoreLimits {
  maxWindows: number;
  maxCooldowns: number;
  maxSuspicion: number;
}

const DEFAULT_MEMORY_LIMITS: MemoryStoreLimits = { maxWindows: 10_000, maxCooldowns: 10_000, maxSuspicion: 50_000 };

function touch<V>(map: Map<string, V>, key: string, value: V, limit: number): void {
  map.delete(key);
  map.set(key, value);
  while (map.size > limit) {
    const oldest = map.keys().next().value;
    if (oldest === undefined) break;
    map.delete(oldest);
  }
}

/** Process-local store. Used in tests and as the degraded fallback when Redis is unreachable. */
export class MemoryAntiCheatStateStore implements AntiCheatStateStore {
  readonly kind = "memory" as const;
  private readonly windows = new Map<string, MemoryWindow>();
  private readonly cooldowns = new Map<string, MemoryCooldown>();
  private readonly suspicion = new Map<string, MemorySuspicion>();

  constructor(private readonly limits: MemoryStoreLimits = DEFAULT_MEMORY_LIMITS) {}

  observeWindow(request: WindowRequest): Promise<WindowObservation> {
    const nowMs = request.nowMs ?? Date.now();
    const previous = this.windows.get(request.key);
    const timestampsMs = (previous?.timestampsMs ?? []).filter(
      (timestampMs) => nowMs >= timestampMs && nowMs - timestampMs <= request.windowMs,
    );
    timestampsMs.push(nowMs);
    if (timestampsMs.length > request.threshold) timestampsMs.splice(0, timestampsMs.length - request.threshold);
    const lastEmittedMs = previous?.lastEmittedMs ?? NEVER;
    const emit = timestampsMs.length >= request.threshold && nowMs - lastEmittedMs >= request.cooldownMs;
    touch(this.windows, request.key, { timestampsMs, lastEmittedMs: emit ? nowMs : lastEmittedMs }, this.limits.maxWindows);
    return Promise.resolve({ count: timestampsMs.length, emit });
  }

  acquireCooldown(request: CooldownRequest): Promise<CooldownResult> {
    const nowMs = request.nowMs ?? Date.now();
    const previous = this.cooldowns.get(request.key);
    const lastEmittedMs = previous?.lastEmittedMs ?? NEVER;
    if (nowMs - lastEmittedMs < request.cooldownMs) {
      touch(this.cooldowns, request.key, { lastEmittedMs, suppressed: (previous?.suppressed ?? 0) + 1 }, this.limits.maxCooldowns);
      return Promise.resolve({ emit: false, suppressed: 0 });
    }
    const suppressed = previous?.suppressed ?? 0;
    touch(this.cooldowns, request.key, { lastEmittedMs: nowMs, suppressed: 0 }, this.limits.maxCooldowns);
    return Promise.resolve({ emit: true, suppressed });
  }

  addSuspicion(request: SuspicionRequest): Promise<number> {
    const nowMs = request.nowMs ?? Date.now();
    const state = this.suspicion.get(request.userId);
    const decayed = state ? Math.max(0, state.score - ((nowMs - state.lastUpdatedMs) / 1000) * request.decayPerSecond) : 0;
    const score = Math.min(request.max, decayed + request.increment);
    touch(this.suspicion, request.userId, { score, lastUpdatedMs: nowMs }, this.limits.maxSuspicion);
    return Promise.resolve(score);
  }

  getSuspicion(userId: string, decayPerSecond: number, nowMs = Date.now()): Promise<number> {
    const state = this.suspicion.get(userId);
    if (!state) return Promise.resolve(0);
    return Promise.resolve(Math.max(0, state.score - ((nowMs - state.lastUpdatedMs) / 1000) * decayPerSecond));
  }

  clearUser(userId: string): Promise<void> {
    this.suspicion.delete(userId);
    const prefix = userKeyPrefix(userId);
    for (const map of [this.windows, this.cooldowns]) {
      for (const key of map.keys()) {
        if (key.startsWith(prefix)) map.delete(key);
      }
    }
    return Promise.resolve();
  }

  close(): Promise<void> {
    this.windows.clear();
    this.cooldowns.clear();
    this.suspicion.clear();
    return Promise.resolve();
  }

  /** Diagnostics for bounded-memory tests. */
  sizes(): { windows: number; cooldowns: number; suspicion: number } {
    return { windows: this.windows.size, cooldowns: this.cooldowns.size, suspicion: this.suspicion.size };
  }
}

/** Keys are namespaced by user so a user's state can be cleared without scanning unrelated keys. */
export function userKeyPrefix(userId: string): string {
  return "ac:v1:{" + sanitizeKeyPart(userId) + "}:";
}

// All times come from the caller when supplied (deterministic tests) and otherwise from the Redis server
// clock, so independent backend instances with skewed clocks agree on window boundaries.
const WINDOW_SCRIPT = `
local now = tonumber(ARGV[1])
if now < 0 then
  local t = redis.call('TIME')
  now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
end
local windowMs = tonumber(ARGV[2])
local threshold = tonumber(ARGV[3])
local cooldownMs = tonumber(ARGV[4])
local seq = redis.call('INCR', KEYS[3])
redis.call('PEXPIRE', KEYS[3], windowMs + cooldownMs)
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', now - windowMs - 1)
redis.call('ZREMRANGEBYSCORE', KEYS[1], now + 1, '+inf')
redis.call('ZADD', KEYS[1], now, now .. ':' .. seq)
local size = redis.call('ZCARD', KEYS[1])
if size > threshold then
  redis.call('ZREMRANGEBYRANK', KEYS[1], 0, size - threshold - 1)
  size = threshold
end
redis.call('PEXPIRE', KEYS[1], windowMs)
local emit = 0
if size >= threshold then
  if redis.call('SET', KEYS[2], '1', 'NX', 'PX', cooldownMs) then emit = 1 end
end
return {size, emit}
`;

const COOLDOWN_SCRIPT = `
local now = tonumber(ARGV[1])
if now < 0 then
  local t = redis.call('TIME')
  now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
end
local cooldownMs = tonumber(ARGV[2])
local suppressedTtl = cooldownMs * 4
if redis.call('SET', KEYS[1], '1', 'NX', 'PX', cooldownMs) then
  local suppressed = tonumber(redis.call('GET', KEYS[2]) or '0')
  redis.call('DEL', KEYS[2])
  return {1, suppressed}
end
redis.call('INCR', KEYS[2])
redis.call('PEXPIRE', KEYS[2], suppressedTtl)
return {0, 0}
`;

const SUSPICION_SCRIPT = `
local now = tonumber(ARGV[1])
if now < 0 then
  local t = redis.call('TIME')
  now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
end
local increment = tonumber(ARGV[2])
local decay = tonumber(ARGV[3])
local max = tonumber(ARGV[4])
local score = 0
local raw = redis.call('HMGET', KEYS[1], 'score', 'ts')
if raw[1] then
  score = math.max(0, tonumber(raw[1]) - ((now - tonumber(raw[2])) / 1000) * decay)
end
score = math.min(max, score + increment)
redis.call('HSET', KEYS[1], 'score', tostring(score), 'ts', tostring(now))
local ttlMs = math.ceil((score / math.max(decay, 0.000001)) * 1000) + 60000
redis.call('PEXPIRE', KEYS[1], ttlMs)
return tostring(score)
`;

declare module "ioredis" {
  // Declaration merging requires the original type parameter list even though it is unused here.
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  interface RedisCommander<Context> {
    antiCheatWindow(keys: [string, string, string], args: [number, number, number, number]): Promise<[number, number]>;
    antiCheatCooldown(keys: [string, string], args: [number, number]): Promise<[number, number]>;
    antiCheatSuspicion(key: string, args: [number, number, number, number]): Promise<string>;
  }
}

export interface RedisStoreOptions {
  url: string;
  /** Per-command timeout so a stalled Redis cannot back up detection work. */
  commandTimeoutMs?: number;
  connectTimeoutMs?: number;
}

export class RedisAntiCheatStateStore implements AntiCheatStateStore {
  readonly kind = "redis" as const;
  private readonly client: Redis;
  private readonly connectTimeoutMs: number;
  private pendingReady: Promise<void> | null = null;

  constructor(options: RedisStoreOptions | { client: Redis; connectTimeoutMs?: number }) {
    this.connectTimeoutMs = options.connectTimeoutMs ?? 1_000;
    if ("client" in options) {
      this.client = options.client;
    } else {
      this.client = new Redis(options.url, {
        commandTimeout: options.commandTimeoutMs ?? 250,
        connectTimeout: options.connectTimeoutMs ?? 1_000,
        maxRetriesPerRequest: 1,
        enableOfflineQueue: false,
        lazyConnect: false,
        retryStrategy: (attempt) => Math.min(2_000, 100 * 2 ** Math.min(attempt, 5)),
      });
    }
    // Connection errors are surfaced per command (and handled by the degrading service); this listener only
    // prevents an unhandled 'error' event from terminating the process.
    this.client.on("error", () => undefined);
    this.client.defineCommand("antiCheatWindow", { numberOfKeys: 3, lua: WINDOW_SCRIPT });
    this.client.defineCommand("antiCheatCooldown", { numberOfKeys: 2, lua: COOLDOWN_SCRIPT });
    this.client.defineCommand("antiCheatSuspicion", { numberOfKeys: 1, lua: SUSPICION_SCRIPT });
  }

  /**
   * The offline queue is disabled on purpose: it would replay stale commands after an outage. Instead each
   * operation waits (bounded by the connect timeout, shared by concurrent callers) for the connection to be ready.
   */
  private waitReady(): Promise<void> {
    if (this.client.status === "ready") return Promise.resolve();
    if (!this.pendingReady) {
      this.pendingReady = new Promise<void>((resolve, reject) => {
        const onReady = (): void => {
          cleanup();
          resolve();
        };
        const timer = setTimeout(() => {
          cleanup();
          reject(new Error("redis_not_ready"));
        }, this.connectTimeoutMs);
        const cleanup = (): void => {
          clearTimeout(timer);
          this.client.off("ready", onReady);
          this.pendingReady = null;
        };
        this.client.once("ready", onReady);
      });
    }
    return this.pendingReady;
  }

  async observeWindow(request: WindowRequest): Promise<WindowObservation> {
    await this.waitReady();
    const [size, emit] = await this.client.antiCheatWindow(
      [request.key + ":w", request.key + ":e", request.key + ":s"],
      [request.nowMs ?? -1, request.windowMs, request.threshold, request.cooldownMs],
    );
    return { count: Number(size), emit: Number(emit) === 1 };
  }

  async acquireCooldown(request: CooldownRequest): Promise<CooldownResult> {
    await this.waitReady();
    const [emit, suppressed] = await this.client.antiCheatCooldown(
      [request.key + ":c", request.key + ":n"],
      [request.nowMs ?? -1, request.cooldownMs],
    );
    return { emit: Number(emit) === 1, suppressed: Number(suppressed) };
  }

  async addSuspicion(request: SuspicionRequest): Promise<number> {
    await this.waitReady();
    const score = await this.client.antiCheatSuspicion(userKeyPrefix(request.userId) + "suspicion", [
      request.nowMs ?? -1,
      request.increment,
      request.decayPerSecond,
      request.max,
    ]);
    return Number(score);
  }

  async getSuspicion(userId: string, decayPerSecond: number, nowMs?: number): Promise<number> {
    await this.waitReady();
    const raw = await this.client.hmget(userKeyPrefix(userId) + "suspicion", "score", "ts");
    if (raw[0] === null || raw[0] === undefined || raw[1] === null || raw[1] === undefined) return 0;
    const now = nowMs ?? Number((await this.client.time())[0]) * 1000;
    return Math.max(0, Number(raw[0]) - ((now - Number(raw[1])) / 1000) * decayPerSecond);
  }

  async clearUser(userId: string): Promise<void> {
    await this.waitReady();
    const prefix = userKeyPrefix(userId);
    let cursor = "0";
    do {
      const [next, keys] = await this.client.scan(cursor, "MATCH", prefix + "*", "COUNT", 200);
      cursor = next;
      if (keys.length > 0) await this.client.unlink(...keys);
    } while (cursor !== "0");
  }

  async close(): Promise<void> {
    try {
      await this.client.quit();
    } catch {
      this.client.disconnect();
    }
  }
}
