import { describe, expect, it } from "vitest";
import {
  EXCITED_XP_MULTIPLIER,
  FIRE_FORGE_YIELD_MULTIPLIER,
  WATER_DOCKS_FARM_YIELD_MULTIPLIER,
  buildCompanionSnapshot,
  grantCompanionXp,
  workYieldMultiplier,
  xpMultiplierFor,
} from "./mythos-companion.js";

describe("mythos companion contract", () => {
  it("applies 1.6x fire/forge ore_smelting yield and 1.4x water food yield", () => {
    expect(workYieldMultiplier("fire", "forge", "ore_smelting")).toBe(FIRE_FORGE_YIELD_MULTIPLIER);
    expect(workYieldMultiplier("FIRE", " Forge ", " ORE_SMELTING ")).toBe(1.6);
    expect(workYieldMultiplier("water", "docks", "fishing")).toBe(WATER_DOCKS_FARM_YIELD_MULTIPLIER);
    expect(workYieldMultiplier("water", "fishing_dock", "net_operation")).toBe(1.4);
    expect(workYieldMultiplier("water", "farm", "irrigation")).toBe(1.4);
    expect(workYieldMultiplier("earth", "forge", "ore_smelting")).toBe(1);
    expect(workYieldMultiplier("fire", "steel_mill", "ore_smelting")).toBe(1);
    expect(workYieldMultiplier("water", "farm", "process")).toBe(1);
  });

  it("grants 2.0x XP and maximum work output at mood 80+ for tamed companions", () => {
    expect(xpMultiplierFor("tamed_work", 79)).toBe(1);
    expect(xpMultiplierFor("tamed_work", 80)).toBe(EXCITED_XP_MULTIPLIER);
    expect(grantCompanionXp(10, "tamed_follow", 80)).toBe(20);
    expect(grantCompanionXp(10, "wild", 100)).toBe(10);
    const snapshot = buildCompanionSnapshot({
      id: "mythos-1",
      element: "fire",
      mood: 80,
      tameProgress: 100,
      assigned: true,
      workstation: "forge",
      task: "ore_smelting",
    });
    expect(snapshot).toMatchObject({
      state: "tamed_work",
      element: "fire",
      mood: 80,
      xp_multiplier: 2,
      work_output_max: true,
      workstation: "forge",
      work_task: "ore_smelting",
      work_yield_multiplier: 1.6,
    });
  });

  it("keeps care and work state server-owned in snapshots", () => {
    expect(buildCompanionSnapshot({
      id: "mythos-2",
      element: "water",
      mood: 15,
      tameProgress: 100,
      assigned: false,
    })).toMatchObject({ state: "tamed_follow", xp_multiplier: 1, work_output_max: false, workstation: "", work_task: "", work_yield_multiplier: 1 });
    expect(buildCompanionSnapshot({
      id: "mythos-3",
      element: "earth",
      mood: 0,
      tameProgress: 40,
      assigned: false,
    }).state).toBe("wild");
    expect(buildCompanionSnapshot({
      id: "mythos-4",
      element: "air",
      mood: 90,
      tameProgress: 100,
      assigned: false,
      companionState: "resting",
    })).toMatchObject({ state: "resting", xp_multiplier: 2, work_output_max: true, work_yield_multiplier: 1 });
  });
});
