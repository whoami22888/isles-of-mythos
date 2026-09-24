import { describe, expect, it } from "vitest";
import { applyDamage, calculateDamage, createCombatTarget, distance, tickStatuses, weaponFor } from "./combat.js";

describe("combat engine", () => {
  it("uses server-defined weapon damage and defense", () => {
    const weapon = weaponFor("cutlass");
    expect(weapon).not.toBeNull();
    const result = calculateDamage(weapon!, { defense: 5, element: "physical" }, 0.99);
    expect(result.amount).toBe(15);
    expect(result.critical).toBe(false);
  });

  it("applies elemental multipliers and critical hits", () => {
    const weapon = weaponFor("fire_spell");
    const result = calculateDamage(weapon!, { defense: 0, element: "ice" }, 0);
    expect(result.amount).toBe(70);
    expect(result.critical).toBe(true);
  });

  it("applies and ticks damage-over-time status effects", () => {
    const target = createCombatTarget("creature:1:1", "slime", 1, 1, 1);
    const weapon = weaponFor("fire_spell");
    applyDamage(target, weapon!, 0.99);
    expect(target.statuses.some((status) => status.id === "burn")).toBe(true);
    const healthBefore = target.health;
    tickStatuses(target, 1000);
    expect(target.health).toBeLessThan(healthBefore);
  });

  it("computes spatial distance for authoritative range checks", () => {
    expect(distance({ x: 0, y: 0 }, { x: 3, y: 4 })).toBe(5);
  });
});
