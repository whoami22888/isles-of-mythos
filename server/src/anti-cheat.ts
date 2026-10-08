export type AntiCheatSeverity = "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
export type AntiCheatEventType =
  | "MOVEMENT_RATE_LIMIT"
  | "MOVEMENT_SEQUENCE_GAP"
  | "MOVEMENT_INVALID_SEQUENCE"
  | "IMPOSSIBLE_MOVEMENT";

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

const DECAY_PER_SECOND = 1;
const MAX_EVENTS = 5000;

export class AntiCheatService {
  private readonly events: AntiCheatEvidence[] = [];
  private readonly suspicion = new Map<string, SuspicionState>();

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
    for (let index = this.events.length - 1; index >= 0; index -= 1) {
      if (this.events[index]?.userId === userId) this.events.splice(index, 1);
    }
  }
}
