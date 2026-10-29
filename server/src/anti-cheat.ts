import {
  MemoryAntiCheatStateStore,
  sanitizeKeyPart,
  userKeyPrefix,
  type AntiCheatStateStore,
} from "./anti-cheat-store.js";
import type { AntiCheatEvidenceSink } from "./anti-cheat-evidence-store.js";
import { log } from "./logger.js";

export type AntiCheatSeverity = "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
export type AntiCheatEventType =
  | "MOVEMENT_RATE_LIMIT"
  | "MOVEMENT_SEQUENCE_GAP"
  | "MOVEMENT_INVALID_SEQUENCE"
  | "IMPOSSIBLE_MOVEMENT"
  | "ATTACK_COOLDOWN_SPAM"
  | "RESOURCE_RANGE_ABUSE"
  | "INVENTORY_MUTATION_REJECTED"
  | "REQUEST_DUPLICATION"
  | "MULTI_SOCKET_ABUSE";

export interface AntiCheatEvidence {
  userId: string;
  type: AntiCheatEventType;
  severity: AntiCheatSeverity;
  timestampMs: number;
  evidence: Record<string, number | string | boolean>;
  suspicion: number;
}

const REJECTED_ACTION_RULES = {
  ATTACK_COOLDOWN_SPAM: { threshold: 8, windowMs: 5_000, severity: "HIGH" as const },
  RESOURCE_RANGE_ABUSE: { threshold: 5, windowMs: 10_000, severity: "MEDIUM" as const },
  INVENTORY_MUTATION_REJECTED: { threshold: 5, windowMs: 10_000, severity: "MEDIUM" as const },
  REQUEST_DUPLICATION: { threshold: 5, windowMs: 10_000, severity: "MEDIUM" as const },
} as const;

const DECAY_PER_SECOND = 1;
const MAX_SUSPICION = 100;
const MAX_EVENTS = 5000;
const MULTI_SOCKET_THRESHOLD = 4;
export const SOCKET_LEASE_TTL_MS = 90_000;
const MULTI_SOCKET_WINDOW_MS = 10_000;
// Persisted evidence is throttled per user and event type so sustained hostile traffic cannot flood storage.
// Suppressed occurrences are counted and attached to the next persisted row rather than discarded silently.
const PERSIST_COOLDOWN_MS = 5_000;
const PERSIST_COOLDOWN_CRITICAL_MS = 1_000;
// After a primary-store failure, skip it briefly so a dead Redis does not add a timeout to every observation.
const PRIMARY_RETRY_AFTER_MS = 5_000;
const DEGRADED_LOG_INTERVAL_MS = 30_000;

export interface AntiCheatServiceOptions {
  /** Shared detection state (Redis in production). Defaults to a process-local store. */
  store?: AntiCheatStateStore;
  /** Durable evidence destination (PostgreSQL in production). Optional. */
  sink?: AntiCheatEvidenceSink;
  /** Called when the primary store fails and detection degrades to process-local state. */
  onDegraded?: (reason: string) => void;
}

export class AntiCheatService {
  private readonly events: AntiCheatEvidence[] = [];
  private readonly primary: AntiCheatStateStore;
  private readonly fallback = new MemoryAntiCheatStateStore();
  private readonly sink: AntiCheatEvidenceSink | undefined;
  private readonly onDegraded: ((reason: string) => void) | undefined;
  private primaryRetryAtMs = 0;
  private lastDegradedLogMs = Number.NEGATIVE_INFINITY;
  private degradedCount = 0;
  // Handlers start observations without awaiting them; shutdown must wait for them or their evidence is lost.
  private readonly inflight = new Set<Promise<unknown>>();
  // Socket leases held by this process; refreshed on a timer so they outlive the TTL only while we are alive.
  private readonly leases = new Map<string, Set<string>>();
  private heartbeat: NodeJS.Timeout | null = null;
  private readonly socketOperations = new Map<string, Promise<void>>();

  constructor(options: AntiCheatServiceOptions = {}) {
    this.primary = options.store ?? new MemoryAntiCheatStateStore();
    this.sink = options.sink;
    this.onDegraded = options.onDegraded;
    for (const name of ["record", "observeMovement", "observePosition", "observeRejectedAction", "observeRequestDuplicate", "observeMultiSocket", "connectSocket", "disconnectSocket"] as const) {
      const original = this[name].bind(this) as (...args: unknown[]) => Promise<unknown>;
      (this as unknown as Record<typeof name, typeof original>)[name] = (...args) => this.track(original(...args));
    }
  }

