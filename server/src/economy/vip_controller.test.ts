import { describe, expect, it } from "vitest";
import {
  VIP_BUILDING_SPEED_CAP,
  VIP_GATHER_SPEED_CAP,
  VIP_MAX_TIER,
  gatherSpeedBonus,
  productionMultipliers,
  vipPerks,
} from "./vip_controller.js";

describe("VIP production caps", () => {
  it("keeps VIP 15 gather speed at or below the +10.0% hard cap reached at tier 12", () => {
    expect(gatherSpeedBonus(12)).toBe(VIP_GATHER_SPEED_CAP);
    const vip15 = productionMultipliers(15);
    expect(vip15.gatherSpeedBonus).toBeLessThanOrEqual(VIP_GATHER_SPEED_CAP);
    expect(vip15.gatherSpeedBonus).toBe(VIP_GATHER_SPEED_CAP);
    expect(vip15.buildingSpeedBonus).toBeLessThanOrEqual(VIP_BUILDING_SPEED_CAP);
    expect(vip15.buildingSpeedBonus).toBe(VIP_BUILDING_SPEED_CAP);
  });

  it("grants QoL march slots, guild help taps, and a daily VIP chest at every tier", () => {
    for (let tier = 1; tier <= VIP_MAX_TIER; tier += 1) {
      const perks = vipPerks(tier);
      expect(perks.extraMarchSlots).toBeGreaterThanOrEqual(1);
      expect(perks.extraGuildHelpTaps).toBe(tier);
      expect(perks.dailyVipChests).toBe(1);
      expect(perks.gatherSpeedBonus).toBeLessThanOrEqual(VIP_GATHER_SPEED_CAP);
      expect(perks.buildingSpeedBonus).toBeLessThanOrEqual(VIP_BUILDING_SPEED_CAP);
    }
  });
});
