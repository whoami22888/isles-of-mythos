import type { Pool } from "pg";
import { log } from "./logger.js";

export type EvidenceValue = number | string | boolean;

export interface PersistedAntiCheatEvidence {
  userId: string;
  type: string;
  severity: "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
  suspicion: number;
  suppressedCount: number;
  evidence: Record<string, EvidenceValue>;
  occurredAtMs: number;
}

export interface AntiCheatEvidenceSink {
  enqueue(evidence: PersistedAntiCheatEvidence): void;
  flush(): Promise<void>;
  close(): Promise<void>;
}

const MAX_EVIDENCE_KEYS = 16;
// Serialized evidence must stay under the table's 4096-byte CHECK even after JSON escaping.
const MAX_EVIDENCE_JSON_LENGTH = 3_000;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_EVIDENCE_STRING = 128;
const MAX_KEY_LENGTH = 48;
// Evidence is reviewed by operators; it must never carry credentials, tokens or identifiers that tie a
// diagnostic row to a request, socket or inventory object.
const FORBIDDEN_KEY = /token|password|secret|authorization|cookie|jwt|requestid|socketid|itemid|inventoryid|email/i;

export function sanitizeEvidence(input: Record<string, EvidenceValue>): Record<string, EvidenceValue> {
  const output: Record<string, EvidenceValue> = {};
  let kept = 0;
  for (const [rawKey, value] of Object.entries(input)) {
    if (kept >= MAX_EVIDENCE_KEYS) break;
    const key = rawKey.slice(0, MAX_KEY_LENGTH);
    if (FORBIDDEN_KEY.test(key)) continue;
    if (typeof value === "number") {
      if (!Number.isFinite(value)) continue;
      output[key] = value;
    } else if (typeof value === "boolean") {
      output[key] = value;
    } else if (typeof value === "string") {
      output[key] = value.length > MAX_EVIDENCE_STRING ? value.slice(0, MAX_EVIDENCE_STRING) : value;
    } else {
      continue;
    }
    if (JSON.stringify(output).length > MAX_EVIDENCE_JSON_LENGTH) {
      delete output[key];
      break;
    }
    kept += 1;
  }
  return output;
}

export interface PostgresEvidenceSinkOptions {
  /** Maximum queued rows held in memory; the oldest queued rows are dropped (and counted) beyond this. */
  maxQueue?: number;
  batchSize?: number;
  flushIntervalMs?: number;
  /** Retention in days; rows older than this are removed by the retention routine. */
  retentionDays?: number;
  retentionIntervalMs?: number;
  now?: () => number;
}

const RETENTION_DELETE_BATCH = 5_000;

// SQLSTATE class 22 (data exception) and 23 (integrity constraint violation) are deterministic for a given row.
function isDataError(error: unknown): boolean {
  const code = typeof error === "object" && error !== null ? (error as { code?: unknown }).code : undefined;
  return typeof code === "string" && (code.startsWith("22") || code.startsWith("23"));
}

export class PostgresAntiCheatEvidenceSink implements AntiCheatEvidenceSink {
  private queue: PersistedAntiCheatEvidence[] = [];
  private dropped = 0;
  private rejected = 0;
  private flushing: Promise<void> | null = null;
  private flushTimer: NodeJS.Timeout | null = null;
  private retentionTimer: NodeJS.Timeout | null = null;
  private closed = false;
  private readonly maxQueue: number;
  private readonly batchSize: number;
  private readonly retentionDays: number;

  constructor(private readonly db: Pool, options: PostgresEvidenceSinkOptions = {}) {
    this.maxQueue = options.maxQueue ?? 1_000;
    this.batchSize = options.batchSize ?? 100;
    this.retentionDays = options.retentionDays ?? 30;
    const flushIntervalMs = options.flushIntervalMs ?? 1_000;
    this.flushTimer = setInterval(() => void this.flush().catch(() => undefined), flushIntervalMs);
    this.flushTimer.unref();
    const retentionIntervalMs = options.retentionIntervalMs ?? 6 * 60 * 60 * 1_000;
    this.retentionTimer = setInterval(() => void this.purgeExpired().catch(() => undefined), retentionIntervalMs);
    this.retentionTimer.unref();
  }

  enqueue(evidence: PersistedAntiCheatEvidence): void {
    if (this.closed) return;
    // A row the table can never accept must not enter the queue: it would otherwise be retried forever.
    if (!UUID_PATTERN.test(evidence.userId) || !Number.isFinite(evidence.suspicion) || !Number.isFinite(evidence.occurredAtMs)) {
      this.rejected += 1;
      return;
    }
    this.queue.push(evidence);
    if (this.queue.length > this.maxQueue) {
      const overflow = this.queue.length - this.maxQueue;
      this.queue.splice(0, overflow);
      this.dropped += overflow;
    }
    if (this.queue.length >= this.batchSize) void this.flush().catch(() => undefined);
  }

  droppedCount(): number {
    return this.dropped;
  }

  /** Rows refused up front because they could never be stored (invalid user id / non-finite numbers). */
  rejectedCount(): number {
    return this.rejected;
  }

  queuedCount(): number {
    return this.queue.length;
  }

  flush(): Promise<void> {
    if (this.flushing) return this.flushing;
    this.flushing = this.drain().finally(() => {
      this.flushing = null;
    });
    return this.flushing;
  }

