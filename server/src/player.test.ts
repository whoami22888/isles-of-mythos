import { describe, expect, it } from "vitest";
import { PLAYER_MAX_HEALTH, PLAYER_MAX_HUNGER, PLAYER_MAX_OXYGEN, applyPlayerInput, createDefaultPlayer, meleeHitbox, playerHitbox } from "./player.js";

describe("player survival and movement", () => {
  it("creates a valid default player state", () => {
    const player = createDefaultPlayer("user-1");
    expect(player.health).toBe(PLAYER_MAX_HEALTH);
    expect(player.hunger).toBe(PLAYER_MAX_HUNGER);
    expect(player.oxygen).toBe(PLAYER_MAX_OXYGEN);
    expect(player.inventory).toEqual({});
    expect(player.hotbar[0]).toBe("cutlass");
  });
  it("normalizes diagonal movement and consumes hunger", () => {
    const player = createDefaultPlayer("user-1");
    applyPlayerInput(player, { dx: 1, dy: 1, dt: 0.25 });
    expect(player.x).toBeGreaterThan(0);
    expect(player.y).toBeGreaterThan(0);
    expect(player.x).toBeCloseTo(player.y, 6);
    expect(player.hunger).toBeLessThan(PLAYER_MAX_HUNGER);
  });
  it("applies an authoritative movement speed multiplier", () => {
    const normal = createDefaultPlayer("normal");
    const slowed = createDefaultPlayer("slowed");
    applyPlayerInput(normal, { dx: 1, dy: 0, dt: 0.25 });
    applyPlayerInput(slowed, { dx: 1, dy: 0, dt: 0.25, speedMultiplier: 0.35 });
    expect(slowed.x).toBeCloseTo(normal.x * 0.35, 6);
  });
  it("produces player and melee hitboxes", () => {
    const player = createDefaultPlayer("user-1");
    expect(playerHitbox(player)).toMatchObject({ width: 0.7, height: 0.7 });
    expect(meleeHitbox(player, 1, 0).width).toBe(1.5);
  });
});
