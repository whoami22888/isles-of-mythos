import { describe, expect, it } from "vitest";
import { CHUNK_SIZE, TileKind, WorldChunkCache, generateChunk } from "./world.js";

describe("world generation", () => {
  it("generates deterministic chunks", () => {
    expect(generateChunk(3, -7)).toEqual(generateChunk(3, -7));
  });

  it("returns a complete fixed-size tile buffer", () => {
    const chunk = generateChunk(0, 0);
    expect(chunk.tiles).toHaveLength(CHUNK_SIZE * CHUNK_SIZE);
    expect(chunk.size).toBe(CHUNK_SIZE);
    expect(chunk.tiles.every((tile) => Object.values(TileKind).includes(tile))).toBe(true);
  });

  it("keeps the chunk cache bounded and reuses generated chunks", () => {
    const cache = new WorldChunkCache(2);
    const first = cache.get(0, 0);
    expect(cache.get(0, 0)).toBe(first);
    cache.get(1, 0);
    cache.get(2, 0);
    expect(cache.size).toBe(2);
  });
});
