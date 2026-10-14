import { describe, expect, it } from "vitest";
import { CombatReplayCache } from "./combat-replay.js";
import { createMutationTiming, runTimedMutation } from "./mutation-timing.js";
import { runReplayableRequest } from "./request-coordinator.js";

describe("replayable mutation coordinator", () => {
  it("times only the single execution for coalesced and replayed requests", async () => {
    const replay = new CombatReplayCache<string>();
    const pending = new Map<string, Promise<string>>();
    let release: (() => void) | undefined;
    let executions = 0;
    let diagnostics = 0;
    const operation = async () => {
      executions += 1;
      await new Promise<void>((resolve) => { release = resolve; });
      const timing = createMutationTiming();
      return runTimedMutation(timing, () => Promise.resolve("response"), () => { diagnostics += 1; });
    };

    const first = runReplayableRequest(replay, pending, "user", "request", "craft|recipe", operation, "conflict");
    const coalesced = runReplayableRequest(replay, pending, "user", "request", "craft|recipe", operation, "conflict");
    await Promise.resolve();
    expect(executions).toBe(1);
    release?.();
    await expect(first).resolves.toBe("response");
    await expect(coalesced).resolves.toBe("response");

    await expect(runReplayableRequest(replay, pending, "user", "request", "craft|recipe", operation, "conflict")).resolves.toBe("response");
    expect(executions).toBe(1);
    expect(diagnostics).toBe(1);
  });

  it("returns a conflict without executing or timing a duplicate request", async () => {
    const replay = new CombatReplayCache<string>();
    const pending = new Map<string, Promise<string>>();
    replay.remember("user", "request", "craft|old", "response");
    let executions = 0;

    await expect(runReplayableRequest(
      replay,
      pending,
      "user",
      "request",
      "craft|new",
      () => { executions += 1; return Promise.resolve("unexpected"); },
      "conflict",
    )).resolves.toBe("conflict");
    expect(executions).toBe(0);
  });

  it("reports replay, conflict, and coalesced outcomes without changing responses", async () => {
    const replay = new CombatReplayCache<string>();
    const pending = new Map<string, Promise<string>>();
    const outcomes: string[] = [];
    replay.remember("user", "replay", "same", "cached");
    await expect(runReplayableRequest(
      replay, pending, "user", "replay", "same", () => "unexpected", "conflict",
      (outcome) => outcomes.push(outcome),
    )).resolves.toBe("cached");
    await expect(runReplayableRequest(
      replay, pending, "user", "replay", "different", () => "unexpected", "conflict",
      (outcome) => outcomes.push(outcome),
    )).resolves.toBe("conflict");
    let release: (() => void) | undefined;
    const first = runReplayableRequest(
      replay, pending, "user", "coalesce", "same", async () => {
        await new Promise<void>((resolve) => { release = resolve; });
        return "done";
      }, "conflict", (outcome) => outcomes.push(outcome),
    );
    const second = runReplayableRequest(
      replay, pending, "user", "coalesce", "same", () => "unexpected", "conflict",
      (outcome) => outcomes.push(outcome),
    );
    await Promise.resolve();
    release?.();
    await expect(first).resolves.toBe("done");
    await expect(second).resolves.toBe("done");
    expect(outcomes).toEqual(["REPLAYED", "CONFLICT", "COALESCED"]);
  });
});
