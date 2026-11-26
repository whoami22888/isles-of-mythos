import { parentPort } from "node:worker_threads";

const GRID = 32;
const TICK_HZ = 20;

function hashEntities(entities) {
  const buckets = new Map();
  for (const entity of entities) {
    const key = `${Math.floor(entity.x / GRID)},${Math.floor(entity.y / GRID)}`;
    let list = buckets.get(key);
    if (!list) {
      list = [];
      buckets.set(key, list);
    }
    list.push(entity.id);
  }
  return Object.fromEntries(buckets);
}

parentPort?.on("message", (message) => {
  if (message?.type === "tick") {
    const started = performance.now();
    const buckets = hashEntities(message.entities ?? []);
    parentPort.postMessage({
      type: "tick-result",
      requestId: message.requestId,
      buckets,
      entityCount: (message.entities ?? []).length,
      workerMs: performance.now() - started,
      tickHz: TICK_HZ,
    });
  }
});
