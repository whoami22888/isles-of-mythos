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
  gold: 0,
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
});
