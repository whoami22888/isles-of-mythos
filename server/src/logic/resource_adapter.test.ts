import { describe, expect, it } from "vitest";
import { MAX_WOOD_SPAWN_BONUS, woodSpawnBonus } from "./resource_adapter.js";

describe("dynamic resource adapter", () => {
  it("boosts wood node spawns by up to 35% when steel is 90% and wood is 2%", () => {
    const bonus = woodSpawnBonus({ wood: 2, steel: 90, other: 8 });
    expect(bonus).toBeGreaterThan(0);
    expect(bonus).toBeLessThanOrEqual(MAX_WOOD_SPAWN_BONUS);
    expect(bonus).toBeCloseTo(MAX_WOOD_SPAWN_BONUS * ((0.05 - 0.02) / 0.05));
  });

  it("does not boost a balanced inventory", () => {
    expect(woodSpawnBonus({ wood: 40, steel: 40, other: 20 })).toBe(0);
  });
});
