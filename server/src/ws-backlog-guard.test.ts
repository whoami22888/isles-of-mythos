import { describe, expect, it } from "vitest";
import {
  BACKLOG_CLOSE_CODE,
  MAX_BACKLOG_OVERFLOW_STRIKES,
  MAX_QUEUED_MESSAGES_PER_SOCKET,
  MessageBacklogGuard,
  enqueueBacklogWork,
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

  // A-09: the error reporter must never be able to leave the chain rejected.
  describe("enqueueBacklogWork", () => {
    function harness() {
      const guard = new MessageBacklogGuard(8, 8);
      let queue: Promise<void> = Promise.resolve();
      const ran: number[] = [];
      const reported: string[] = [];
      const reporterFailures: string[] = [];
      const enqueue = (
        id: number,
        handler: () => Promise<void>,
        report: (error: unknown) => void,
      ): void => {
        expect(guard.admit()).toBe("accept");
        queue = enqueueBacklogWork(
          queue,
          guard,
          async () => {
            ran.push(id);
            await handler();
          },
          report,
          (error) => { reporterFailures.push(error instanceof Error ? error.message : String(error)); },
        );
      };
      return { guard, ran, reported, reporterFailures, enqueue, tail: () => queue };
    }

    it("keeps running later handlers in order when the handler AND the reporter throw", async () => {
      const h = harness();
      const brokenReport = (): void => { throw new Error("reporter-broken"); };
      h.enqueue(1, () => Promise.reject(new Error("handler-1-failed")), brokenReport);
      h.enqueue(2, () => Promise.resolve(), brokenReport);
      h.enqueue(3, () => Promise.resolve(), brokenReport);
      expect(h.guard.depth).toBe(3);
      await h.tail().catch(() => undefined);
      expect(h.ran).toEqual([1, 2, 3]);
      expect(h.guard.depth).toBe(0);
      await expect(h.tail()).resolves.toBeUndefined();
      expect(h.reporterFailures).toEqual(["reporter-broken"]);
    });

    it("reports the original handler error once and still runs later handlers", async () => {
      const h = harness();
      const report = (error: unknown): void => { h.reported.push(error instanceof Error ? error.message : String(error)); };
      h.enqueue(1, () => Promise.reject(new Error("handler-1-failed")), report);
      h.enqueue(2, () => Promise.resolve(), report);
      h.enqueue(3, () => Promise.resolve(), report);
      await h.tail();
      expect(h.reported).toEqual(["handler-1-failed"]);
      expect(h.reporterFailures).toEqual([]);
      expect(h.ran).toEqual([1, 2, 3]);
      expect(h.guard.depth).toBe(0);
    });

    it("runs successful handlers in FIFO order, never reports, and drains depth to 0", async () => {
      const h = harness();
      const report = (error: unknown): void => { h.reported.push(String(error)); };
      h.enqueue(1, () => new Promise<void>((resolve) => setTimeout(resolve, 5)), report);
      h.enqueue(2, () => Promise.resolve(), report);
      h.enqueue(3, () => Promise.resolve(), report);
      expect(h.guard.depth).toBe(3);
      await h.tail();
      expect(h.ran).toEqual([1, 2, 3]);
      expect(h.reported).toEqual([]);
      expect(h.guard.depth).toBe(0);
    });

    it("releases exactly once per frame even when the reporter-failure logger also throws", async () => {
      const guard = new MessageBacklogGuard(2, 2);
      expect(guard.admit()).toBe("accept");
      const ran: number[] = [];
      const tail = enqueueBacklogWork(
        Promise.resolve(),
        guard,
        () => { ran.push(1); return Promise.reject(new Error("x")); },
        () => { throw new Error("reporter-broken"); },
        () => { throw new Error("logger-broken"); },
      );
      await expect(tail).resolves.toBeUndefined();
      expect(guard.depth).toBe(0);
      expect(guard.admit()).toBe("accept");
      expect(guard.depth).toBe(1);
    });
  });
});
