import { describe, expect, it } from "vitest";
import {
  advanceProjectile,
  createCombatTarget,
  createProjectile,
  isMeleeHit,
  weaponFor,
} from "./combat.js";

describe("combat geometry and projectile lifecycle", () => {
  it("accepts a melee target at the authoritative range boundary", () => {
    const target = createCombatTarget("creature:10:0", "slime", 1.6, 0, 1);
    expect(isMeleeHit({ x: 0, y: 0 }, target, 1, 0, 1.6)).toBe(true);
  });

  it("rejects a melee target beyond range, behind the attacker, or outside the attack arc", () => {
    const beyond = createCombatTarget("creature:2:0", "slime", 2, 0, 1);
    const behind = createCombatTarget("creature:-1:0", "slime", -0.5, 0, 1);
    const side = createCombatTarget("creature:1:1", "slime", 1, 1, 1);

    expect(isMeleeHit({ x: 0, y: 0 }, beyond, 1, 0, 1.6)).toBe(false);
    expect(isMeleeHit({ x: 0, y: 0 }, behind, 1, 0, 1.6)).toBe(false);
    expect(isMeleeHit({ x: 0, y: 0 }, side, 1, 0, 1.6)).toBe(false);
  });

  it("rejects zero-length projectile direction instead of creating an invalid projectile", () => {
    const target = createCombatTarget("creature:1:0", "slime", 1, 0, 1);
    const weapon = weaponFor("flintlock");
    expect(weapon).not.toBeNull();

    expect(createProjectile("p-1", "player-1", target, { x: 0, y: 0 }, 0, 0, weapon!, 1000)).toBeNull();
  });

  it("advances a projectile and reports collision with the target hitbox", () => {
    const target = createCombatTarget("creature:2:0", "slime", 2, 0, 1);
    const weapon = weaponFor("flintlock");
    expect(weapon).not.toBeNull();

    const projectile = createProjectile(
      "p-2",
      "player-1",
      target,
      { x: 0, y: 0 },
      1,
      0,
      weapon!,
      1000,
      "attack-2",
    );
    expect(projectile).not.toBeNull();

    expect(advanceProjectile(projectile!, target, 0.1, 1100)).toBe("hit");
  });

  it("expires a projectile after its server-defined lifetime", () => {
    const target = createCombatTarget("creature:3:0", "slime", 100, 0, 1);
    const weapon = weaponFor("flintlock");
    expect(weapon).not.toBeNull();

    const projectile = createProjectile(
      "p-3",
      "player-1",
      target,
      { x: 0, y: 0 },
      1,
      0,
      weapon!,
      1000,
    );
    expect(projectile).not.toBeNull();

    expect(advanceProjectile(projectile!, target, 0.01, projectile!.expiresAt)).toBe("expired");
  });

  it("enforces creature ability cooldown state", () => {
    const target = createCombatTarget("creature:4:0", "slime", 0, 0, 1);
    const first = target.nextAbilityAt;
    const firstResult = target;
    const ai = requireAiTick(firstResult, 1, 0);
    expect(ai.ability?.id).toBe("acid_burst");

    const next = requireAiTick(firstResult, 1, 1);
    expect(next.ability).toBeUndefined();
    expect(firstResult.nextAbilityAt).toBeGreaterThan(first);
  });
});

function requireAiTick(target: ReturnType<typeof createCombatTarget>, userX: number, now: number) {
  // Importing the AI function only for this test keeps the assertions focused on
  // the state transition without duplicating the cooldown implementation.
  return tickCreatureAiForTest(target, [{ userId: "player-1", x: userX, y: 0 }], now, 250);
}

import { tickCreatureAi as tickCreatureAiForTest } from "./combat.js";
