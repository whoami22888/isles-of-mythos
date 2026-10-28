import { describe, expect, it } from "vitest";
import {
  BACKLOG_CLOSE_CODE,
  MAX_BACKLOG_OVERFLOW_STRIKES,
  MAX_QUEUED_MESSAGES_PER_SOCKET,
  MessageBacklogGuard,
  reportMessageFailure,
} from "./ws-backlog.js";

// MYTHOS-NET-02: invariants of the per-socket backlog guard. These need no
// database or socket, so every state transition is deterministic.

describe("MessageBacklogGuard", () => {
  it("accepts up to the cap, then rejects without growing the queue", () => {
    const guard = new MessageBacklogGuard(4, 3);
    for (let i = 0; i < 4; i += 1) expect(guard.admit()).toBe("accept");
    expect(guard.depth).toBe(4);
    expect(guard.admit()).toBe("reject");
    expect(guard.admit()).toBe("reject");
    expect(guard.depth).toBe(4);
    expect(guard.overflowStrikes).toBe(2);
  });

  it("asks to close exactly when the strike limit is reached", () => {
    const guard = new MessageBacklogGuard(1, 3);
    expect(guard.admit()).toBe("accept");
    expect(guard.admit()).toBe("reject");
    expect(guard.admit()).toBe("reject");
    expect(guard.admit()).toBe("close");
    expect(guard.depth).toBe(1);
  });

  it("resets strikes only after the backlog fully drains", () => {
    const guard = new MessageBacklogGuard(2, 5);
    guard.admit();
    guard.admit();
    guard.admit();
    guard.admit();
    expect(guard.overflowStrikes).toBe(2);
    // One slot frees but the queue is not empty: strikes must persist, so a
    // peer cannot dodge the close by draining a single frame.
    guard.release();
    expect(guard.depth).toBe(1);
    expect(guard.overflowStrikes).toBe(2);
    guard.release();
    expect(guard.depth).toBe(0);
    expect(guard.overflowStrikes).toBe(0);
  });

  it("admits again after a drain, so a recovered client keeps working", () => {
    const guard = new MessageBacklogGuard(2, 5);
    guard.admit();
    guard.admit();
    expect(guard.admit()).toBe("reject");
    guard.release();
    guard.release();
    expect(guard.admit()).toBe("accept");
    expect(guard.depth).toBe(1);
  });

  it("never lets depth go negative on an unmatched release", () => {
    const guard = new MessageBacklogGuard(2, 2);
    guard.release();
    guard.release();
    expect(guard.depth).toBe(0);
    expect(guard.admit()).toBe("accept");
    expect(guard.depth).toBe(1);
  });

  it("releases once per frame through a failing handler chain (finally path)", async () => {
    // Mirrors the app wiring: queue = queue.then(handler).catch(report); queue = queue.finally(release).
    const guard = new MessageBacklogGuard(3, 3);
    let queue: Promise<void> = Promise.resolve();
    const reported: string[] = [];
    const run = (handler: () => Promise<void>): void => {
      expect(guard.admit()).toBe("accept");
      queue = queue.then(handler).catch((error: unknown) => {
        reported.push(error instanceof Error ? error.message : String(error));
      });
      queue = queue.finally(() => guard.release());
    };
    run(() => Promise.reject(new Error("handler-1-failed")));
    run(() => Promise.resolve());
    run(() => Promise.reject(new Error("handler-3-failed")));
    expect(guard.depth).toBe(3);
    await queue;
    expect(reported).toEqual(["handler-1-failed", "handler-3-failed"]);
    expect(guard.depth).toBe(0);
    expect(guard.overflowStrikes).toBe(0);
  });

  it("uses the documented production limits and a retryable close code", () => {
    expect(MAX_QUEUED_MESSAGES_PER_SOCKET).toBe(64);
    expect(MAX_BACKLOG_OVERFLOW_STRIKES).toBe(32);
    // 1008 would be treated by the Godot client as rejected credentials.
    expect(BACKLOG_CLOSE_CODE).toBe(1013);
  });

  it("rejects invalid configuration", () => {
    expect(() => new MessageBacklogGuard(0, 1)).toThrow("INVALID_MAX_QUEUED");
    expect(() => new MessageBacklogGuard(1.5, 1)).toThrow("INVALID_MAX_QUEUED");
    expect(() => new MessageBacklogGuard(1, 0)).toThrow("INVALID_MAX_STRIKES");
  });
});

describe("reportMessageFailure", () => {
  it("never throws and still notifies when the logger throws", () => {
    let notified = false;
    expect(() => reportMessageFailure(new Error("x"), () => { throw new Error("log down"); }, () => { notified = true; })).not.toThrow();
    expect(notified).toBe(true);
  });

  it("never throws and still logs when the send throws", () => {
    let logged = false;
    expect(() => reportMessageFailure(new Error("x"), () => { logged = true; }, () => { throw new Error("socket gone"); })).not.toThrow();
    expect(logged).toBe(true);
  });

  it("keeps a FIFO chain alive when handler, logger and send all throw", async () => {
    const guard = new MessageBacklogGuard(4, 3);
    let chain = Promise.resolve();
    const ran: number[] = [];
    const enqueue = (n: number, fail: boolean) => {
      expect(guard.admit()).toBe("accept");
      chain = chain.then(() => { if (fail) throw new Error("handler"); ran.push(n); })
        .catch((e) => reportMessageFailure(e, () => { throw new Error("log"); }, () => { throw new Error("send"); }));
      chain = chain.finally(() => guard.release());
    };
    enqueue(1, true);
    enqueue(2, false);
    await chain;
    expect(ran).toEqual([2]);
    expect(guard.depth).toBe(0);
  });
});