  private track<T>(operation: Promise<T>): Promise<T> {
    this.inflight.add(operation);
    const release = (): void => {
      this.inflight.delete(operation);
    };
    operation.then(release, release);
    return operation;
  }

  /** Waits for every observation started so far (each store call is individually time-bounded). */
  private async drainInflight(): Promise<void> {
    while (this.inflight.size > 0) await Promise.allSettled([...this.inflight]);
  }

  /** Number of observations served from process-local fallback state because the primary store failed. */
  degradedObservations(): number {
    return this.degradedCount;
  }

  private async withStore<T>(operation: (store: AntiCheatStateStore) => Promise<T>): Promise<T> {
    const wallMs = Date.now();
    if (this.primary.kind === "memory" || wallMs < this.primaryRetryAtMs) {
      if (this.primary.kind !== "memory") this.degradedCount += 1;
      return operation(this.primary.kind === "memory" ? this.primary : this.fallback);
    }
    try {
      return await operation(this.primary);
    } catch (error) {
      this.primaryRetryAtMs = wallMs + PRIMARY_RETRY_AFTER_MS;
      this.degradedCount += 1;
      const reason = error instanceof Error ? error.message : String(error);
      if (wallMs - this.lastDegradedLogMs >= DEGRADED_LOG_INTERVAL_MS) {
        this.lastDegradedLogMs = wallMs;
        log("anti_cheat_store_degraded", { store: this.primary.kind, message: reason });
      }
      try {
        this.onDegraded?.(reason);
      } catch {
        // Diagnostics must never alter detection behaviour.
      }
      return operation(this.fallback);
    }
  }

  async record(
    userId: string,
    type: AntiCheatEventType,
    severity: AntiCheatSeverity,
    evidence: Record<string, number | string | boolean>,
    nowMs: number | undefined = undefined,
  ): Promise<AntiCheatEvidence> {
    const timestampMs = nowMs ?? Date.now();
    const increment = severity === "CRITICAL" ? 10 : severity === "HIGH" ? 5 : severity === "MEDIUM" ? 2 : 1;
    const suspicion = await this.withStore((store) =>
      store.addSuspicion({
        userId,
        nowMs,
        increment,
        decayPerSecond: DECAY_PER_SECOND,
        max: MAX_SUSPICION,
      }),
    );

    const event: AntiCheatEvidence = { userId, type, severity, timestampMs, evidence, suspicion };
    this.events.push(event);
    if (this.events.length > MAX_EVENTS) this.events.splice(0, this.events.length - MAX_EVENTS);
    await this.persist(event, nowMs);
    return event;
  }

  private async persist(event: AntiCheatEvidence, nowMs: number | undefined): Promise<void> {
    if (!this.sink) return;
    try {
      const cooldown = await this.withStore((store) =>
        store.acquireCooldown({
          key: userKeyPrefix(event.userId) + "persist:" + event.type,
          nowMs,
          cooldownMs: event.severity === "CRITICAL" ? PERSIST_COOLDOWN_CRITICAL_MS : PERSIST_COOLDOWN_MS,
        }),
      );
      if (!cooldown.emit) return;
      this.sink.enqueue({
        userId: event.userId,
        type: event.type,
        severity: event.severity,
        suspicion: event.suspicion,
        suppressedCount: cooldown.suppressed,
        evidence: event.evidence,
        occurredAtMs: event.timestampMs,
      });
    } catch (error) {
      log("anti_cheat_persist_failed", { message: error instanceof Error ? error.message : String(error) });
    }
  }

  async observeMovement(
    userId: string,
    decision: { accepted: boolean; reason?: string; sequenceGap: number; serverDt: number },
    nowMs?: number,
  ): Promise<AntiCheatEvidence | null> {
    if (decision.reason === "RATE_LIMITED") {
      return this.record(userId, "MOVEMENT_RATE_LIMIT", "HIGH", {
        serverDt: decision.serverDt,
        sequenceGap: decision.sequenceGap,
      }, nowMs);
    }
    if (decision.reason === "INVALID_SEQUENCE") {
      return this.record(userId, "MOVEMENT_INVALID_SEQUENCE", "MEDIUM", {
        serverDt: decision.serverDt,
        sequenceGap: decision.sequenceGap,
      }, nowMs);
    }
    if (decision.sequenceGap > 0) {
      return this.record(userId, "MOVEMENT_SEQUENCE_GAP", "LOW", {
        sequenceGap: decision.sequenceGap,
        serverDt: decision.serverDt,
      }, nowMs);
    }
    return null;
  }

