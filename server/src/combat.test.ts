import { describe, expect, it } from "vitest";
import { addThreat, advanceProjectile, applyDamage, calculateDamage, createCombatTarget, createProjectile, creatureAbilityDamage, distance, isMeleeHit, selectThreatTarget, tickCreatureAi, tickStatuses, weaponFor } from "./combat.js";

describe("combat engine", () => {
  it("uses server-defined weapon damage and defense", () => {
    const weapon = weaponFor("cutlass");
    expect(weapon?.delivery).toBe("melee");
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

  it("uses directional melee hitboxes rather than distance alone", () => {
    const attacker = { x: 0, y: 0 };
    const target = createCombatTarget("creature:1:0", "slime", 1, 0, 1);
    expect(isMeleeHit(attacker, target, 1, 0, 1.6)).toBe(true);
    target.x = 0;
    target.y = 1;
    expect(isMeleeHit(attacker, target, 1, 0, 1.6)).toBe(false);
  });

  it("creates and advances authoritative projectiles", () => {
    const weapon = weaponFor("flintlock");
    const target = createCombatTarget("creature:5:0", "slime", 5, 0, 1);
    const projectile = createProjectile("projectile:user:attack-1", "user", target, { x: 0, y: 0 }, 1, 0, weapon!, 1000, "target|1|0|0");
    expect(projectile?.weapon.id).toBe("flintlock");
    expect(projectile?.replayFingerprint).toBe("target|1|0|0");
    expect(advanceProjectile(projectile!, target, 0.25, 1250)).toBe("flying");
    expect(advanceProjectile(projectile!, target, 0.05, 1300)).toBe("hit");
  });

  it("expires projectiles without applying damage", () => {
    const weapon = weaponFor("bow");
    const target = createCombatTarget("creature:20:0", "slime", 20, 0, 1);
    const projectile = createProjectile("projectile:user:attack-2", "user", target, { x: 0, y: 0 }, 1, 0, weapon!, 1000, "target|2|1|0");
    expect(advanceProjectile(projectile!, target, 0.05, projectile!.expiresAt)).toBe("expired");
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

  it("defines a bounded authoritative basic-attack cadence for creatures", () => {
    const target = createCombatTarget("creature:1:1", "slime", 1, 1, 1);
    expect(target.attackCooldownMs).toBeGreaterThanOrEqual(1000);
    expect(target.nextAttackAt).toBe(0);
  });

  it("applies creature ability damage without allowing critical-hit variance", () => {
    const target = createCombatTarget("player:1", "slime", 1, 1, 1);
    const before = target.health;
    const ability = {
      id: "test_burst",
      cooldownMs: 1000,
      range: 3,
      damage: 10,
      damageType: "water" as const,
    };
    const result = creatureAbilityDamage(target, ability);
    expect(result.critical).toBe(false);
    expect(result.amount).toBe(8);
    expect(target.health).toBe(before - 8);
  });

  it("keeps dead creatures from re-entering AI combat", () => {
    const target = createCombatTarget("creature:1:1", "boar", 1, 1, 1);
    target.health = 0;
    const result = tickCreatureAi(target, [{ userId: "player", x: 1, y: 1 }], 100, 250);
    expect(result.state).toBe("dead");
    expect(result.targetUserId).toBeNull();
  });

  it("handles expired status tick input safely", () => {
    const target = createCombatTarget("creature:1:1", "slime", 1, 1, 1);
    expect(tickStatuses(target, 0)).toBe(0);
    expect(tickStatuses(target, -100)).toBe(0);
  });
});
