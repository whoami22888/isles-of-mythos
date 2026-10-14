import { describe, expect, it } from "vitest";
import { createMutationTiming, measureMutationStage, runTimedMutation } from "./mutation-timing.js";

describe("mutation timing", () => {
  it("records successful stage duration and total duration", async () => {
    const timing = createMutationTiming();
    const ticks = [100, 140, 155];
    const snapshot = await runTimedMutation(
      timing,
      () => measureMutationStage(timing, "transactionMs", () => Promise.resolve("ok"), () => ticks.shift() ?? 155),
      (value) => value,
      () => ticks.shift() ?? 155,
    );

    expect(snapshot).toBe("ok");
    expect(timing.startedAt).toBe(100);
    expect(timing.stages.transactionMs).toBe(15);
  });

  it("records failed stage duration and settles diagnostics before rethrowing", async () => {
    const timing = createMutationTiming();
    const ticks = [200, 260, 275];
    let settled: { totalMs: number; stages: Record<string, number> } | undefined;
    await expect(runTimedMutation(
      timing,
      () => measureMutationStage(timing, "reloadEconomyMs", () => Promise.reject(new Error("DATABASE_FAILURE")), () => ticks.shift() ?? 275),
      (snapshot) => { settled = snapshot; },
      () => ticks.shift() ?? 275,
    )).rejects.toThrow("DATABASE_FAILURE");

    expect(settled).toEqual({ totalMs: 75, stages: { reloadEconomyMs: 15 } });
  });

  it("reports a slow rejected mutation at the 50 ms threshold", async () => {
    const timing = createMutationTiming();
    const ticks = [0, 50];
    let emitted = false;
    await expect(runTimedMutation(
      timing,
      () => Promise.reject(new Error("MUTATION_REJECTED")),
      (snapshot) => { emitted = snapshot.totalMs >= 50; },
      () => ticks.shift() ?? 50,
    )).rejects.toThrow("MUTATION_REJECTED");

    expect(emitted).toBe(true);
  });
});