  async observePosition(
    userId: string,
    before: { x: number; y: number },
    after: { x: number; y: number },
    serverDt: number,
    nowMs?: number,
  ): Promise<AntiCheatEvidence | null> {
    const coordinates = [before.x, before.y, after.x, after.y, serverDt];
    if (coordinates.some((value) => !Number.isFinite(value))) {
      return this.record(userId, "IMPOSSIBLE_MOVEMENT", "CRITICAL", {
        reason: "NON_FINITE_POSITION",
        beforeX: String(before.x),
        beforeY: String(before.y),
        afterX: String(after.x),
        afterY: String(after.y),
      }, nowMs);
    }
    const distance = Math.hypot(after.x - before.x, after.y - before.y);
    const maxDistance = Math.max(0, serverDt) * 4 + 0.001;
    if (distance <= maxDistance) return null;
    return this.record(userId, "IMPOSSIBLE_MOVEMENT", "HIGH", {
      distance,
      maxDistance,
      serverDt,
      beforeX: before.x,
      beforeY: before.y,
      afterX: after.x,
      afterY: after.y,
    }, nowMs);
  }

  async observeRejectedAction(
    userId: string,
    type: "ATTACK_COOLDOWN_SPAM" | "RESOURCE_RANGE_ABUSE" | "INVENTORY_MUTATION_REJECTED" | "REQUEST_DUPLICATION",
    evidence: Record<string, number | string | boolean>,
    nowMs?: number,
  ): Promise<AntiCheatEvidence | null> {
    const rule = REJECTED_ACTION_RULES[type];
    const action = typeof evidence.action === "string" ? evidence.action : "";
    const reason = typeof evidence.reason === "string" ? evidence.reason : "";
    const key = userKeyPrefix(userId) + [type, sanitizeKeyPart(action), sanitizeKeyPart(reason)].join(":");
    const window = await this.withStore((store) =>
      store.observeWindow({ key, nowMs, windowMs: rule.windowMs, threshold: rule.threshold, cooldownMs: rule.windowMs }),
    );
    if (!window.emit) return null;
    return this.record(userId, type, rule.severity, {
      ...evidence,
      rejectedCount: window.count,
      windowMs: rule.windowMs,
    }, nowMs);
  }

  async observeRequestDuplicate(
    userId: string,
    outcome: "REPLAYED" | "CONFLICT" | "COALESCED",
    nowMs?: number,
  ): Promise<AntiCheatEvidence | null> {
    return this.observeRejectedAction(userId, "REQUEST_DUPLICATION", {
      action: "request_duplicate",
      reason: outcome,
    }, nowMs);
  }

  /**
   * `connectionCount` is the caller's local view; the emission cooldown is shared so that several backend
   * instances observing the same abusive account do not each emit.
   */
  async observeMultiSocket(userId: string, connectionCount: number, nowMs?: number): Promise<AntiCheatEvidence | null> {
    if (!Number.isSafeInteger(connectionCount) || connectionCount < MULTI_SOCKET_THRESHOLD) return null;
    const cooldown = await this.withStore((store) =>
      store.acquireCooldown({
        key: userKeyPrefix(userId) + "multisocket",
        nowMs,
        cooldownMs: MULTI_SOCKET_WINDOW_MS,
      }),
    );
    if (!cooldown.emit) return null;
    return this.record(userId, "MULTI_SOCKET_ABUSE", "MEDIUM", {
      connectionCount,
      threshold: MULTI_SOCKET_THRESHOLD,
      windowMs: MULTI_SOCKET_WINDOW_MS,
    }, nowMs);
  }

