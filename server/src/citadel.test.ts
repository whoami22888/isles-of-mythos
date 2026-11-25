import { describe, expect, it } from "vitest";
import { MAX_BUILDING_LEVEL, BASE_BUILDING_DEFINITIONS } from "./base.js";
import {
  CITADEL_MAX_LEVEL,
  CITADEL_MIN_LEVEL,
  CITADEL_SECOND_QUEUE_UNLOCK_LEVEL,
  CITADEL_SOFT_WALL_BADGES,
  CITADEL_SOFT_WALL_FOOD,
  CITADEL_SOFT_WALL_STEEL,
  CITADEL_SOFT_WALL_TARGET_LEVEL,
  CITADEL_SOFT_WALL_WOOD,
  canAffordCitadelBadges,
  canAffordCitadelResources,
  citadelUpgradeCostMatrix,
  getCitadelUpgradeCost,
  getCitadelUpgradeDurationSeconds,
  resolveCitadelPayment,
} from "./citadel.js";

describe("citadel cost contract", () => {
  it("keeps ordinary buildings on the existing level-7 cap", () => {
    expect(MAX_BUILDING_LEVEL).toBe(7);
    expect(BASE_BUILDING_DEFINITIONS.command_centre.maxLevel).toBe(7);
    expect(CITADEL_MAX_LEVEL).toBe(20);
    expect(CITADEL_MIN_LEVEL).toBe(1);
  });

  it("supplies a complete 2–20 matrix including the frozen 15→16 soft wall", () => {
    const matrix = citadelUpgradeCostMatrix();
    expect(Object.keys(matrix)).toEqual(
      Array.from({ length: CITADEL_MAX_LEVEL - 1 }, (_, i) => String(i + 2)),
    );
    for (let level = 2; level <= CITADEL_MAX_LEVEL; level += 1) {
      const cost = matrix[String(level)];
      expect(cost.wood).toBeGreaterThanOrEqual(0);
      expect(cost.steel).toBeGreaterThanOrEqual(0);
      expect(cost.food).toBeGreaterThanOrEqual(0);
      expect(cost.badge_alternative).toBeGreaterThanOrEqual(0);
      expect(cost.wood + cost.steel + cost.food + cost.badge_alternative).toBeGreaterThan(0);
      expect(getCitadelUpgradeDurationSeconds(level)).toBeGreaterThan(0);
    }
    expect(getCitadelUpgradeCost(CITADEL_SOFT_WALL_TARGET_LEVEL)).toEqual({
      wood: CITADEL_SOFT_WALL_WOOD,
      steel: CITADEL_SOFT_WALL_STEEL,
      food: CITADEL_SOFT_WALL_FOOD,
      badge_alternative: CITADEL_SOFT_WALL_BADGES,
    });
  });

  it("rejects a soft-wall upgrade when neither resources nor badges are sufficient", () => {
    const cost = getCitadelUpgradeCost(CITADEL_SOFT_WALL_TARGET_LEVEL);
    expect(canAffordCitadelResources({ wood: 1, steel: 1, food: 1 }, cost)).toBe(false);
    expect(canAffordCitadelBadges(499n, cost)).toBe(false);
    expect(() => resolveCitadelPayment(CITADEL_SOFT_WALL_TARGET_LEVEL, { wood: 1, steel: 1, food: 1 }, 0n))
      .toThrow("CITADEL_SOFT_WALL_BLOCKED");
  });

  it("allows the soft wall to be paid with resources or 500 Triumph Badges", () => {
    const storage = {
      wood: CITADEL_SOFT_WALL_WOOD,
      steel: CITADEL_SOFT_WALL_STEEL,
      food: CITADEL_SOFT_WALL_FOOD,
    };
    expect(resolveCitadelPayment(CITADEL_SOFT_WALL_TARGET_LEVEL, storage, 0n)).toBe("resources");
    expect(resolveCitadelPayment(CITADEL_SOFT_WALL_TARGET_LEVEL, {}, 500n)).toBe("badges");
    expect(resolveCitadelPayment(CITADEL_SOFT_WALL_TARGET_LEVEL, {}, 500n, "badges")).toBe("badges");
    expect(() => resolveCitadelPayment(CITADEL_SOFT_WALL_TARGET_LEVEL, {}, 499n, "badges"))
      .toThrow("CITADEL_SOFT_WALL_BLOCKED");
  });

  it("prefers resources and rejects a badge path when no alternative exists", () => {
    const cost = getCitadelUpgradeCost(2);
    expect(cost.badge_alternative).toBe(0);
    expect(resolveCitadelPayment(2, { wood: 200, steel: 80, food: 40 }, 0n)).toBe("resources");
    expect(() => resolveCitadelPayment(2, { wood: 200, steel: 80, food: 40 }, 0n, "badges"))
      .toThrow("INVALID_CITADEL_PAYMENT");
    expect(() => resolveCitadelPayment(2, { wood: 0, steel: 0, food: 0 }, 0n))
      .toThrow("INSUFFICIENT_CITADEL_RESOURCES");
  });

  it("unlocks the second building queue at citadel level 10", () => {
    expect(CITADEL_SECOND_QUEUE_UNLOCK_LEVEL).toBe(10);
  });
});
