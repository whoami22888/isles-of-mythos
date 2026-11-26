import { describe, expect, it } from "vitest";
import {
  CITADEL_SOFT_WALL_BLOCKED,
  CITADEL_SOFT_WALL_FOOD,
  CITADEL_SOFT_WALL_STEEL,
  CITADEL_SOFT_WALL_WOOD,
  assertCitadelSoftWall,
  canClearCitadelSoftWall,
} from "./citadel_soft_wall.js";

describe("citadel soft wall", () => {
  it("rejects a level 16 attempt with 4,999,999 wood and 0 badges", () => {
    const storage = {
      wood: 4_999_999,
      steel: CITADEL_SOFT_WALL_STEEL,
      food: CITADEL_SOFT_WALL_FOOD,
    };
    expect(canClearCitadelSoftWall(storage, 0n)).toBe(false);
    expect(() => assertCitadelSoftWall(storage, 0)).toThrow(CITADEL_SOFT_WALL_BLOCKED);
  });

  it("clears the gate with the published resource totals or 500 Triumph Badges", () => {
    expect(canClearCitadelSoftWall({
      wood: CITADEL_SOFT_WALL_WOOD,
      steel: CITADEL_SOFT_WALL_STEEL,
      food: CITADEL_SOFT_WALL_FOOD,
    }, 0n)).toBe(true);
    expect(canClearCitadelSoftWall({ wood: 0, steel: 0, food: 0 }, 500n)).toBe(true);
    expect(canClearCitadelSoftWall({ wood: 0, steel: 0, food: 0 }, 499n)).toBe(false);
  });
});