  /**
   * Registers an authenticated socket and evaluates the user's session count across all backend instances.
   * The lease is refreshed while this process lives and expires on its own if the process dies.
   */
  async connectSocket(userId: string, socketId: string, nowMs?: number): Promise<AntiCheatEvidence | null> {
    const held = this.leases.get(userId) ?? new Set<string>();
    held.add(socketId);
    this.leases.set(userId, held);
    this.startHeartbeat();
    const count = await this.leaseIfHeld(userId, socketId, nowMs);
    if (count === null) return null;
    // The store's count can under-report after an outage (sockets leased before the failure are missing from the
    // fallback). Live sockets this process holds are a lower bound on the account's total, so use the larger.
    return this.observeMultiSocket(userId, Math.max(count, held.size), nowMs);
  }

  async disconnectSocket(userId: string, socketId: string): Promise<void> {
    const held = this.leases.get(userId);
    held?.delete(socketId);
    if (held && held.size === 0) this.leases.delete(userId);
    // Queued behind any lease write for this socket, so a registration still waiting on the network cannot
    // land after the release and leave a stale shared lease that other instances would count until the TTL.
    await this.serializeSocket(userId, socketId, async () => {
      await this.withStore((store) => store.releaseSocket(userId, socketId));
      if (this.primary.kind !== "memory") await this.fallback.releaseSocket(userId, socketId);
    });
  }

  /** Leases a socket only while this process still holds it; returns null when it was already disconnected. */
  private leaseIfHeld(userId: string, socketId: string, nowMs?: number): Promise<number | null> {
    return this.serializeSocket(userId, socketId, async () => {
      if (!this.leases.get(userId)?.has(socketId)) return null;
      return this.withStore((store) => store.leaseSocket({ userId, socketId, ttlMs: SOCKET_LEASE_TTL_MS, nowMs }));
    });
  }

  /** Runs lease operations for one socket strictly in call order. */
  private serializeSocket<T>(userId: string, socketId: string, operation: () => Promise<T>): Promise<T> {
    const key = userId + "\u0000" + socketId;
    const previous = this.socketOperations.get(key) ?? Promise.resolve();
    const next = previous.then(operation, operation);
    const tail = next.then(() => undefined, () => undefined);
    this.socketOperations.set(key, tail);
    void tail.then(() => {
      if (this.socketOperations.get(key) === tail) this.socketOperations.delete(key);
    });
    return next;
  }

  private startHeartbeat(): void {
    if (this.heartbeat) return;
    this.heartbeat = setInterval(() => {
      for (const [userId, sockets] of this.leases) {
        for (const socketId of sockets) {
          // Best effort: a failed refresh only lets the lease lapse, which under-counts, never over-counts.
          void this.track(this.leaseIfHeld(userId, socketId)).catch(() => undefined);
        }
      }
    }, SOCKET_LEASE_TTL_MS / 3);
    this.heartbeat.unref();
  }

  /** Process-local, bounded diagnostic view. Durable history is read from the evidence table. */
  listRecent(userId?: string, limit = 100): AntiCheatEvidence[] {
    const boundedLimit = Math.max(1, Math.min(1000, Math.floor(limit)));
    const filtered = userId ? this.events.filter((event) => event.userId === userId) : this.events;
    return filtered.slice(-boundedLimit);
  }

  async suspicionScore(userId: string, nowMs?: number): Promise<number> {
    return this.withStore((store) => store.getSuspicion(userId, DECAY_PER_SECOND, nowMs));
  }

  async reset(userId: string): Promise<void> {
    await this.withStore((store) => store.clearUser(userId));
    if (this.primary.kind !== "memory") await this.fallback.clearUser(userId);
    for (let index = this.events.length - 1; index >= 0; index -= 1) {
      if (this.events[index]?.userId === userId) this.events.splice(index, 1);
    }
  }

  async flush(): Promise<void> {
    await this.drainInflight();
    await this.sink?.flush();
  }

  async close(): Promise<void> {
    if (this.heartbeat) clearInterval(this.heartbeat);
    this.heartbeat = null;
    await this.drainInflight();
    // Release our leases so peers stop counting these sockets immediately instead of waiting for the TTL.
    for (const [userId, sockets] of this.leases) {
      for (const socketId of sockets) await this.withStore((store) => store.releaseSocket(userId, socketId)).catch(() => undefined);
    }
    this.leases.clear();
    await this.sink?.close();
    await this.primary.close();
    await this.fallback.close();
  }
}
