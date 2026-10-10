import { describe, expect, it } from "vitest";
import { PLAYER_MAX_HEALTH, PLAYER_MAX_HUNGER, PLAYER_MAX_OXYGEN, PLAYER_BASE_DEFENSE, STARTING_FLINTLOCK_AMMO, MOVEMENT_MAX_PACKETS_PER_SECOND, MovementAuthority, applyAuthoritativePlayerInput, applyPlayerInput, createDefaultPlayer, meleeHitbox, playerHitbox } from "./player.js";
import { TileKind, tileAtWorld } from "./world.js";

describe("player survival and movement", () => {
  it("creates a valid default player state", () => {
    const player = createDefaultPlayer("user-1");
    expect(player.health).toBe(PLAYER_MAX_HEALTH);
    expect(player.defense).toBe(PLAYER_BASE_DEFENSE);
    expect(player.hunger).toBe(PLAYER_MAX_HUNGER);
    expect(player.oxygen).toBe(PLAYER_MAX_OXYGEN);
    expect(player.inventory).toEqual({ "ammo.flintlock": STARTING_FLINTLOCK_AMMO, "capture.orb": 3, "creature.feed": 4 });
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
  it("treats coral reef tiles as water for movement", () => {
    const player = createDefaultPlayer("reef-movement");
    expect(tileAtWorld(0, 0)).toBe(TileKind.Reef);
    applyAuthoritativePlayerInput(player, { dx: 1, dy: 0, sequence: 1 }, 0.05);
    expect(player.x).toBeCloseTo(0.125, 6);
  });
  it("applies an authoritative movement speed multiplier", () => {
    const normal = createDefaultPlayer("normal");
    const slowed = createDefaultPlayer("slowed");
    applyPlayerInput(normal, { dx: 1, dy: 0, dt: 0.25 });
    applyPlayerInput(slowed, { dx: 1, dy: 0, dt: 0.25, speedMultiplier: 0.35 });
    expect(slowed.x).toBeCloseTo(normal.x * 0.35, 6);
  });
  it("ignores manipulated client time and uses the server monotonic clock", () => {
    const authority = new MovementAuthority();
    const player = createDefaultPlayer("speedhack");
    const first = authority.evaluate("speedhack", { dx: 1, dy: 0, sequence: 0 }, 1_000);
    const second = authority.evaluate("speedhack", { dx: 1, dy: 0, sequence: 1 }, 1_050);
    expect(first.accepted).toBe(false);
    expect(second.serverDt).toBeCloseTo(0.05, 6);
    applyAuthoritativePlayerInput(player, { dx: 1, dy: 0, sequence: 1 }, second.serverDt);
    expect(player.x).toBeCloseTo(0.125, 6);
  });
  it("caps delayed packets to one authoritative movement budget", () => {
    const authority = new MovementAuthority();
    authority.evaluate("laggy", { dx: 1, dy: 0, sequence: 0 }, 1_000);
    const delayed = authority.evaluate("laggy", { dx: 1, dy: 0, sequence: 1 }, 3_000);
    expect(delayed.serverDt).toBe(0.1);
  });
  it("rejects duplicated or out-of-order movement sequences", () => {
    const authority = new MovementAuthority();
    authority.evaluate("dup", { dx: 1, dy: 0, sequence: 4 }, 1_000);
    expect(authority.evaluate("dup", { dx: 1, dy: 0, sequence: 4 }, 1_050).reason).toBe("DUPLICATE_SEQUENCE");
    expect(authority.evaluate("dup", { dx: 1, dy: 0, sequence: 3 }, 1_100).reason).toBe("DUPLICATE_SEQUENCE");
  });
  it("rate-limits movement packets independently of client time", () => {
    const authority = new MovementAuthority();
    authority.evaluate("flood", { dx: 1, dy: 0, sequence: 0 }, 1_000);
    let decision = authority.evaluate("flood", { dx: 1, dy: 0, sequence: 1 }, 1_001);
    for (let sequence = 2; sequence < MOVEMENT_MAX_PACKETS_PER_SECOND; sequence += 1) {
      decision = authority.evaluate("flood", { dx: 1, dy: 0, sequence }, 1_001 + sequence);
    }
    expect(decision.accepted).toBe(true);
    expect(authority.evaluate("flood", { dx: 1, dy: 0, sequence: MOVEMENT_MAX_PACKETS_PER_SECOND }, 1_041).reason).toBe("RATE_LIMITED");
  });
  it("bounds sustained movement to server time rather than packet count", () => {
    const authority = new MovementAuthority();
    const player = createDefaultPlayer("bounded");
    authority.evaluate("bounded", { dx: 1, dy: 0, sequence: 0 }, 1_000);
    for (let sequence = 1; sequence <= 20; sequence += 1) {
      const decision = authority.evaluate("bounded", { dx: 1, dy: 0, sequence }, 1_000 + sequence * 50);
      if (decision.accepted) applyAuthoritativePlayerInput(player, { dx: 1, dy: 0, sequence }, decision.serverDt);
    }
    expect(player.x).toBeCloseTo(2.5, 6);
  });
  it("produces player and melee hitboxes", () => {
    const player = createDefaultPlayer("user-1");
    expect(playerHitbox(player)).toMatchObject({ width: 0.7, height: 0.7 });
    expect(meleeHitbox(player, 1, 0).width).toBe(1.5);
  });
});
