import { describe, expect, it, vi } from "vitest";
import type { WorldChunk } from "./world.js";
import { createWorldResourceVisibilityBatcher } from "./world-resource-visibility.js";

function chunk(x: number, ids: string[]): WorldChunk {
  return {
    x, y: 0, size: 32, tiles: [], creatures: [], resourceMillSpawns: [],
    resources: ids.map((id) => ({ id, type: "wood", x, y: 0 })),
  };
}

describe("world-resource visibility batching", () => {
  it("queries once for concurrent chunks and keeps visible resource order", async () => {
    const query = vi.fn((ids: string[]) => Promise.resolve(new Set(ids.filter((id) => id === "wood:2:0"))));
    const filter = createWorldResourceVisibilityBatcher(query);
    const first = chunk(1, ["wood:1:0", "wood:2:0"]);
    const second = chunk(2, ["wood:2:0", "wood:3:0"]);
    const [a, b] = await Promise.all([filter(first), filter(second)]);
    expect(query).toHaveBeenCalledTimes(1);
    expect(query.mock.calls[0][0]).toEqual(["wood:1:0", "wood:2:0", "wood:3:0"]);
    expect(a.resources.map((item) => item.id)).toEqual(["wood:1:0"]);
    expect(b.resources.map((item) => item.id)).toEqual(["wood:3:0"]);
    expect(first.resources).toHaveLength(2);
    expect(second.resources).toHaveLength(2);
  });

  it("skips database access for empty resources and preserves unchanged chunks", async () => {
    const query = vi.fn((ids: string[]) => Promise.resolve(new Set(ids.filter(() => false))));
    const filter = createWorldResourceVisibilityBatcher(query);
    const empty = chunk(0, []);
    const full = chunk(1, ["wood:1:0"]);
    expect(await filter(empty)).toBe(empty);
    expect(await filter(full)).toBe(full);
    expect(query).toHaveBeenCalledTimes(1);
  });

  it("does not cache mutable depletion state across batches", async () => {
    let depleted = new Set<string>(["wood:1:0"]);
    const query = vi.fn((ids: string[]) => Promise.resolve(new Set(ids.filter((id) => depleted.has(id)))));
    const filter = createWorldResourceVisibilityBatcher(query);
    const current = chunk(1, ["wood:1:0"]);
    expect((await filter(current)).resources).toHaveLength(0);
    depleted = new Set<string>();
    expect((await filter(current)).resources).toHaveLength(1);
    expect(query).toHaveBeenCalledTimes(2);
  });

  it("rejects the entire failed query batch and allows the next batch to recover", async () => {
    const query = vi.fn()
      .mockRejectedValueOnce(new Error("DB_DOWN"))
      .mockResolvedValueOnce(new Set<string>());
    const filter = createWorldResourceVisibilityBatcher(query);
    const failures = await Promise.allSettled([filter(chunk(1, ["wood:1:0"])), filter(chunk(2, ["wood:2:0"]))]);
    expect(failures.map((failure) => failure.status)).toEqual(["rejected", "rejected"]);
    expect(query).toHaveBeenCalledTimes(1);
    expect((await filter(chunk(3, ["wood:3:0"]))).resources).toHaveLength(1);
    expect(query).toHaveBeenCalledTimes(2);
  });

  it("bounds each query to at most 32 concurrent chunk requests", async () => {
    const query = vi.fn((ids: string[]) => Promise.resolve(new Set(ids.filter(() => false))));
    const filter = createWorldResourceVisibilityBatcher(query);
    const chunks = Array.from({ length: 65 }, (_, index) => chunk(index, [`wood:${index}:0`]));
    const results = await Promise.all(chunks.map(filter));
    expect(results).toEqual(chunks);
    expect(query.mock.calls.map(([ids]) => ids.length)).toEqual([32, 32, 1]);
  });

  it("accepts requests arriving while an earlier query is still in flight", async () => {
    let releaseFirst: ((ids: ReadonlySet<string>) => void) | undefined;
    const query = vi.fn()
      .mockImplementationOnce(() => new Promise<ReadonlySet<string>>((resolve) => { releaseFirst = resolve; }))
      .mockResolvedValueOnce(new Set<string>(["wood:2:0"]));
    const filter = createWorldResourceVisibilityBatcher(query);
    const first = filter(chunk(1, ["wood:1:0"]));
    await new Promise<void>((resolve) => setImmediate(resolve));
    const second = filter(chunk(2, ["wood:2:0"]));
    expect((await second).resources).toHaveLength(0);
    releaseFirst?.(new Set<string>());
    expect((await first).resources).toHaveLength(1);
    expect(query).toHaveBeenCalledTimes(2);
  });
});