  private async drain(): Promise<void> {
    while (this.queue.length > 0) {
      const batch = this.queue.splice(0, this.batchSize);
      try {
        await this.insert(batch);
      } catch (error) {
        if (isDataError(error)) {
          // Data/integrity violations are deterministic: retrying the same rows can never succeed. Isolate the
          // offending rows, keep the good ones, and drop (and count) only what the table rejects.
          await this.insertIndividually(batch);
          continue;
        }
        // Re-queue at the front (still bounded) so a transient outage does not lose evidence.
        this.queue.unshift(...batch);
        if (this.queue.length > this.maxQueue) {
          const overflow = this.queue.length - this.maxQueue;
          this.queue.splice(this.maxQueue, overflow);
          this.dropped += overflow;
        }
        log("anti_cheat_evidence_flush_failed", {
          message: error instanceof Error ? error.message : String(error),
          queued: this.queue.length,
          dropped: this.dropped,
        });
        throw error;
      }
    }
  }

  private async insertIndividually(batch: PersistedAntiCheatEvidence[]): Promise<void> {
    for (const row of batch) {
      try {
        await this.insert([row]);
      } catch (error) {
        if (!isDataError(error)) {
          this.queue.unshift(row);
          throw error;
        }
        this.rejected += 1;
        log("anti_cheat_evidence_row_rejected", {
          type: row.type,
          code: (error as { code?: string }).code ?? "unknown",
        });
      }
    }
  }

  private async insert(batch: PersistedAntiCheatEvidence[]): Promise<void> {
    const values: unknown[] = [];
    const rows = batch.map((row, index) => {
      const base = index * 7;
      values.push(
        row.userId,
        row.type,
        row.severity,
        Math.min(100, Math.max(0, Number(row.suspicion.toFixed(2)))),
        Math.max(0, Math.floor(row.suppressedCount)),
        JSON.stringify(sanitizeEvidence(row.evidence)),
        new Date(row.occurredAtMs).toISOString(),
      );
      return "($" + (base + 1) + ",$" + (base + 2) + ",$" + (base + 3) + ",$" + (base + 4) + ",$" + (base + 5) +
        ",$" + (base + 6) + "::jsonb,$" + (base + 7) + ")";
    });
    await this.db.query(
      "INSERT INTO anti_cheat_evidence (user_id,event_type,severity,suspicion,suppressed_count,evidence,occurred_at) VALUES " +
        rows.join(","),
      values,
    );
  }

  /** Removes evidence past retention in bounded batches; returns the number of rows removed. */
  async purgeExpired(nowMs: number = Date.now()): Promise<number> {
    const cutoff = new Date(nowMs - this.retentionDays * 24 * 60 * 60 * 1_000).toISOString();
    let total = 0;
    for (;;) {
      const client = await this.db.connect();
      let removed: number;
      try {
        await client.query("BEGIN");
        await client.query("SET LOCAL isles.anti_cheat_retention = 'on'");
        const result = await client.query(
          "DELETE FROM anti_cheat_evidence WHERE id IN (SELECT id FROM anti_cheat_evidence WHERE occurred_at < $1 ORDER BY id LIMIT $2)",
          [cutoff, RETENTION_DELETE_BATCH],
        );
        await client.query("COMMIT");
        removed = result.rowCount ?? 0;
      } catch (error) {
        try {
          await client.query("ROLLBACK");
        } catch {
          // The connection is discarded below if rollback fails.
        }
        throw error;
      } finally {
        client.release();
      }
      total += removed;
      if (removed < RETENTION_DELETE_BATCH) return total;
    }
  }

  async close(): Promise<void> {
    if (this.flushTimer) clearInterval(this.flushTimer);
    if (this.retentionTimer) clearInterval(this.retentionTimer);
    this.flushTimer = null;
    this.retentionTimer = null;
    try {
      await this.flush();
    } catch {
      // Already logged by drain(); shutdown must still complete.
    }
    this.closed = true;
  }
}

export interface StoredAntiCheatEvidence {
  userId: string;
  type: string;
  severity: string;
  suspicion: number;
  suppressedCount: number;
  evidence: Record<string, EvidenceValue>;
  occurredAt: string;
}

/** Read access for operators/admin tooling. Returns at most `limit` (1..500) newest rows. */
interface EvidenceRow {
  user_id: string;
  event_type: string;
  severity: string;
  suspicion: string;
  suppressed_count: number;
  evidence: Record<string, EvidenceValue>;
  occurred_at: Date;
}

export async function listStoredEvidence(db: Pool, userId?: string, limit = 100): Promise<StoredAntiCheatEvidence[]> {
  const bounded = Math.max(1, Math.min(500, Math.floor(limit)));
  const result = userId
    ? await db.query<EvidenceRow>(
        "SELECT user_id,event_type,severity,suspicion,suppressed_count,evidence,occurred_at FROM anti_cheat_evidence WHERE user_id=$1 ORDER BY occurred_at DESC,id DESC LIMIT $2",
        [userId, bounded],
      )
    : await db.query<EvidenceRow>(
        "SELECT user_id,event_type,severity,suspicion,suppressed_count,evidence,occurred_at FROM anti_cheat_evidence ORDER BY occurred_at DESC,id DESC LIMIT $1",
        [bounded],
      );
  return result.rows.map((row) => ({
    userId: String(row.user_id),
    type: String(row.event_type),
    severity: String(row.severity),
    suspicion: Number(row.suspicion),
    suppressedCount: Number(row.suppressed_count),
    evidence: row.evidence,
    occurredAt: new Date(row.occurred_at).toISOString(),
  }));
}
