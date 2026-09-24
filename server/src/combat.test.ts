import { describe, expect, it } from "vitest";
import { addThreat, applyDamage, calculateDamage, createCombatTarget, distance, selectThreatTarget, tickCreatureAi, tickStatuses, weaponFor } from "./combat.js";

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
  it("tracks threat and selects the highest-threat nearby player", () => {
    const target = createCombatTarget("creature:1:1", "boar", 1, 1, 1);
    addThreat(target, "a", 5, 100);
    addThreat(target, "b", 12, 100);
    expect(selectThreatTarget(target, [{ userId: "a", x: 1, y: 1 }, { userId: "b", x: 2, y: 1 }])?.userId).toBe("b");
  });

  it("moves an engaged creature toward its threat and transitions to attack range", () => {
    const target = createCombatTarget("creature:1:1", "raptor", 0, 0, 1);
    addThreat(target, "player", 10, 100);
    const chase = tickCreatureAi(target, [{ userId: "player", x: 4, y: 0 }], 100, 250);
    expect(chase.state).toBe("chase");
    expect(chase.moveX).toBeGreaterThan(0);
    target.x = 3;
    const attack = tickCreatureAi(target, [{ userId: "player", x: 4, y: 0 }], 100, 250);
    expect(attack.state).toBe("attack");
  });

  it("handles expired status tick input safely", () => {
    const target = createCombatTarget("creature:1:1", "slime", 1, 1, 1);
    expect(tickStatuses(target, 0)).toBe(0);
    expect(tickStatuses(target, -100)).toBe(0);
  });
});
