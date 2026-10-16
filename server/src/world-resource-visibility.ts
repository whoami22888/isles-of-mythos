import type { WorldChunk } from "./world.js";

interface PendingChunk {
  chunk: WorldChunk;
  resolve: (chunk: WorldChunk) => void;
  reject: (error: unknown) => void;
}

const MAX_BATCH_SIZE = 32;

/**
 * Coalesce concurrent chunk depletion reads into bounded database queries.
 * Never cache depleted state: each flush observes the database again, so
 * gathering and respawn changes are visible on subsequent requests.
 */
export function createWorldResourceVisibilityBatcher(
  queryDepletedIds: (resourceIds: string[]) => Promise<ReadonlySet<string>>,
): (chunk: WorldChunk) => Promise<WorldChunk> {
  const pending: PendingChunk[] = [];
  let scheduled = false;

  async function flush(batch: PendingChunk[]): Promise<void> {
    const resourceIds = [...new Set(batch.flatMap(({ chunk }) => chunk.resources.map((resource) => resource.id)))];
    try {
      const depleted = await queryDepletedIds(resourceIds);
      for (const request of batch) {
        const resources = request.chunk.resources.filter((resource) => !depleted.has(resource.id));
        request.resolve(resources.length === request.chunk.resources.length
          ? request.chunk : { ...request.chunk, resources });
      }
    } catch (error) {
      for (const request of batch) request.reject(error);
    }
  }

  function schedule(): void {
    if (scheduled) return;
    scheduled = true;
    setImmediate(() => {
      scheduled = false;
      const batch = pending.splice(0, MAX_BATCH_SIZE);
      if (pending.length > 0) schedule();
      void flush(batch);
    });
  }

  return (chunk) => {
    if (chunk.resources.length === 0) return Promise.resolve(chunk);
    return new Promise<WorldChunk>((resolve, reject) => {
      pending.push({ chunk, resolve, reject });
      schedule();
    });
  };
}
