import { describe, expect, it } from "vitest";
import { formatHotbar } from "./survival-hud.js";

describe("survival HUD hotbar", () => {
  it("renders all eight slots and marks the selected slot", () => {
    expect(formatHotbar({
      hotbar: ["cutlass", "flintlock", null, null, null, null, null, null],
      selectedHotbarSlot: 1,
      inventory: { "ammo.flintlock": 30 },
    })).toBe("HOTBAR  [1] CUTLASS | [2*] FLINTLOCK x30 | [3] — | [4] —\n         [5] — | [6] — | [7] — | [8] —");
  });

  it("uses inventory counts for stackable items and keeps empty slots empty", () => {
    expect(formatHotbar({
      hotbar: ["capture.orb", "creature.feed", null, null, null, null, null, null],
      selectedHotbarSlot: 0,
      inventory: { "capture.orb": 3, "creature.feed": 4 },
    })).toContain("[1*] ORB x3 | [2] FEED x4");
  });

  it("handles a missing slot entry without inventing inventory", () => {
    expect(formatHotbar({
      hotbar: [],
      selectedHotbarSlot: 0,
      inventory: {},
    })).toContain("[1*] —");
  });
});
