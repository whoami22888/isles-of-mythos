export interface CombatReplayRecord<T> {
  fingerprint: string;
  response: T;
  expiresAt: number;
}

export type CombatReplayLookup<T> =
  | { kind: "miss" }
  | { kind: "hit"; response: T }
  | { kind: "conflict" };

export class CombatReplayCache<T> {
  private readonly entries = new Map<string, CombatReplayRecord<T>>();
  constructor(private readonly ttlMs = 30_000, private readonly maxEntries = 4096) {}

  lookup(userId: string, requestId: string, fingerprint: string, now = Date.now()): CombatReplayLookup<T> {
    this.prune(now);
    const entry = this.entries.get(this.key(userId, requestId));
    if (!entry) return { kind: "miss" };
    if (entry.fingerprint !== fingerprint) return { kind: "conflict" };
    return { kind: "hit", response: entry.response };
  }

  remember(userId: string, requestId: string, fingerprint: string, response: T, now = Date.now()): void {
    this.prune(now);
    const key = this.key(userId, requestId);
    this.entries.delete(key);
    this.entries.set(key, { fingerprint, response, expiresAt: now + this.ttlMs });
    while (this.entries.size > this.maxEntries) {
      const oldest = this.entries.keys().next().value;
      if (oldest === undefined) break;
      this.entries.delete(oldest);
    }
  }

  private key(userId: string, requestId: string): string {
    return userId + ":" + requestId;
  }

  private prune(now: number): void {
    for (const [key, entry] of this.entries) {
      if (entry.expiresAt <= now) this.entries.delete(key);
    }
  }
}
