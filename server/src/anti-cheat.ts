export type AntiCheatSeverity = "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
export type AntiCheatEventType =
  | "MOVEMENT_RATE_LIMIT"
  | "MOVEMENT_SEQUENCE_GAP"
  | "MOVEMENT_INVALID_SEQUENCE"
  | "IMPOSSIBLE_MOVEMENT"
  | "ATTACK_COOLDOWN_SPAM"
  | "RESOURCE_RANGE_ABUSE"
  | "INVENTORY_MUTATION_REJECTED";

export interface AntiCheatEvidence {
  userId: string;
  type: AntiCheatEventType;
  severity: AntiCheatSeverity;
  timestampMs: number;
  evidence: Record<string, number | string | boolean>;
  suspicion: number;
}

interface SuspicionState {
  score: number;
  lastUpdatedMs: number;
}

interface RejectedActionWindow {
  timestampsMs: number[];
  lastEmittedMs: number;
}

const REJECTED_ACTION_RULES = {
  ATTACK_COOLDOWN_SPAM: { threshold: 8, windowMs: 5_000, severity: "HIGH" as const },
  RESOURCE_RANGE_ABUSE: { threshold: 5, windowMs: 10_000, severity: "MEDIUM" as const },
  INVENTORY_MUTATION_REJECTED: { threshold: 5, windowMs: 10_000, severity: "MEDIUM" as const },
} as const;

const DECAY_PER_SECOND = 1;
const MAX_EVENTS = 5000;
const MAX_REJECTED_ACTION_WINDOWS = 10_000;

export class AntiCheatService {
  private readonly events: AntiCheatEvidence[] = [];
  private readonly suspicion = new Map<string, SuspicionState>();
  private readonly rejectedActions = new Map<string, RejectedActionWindow>();

  record(
    userId: string,
    type: AntiCheatEventType,
    severity: AntiCheatSeverity,
    evidence: Record<string, number | string | boolean>,
    nowMs = Date.now(),
  ): AntiCheatEvidence {
    const state = this.suspicion.get(userId);
    const previous = state ? Math.max(0, state.score - ((nowMs - state.lastUpdatedMs) / 1000) * DECAY_PER_SECOND) : 0;
    const increment = severity === "CRITICAL" ? 10 : severity === "HIGH" ? 5 : severity === "MEDIUM" ? 2 : 1;
    const next: SuspicionState = { score: Math.min(100, previous + increment), lastUpdatedMs: nowMs };
    this.suspicion.set(userId, next);

    const event: AntiCheatEvidence = { userId, type, severity, timestampMs: nowMs, evidence, suspicion: next.score };
    this.events.push(event);
    if (this.events.length > MAX_EVENTS) this.events.splice(0, this.events.length - MAX_EVENTS);
    return event;
  }

  observeMovement(
    userId: string,
    decision: { accepted: boolean; reason?: string; sequenceGap: number; serverDt: number },
    nowMs = Date.now(),
  ): AntiCheatEvidence | null {
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

  observePosition(
    userId: string,
    before: { x: number; y: number },
    after: { x: number; y: number },
    serverDt: number,
    nowMs = Date.now(),
  ): AntiCheatEvidence | null {
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

  observeRejectedAction(
    userId: string,
    type: "ATTACK_COOLDOWN_SPAM" | "RESOURCE_RANGE_ABUSE" | "INVENTORY_MUTATION_REJECTED",
    evidence: Record<string, number | string | boolean>,
    nowMs = Date.now(),
  ): AntiCheatEvidence | null {
    const rule = REJECTED_ACTION_RULES[type];
    const key = userId + ":" + type;
    const previous = this.rejectedActions.get(key);
    const timestampsMs = (previous?.timestampsMs ?? []).filter(
      (timestampMs) => nowMs >= timestampMs && nowMs - timestampMs <= rule.windowMs,
    );
    timestampsMs.push(nowMs);
    if (timestampsMs.length > rule.threshold) timestampsMs.splice(0, timestampsMs.length - rule.threshold);
    const lastEmittedMs = previous?.lastEmittedMs ?? Number.NEGATIVE_INFINITY;
    this.rejectedActions.delete(key);
    this.rejectedActions.set(key, { timestampsMs, lastEmittedMs });
    while (this.rejectedActions.size > MAX_REJECTED_ACTION_WINDOWS) {
      const oldestKey = this.rejectedActions.keys().next().value;
      if (oldestKey === undefined) break;
      this.rejectedActions.delete(oldestKey);
    }

    if (timestampsMs.length < rule.threshold || nowMs - lastEmittedMs < rule.windowMs) return null;

    const event = this.record(userId, type, rule.severity, {
      ...evidence,
      rejectedCount: timestampsMs.length,
      windowMs: rule.windowMs,
    }, nowMs);
    this.rejectedActions.delete(key);
    this.rejectedActions.set(key, { timestampsMs, lastEmittedMs: nowMs });
    return event;
  }

  listRecent(userId?: string, limit = 100): AntiCheatEvidence[] {
    const boundedLimit = Math.max(1, Math.min(1000, Math.floor(limit)));
    const filtered = userId ? this.events.filter((event) => event.userId === userId) : this.events;
    return filtered.slice(-boundedLimit);
  }

  suspicionScore(userId: string, nowMs = Date.now()): number {
    const state = this.suspicion.get(userId);
    if (!state) return 0;
    return Math.max(0, state.score - ((nowMs - state.lastUpdatedMs) / 1000) * DECAY_PER_SECOND);
  }

  reset(userId: string): void {
    this.suspicion.delete(userId);
    for (const key of this.rejectedActions.keys()) {
      if (key.startsWith(userId + ":")) this.rejectedActions.delete(key);
    }
    for (let index = this.events.length - 1; index >= 0; index -= 1) {
      if (this.events[index]?.userId === userId) this.events.splice(index, 1);
    }
  }
}
