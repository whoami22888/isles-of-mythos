import { monitorEventLoopDelay } from "node:perf_hooks";
import { fileURLToPath } from "node:url";
import { Worker } from "node:worker_threads";

export const SPATIAL_GRID_SIZE = 32;
export const SPATIAL_TICK_HZ = 20;

export interface SpatialEntity {
  id: string;
  x: number;
  y: number;
}

export function createSpatialWorker(): Worker {
  const filename = fileURLToPath(new URL("./spatial_worker_thread.mjs", import.meta.url));
  return new Worker(filename);
}

export function tickSpatial(worker: Worker, entities: readonly SpatialEntity[], requestId = 1): Promise<{
  buckets: Record<string, string[]>;
  entityCount: number;
  workerMs: number;
}> {
  return new Promise((resolve, reject) => {
    const onMessage = (message: { type?: string; requestId?: number; buckets: Record<string, string[]>; entityCount: number; workerMs: number; }) => {
      if (message?.type !== "tick-result" || message.requestId !== requestId) return;
      worker.off("message", onMessage);
      worker.off("error", onError);
      resolve(message);
    };
    const onError = (error: Error) => {
      worker.off("message", onMessage);
      worker.off("error", onError);
      reject(error);
    };
    worker.on("message", onMessage);
    worker.on("error", onError);
    worker.postMessage({ type: "tick", requestId, entities });
  });
}

export async function measureEventLoopDelayMs(run: () => Promise<void>): Promise<number> {
  const histogram = monitorEventLoopDelay({ resolution: 1 });
  histogram.enable();
  await run();
  histogram.disable();
  return histogram.mean / 1e6;
}
