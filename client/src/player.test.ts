import { describe, expect, it } from "vitest";
import { isPlayerState } from "./player.js";

describe("client player contract", () => {
  it("accepts an authoritative player state", () => {
    expect(isPlayerState({ userId: "u1", x: 0, y: 0, health: 100, hunger: 100, oxygen: 100, xp: 0, level: 1, gold: 0, inventory: {}, hotbar: ["cutlass"], selectedHotbarSlot: 0 })).toBe(true);
  });
  it("rejects malformed player state", () => {
    expect(isPlayerState({ userId: "u1", x: "0" })).toBe(false);
  });
});
