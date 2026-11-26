import { afterAll, describe, expect, it } from "vitest";
import { Worker } from "node:worker_threads";
import { createSpatialWorker, measureEventLoopDelayMs, tickSpatial } from "./spatial_worker.js";

const entities = Array.from({ length: 1000 }, (_, index) => ({
  id: `e${index}`,
  x: (index % 80) * 10,
  y: Math.floor(index / 80) * 10,
}));

describe("spatial worker thread", () => {
  let worker: Worker;

  afterAll(async () => {
    if (worker) await worker.terminate();
  });

  it("hashes 1000 entities on a 32x32 grid at 20 Hz without pinning the main thread above 5ms", async () => {
    worker = createSpatialWorker();
    const delayMs = await measureEventLoopDelayMs(async () => {
      for (let i = 0; i < 20; i += 1) {
        const result = await tickSpatial(worker, entities, i + 1);
        expect(result.entityCount).toBe(1000);
      }
    });
    expect(delayMs).toBeLessThan(5);
  });
});
