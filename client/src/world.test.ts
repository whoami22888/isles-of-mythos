import { describe, expect, it } from "vitest";
import { CHUNK_SIZE, TILE_SIZE, TileKind } from "./world.js";

describe("client world constants", () => {
  it("uses the same chunk geometry as the server contract", () => {
    expect(CHUNK_SIZE).toBe(32);
    expect(TILE_SIZE).toBe(32);
    expect(TileKind.Ocean).toBe(0);
    expect(TileKind.Grass).toBe(3);
  });
});
