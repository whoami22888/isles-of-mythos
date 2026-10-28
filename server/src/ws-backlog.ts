// MYTHOS-NET-02: per-socket bound on unfinished message work.
//
// Rejected frames never enter the socket's FIFO queue, so message ordering and
// requestId replay/idempotency are unchanged. The guard is pure state so its
// invariants can be unit-tested without a database or a socket.

export const MAX_QUEUED_MESSAGES_PER_SOCKET = 64;
export const MAX_BACKLOG_OVERFLOW_STRIKES = 32;

// WebSocket close code 1013 "Try Again Later": the server is overloaded or the
// client's work is backed up. Deliberately NOT 1008 (policy violation): the
// client treats 1008 as rejected credentials and never reconnects, which would
// permanently drop a legitimate player whose requests merely queued behind a
// slow database.
export const BACKLOG_CLOSE_CODE = 1013;
export const BACKLOG_CLOSE_REASON = "message_backlog";

export type BacklogDecision = "accept" | "reject" | "close";

export class MessageBacklogGuard {
  private queued = 0;
  private strikes = 0;

  constructor(
    private readonly maxQueued: number = MAX_QUEUED_MESSAGES_PER_SOCKET,
    private readonly maxStrikes: number = MAX_BACKLOG_OVERFLOW_STRIKES,
  ) {
    if (!Number.isInteger(maxQueued) || maxQueued < 1) throw new RangeError("INVALID_MAX_QUEUED");
    if (!Number.isInteger(maxStrikes) || maxStrikes < 1) throw new RangeError("INVALID_MAX_STRIKES");
  }

  get depth(): number {
    return this.queued;
  }

  get overflowStrikes(): number {
    return this.strikes;
  }

  // "accept": the caller must enqueue the frame and later call release() exactly
  // once. "reject": answer RATE_LIMITED and drop the frame. "close": answer
  // RATE_LIMITED, drop the frame and close the socket.
  admit(): BacklogDecision {
    if (this.queued >= this.maxQueued) {
      this.strikes += 1;
      return this.strikes >= this.maxStrikes ? "close" : "reject";
    }
    this.queued += 1;
    return "accept";
  }

  // Called when an accepted frame finishes, whether it succeeded or failed.
  // Strikes reset only once the backlog has fully drained, so a peer that keeps
  // its queue full cannot dodge the close by draining a single slot.
  release(): void {
    if (this.queued > 0) this.queued -= 1;
    if (this.queued === 0) this.strikes = 0;
  }
}

// Appends one admitted frame's work to the socket's FIFO chain and returns the
// new chain tail. The tail can never be rejected: a failure of the handler goes
// to `report` (the original error, unchanged), and a failure of `report` itself
// is swallowed (best-effort `onReporterFailure`) so later queued frames still
// run. The guard slot is released exactly once per frame in every case.
export function enqueueBacklogWork(
  queue: Promise<void>,
  guard: MessageBacklogGuard,
  work: () => Promise<void>,
  report: (error: unknown) => void,
  onReporterFailure?: (error: unknown) => void,
): Promise<void> {
  return queue
    .then(work)
    .catch((error: unknown) => {
      try {
        report(error);
      } catch (reporterError) {
        try {
          onReporterFailure?.(reporterError);
        } catch {
          // Reporting the reporter failure is best-effort only.
        }
      }
    })
    .finally(() => guard.release());
}
