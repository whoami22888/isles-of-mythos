import { describe, expect, it } from "vitest";
import { isPlayerState } from "./player.js";

const validPlayerState = {
  userId: "u1",
  x: 0,
  y: 0,
  health: 100,
  stamina: 100,
  maxStamina: 100,
  hunger: 100,
  oxygen: 100,
  xp: 0,
  level: 1,
  gold: "0",
  triumphBadges: "0",
  inventory: {},
  hotbar: ["cutlass", null, null, null, null, null, null, null],
  selectedHotbarSlot: 0,
};

describe("client player contract", () => {
  it("accepts an authoritative player state", () => {
    expect(isPlayerState(validPlayerState)).toBe(true);
  });

  it("rejects malformed player state", () => {
    expect(isPlayerState({ ...validPlayerState, stamina: "100" })).toBe(false);
    expect(isPlayerState({ ...validPlayerState, maxStamina: 50, stamina: 51 })).toBe(false);
    expect(isPlayerState({ ...validPlayerState, hotbar: ["cutlass"] })).toBe(false);
    expect(isPlayerState({ ...validPlayerState, inventory: { wood: -1 } })).toBe(false);
    expect(isPlayerState({ ...validPlayerState, selectedHotbarSlot: 8 })).toBe(false);
  });

  it("accepts exact decimal Gold Doubloons and rejects overflow", () => {
    const state = {
      userId: "user-1",
      x: 0, y: 0, health: 100, stamina: 100, maxStamina: 100,
      hunger: 100, oxygen: 100, xp: 0, level: 1,
      gold: "500000000",
      triumphBadges: "123",
      inventory: {},
      hotbar: ["cutlass", null, null, null, null, null, null, null],
      selectedHotbarSlot: 0,
    };
    expect(isPlayerState(state)).toBe(true);
    expect(isPlayerState({ ...state, gold: "9223372036854775807" })).toBe(true);
    expect(isPlayerState({ ...state, gold: "9223372036854775808" })).toBe(false);
    expect(isPlayerState({ ...state, gold: 500000000 })).toBe(false);
    expect(isPlayerState({ ...state, triumphBadges: "9223372036854775808" })).toBe(false);
    expect(isPlayerState({ ...state, triumphBadges: 1 })).toBe(false);
  });
});
