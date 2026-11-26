export const VIP_MIN_TIER = 1;
export const VIP_MAX_TIER = 15;
export const VIP_GATHER_SPEED_CAP = 0.10;
export const VIP_GATHER_SPEED_CAP_TIER = 12;
export const VIP_BUILDING_SPEED_CAP = 0.30;

export type VipTier = 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15;

export interface VipPerks {
  tier: VipTier;
  gatherSpeedBonus: number;
  buildingSpeedBonus: number;
  extraMarchSlots: number;
  extraGuildHelpTaps: number;
  dailyVipChests: number;
}

export function assertVipTier(tier: number): VipTier {
  if (!Number.isInteger(tier) || tier < VIP_MIN_TIER || tier > VIP_MAX_TIER) {
    throw new Error("INVALID_VIP_TIER");
  }
  return tier as VipTier;
}

/** Linear gather ramp that hard-caps at +10.0% from tier 12 upward. */
export function gatherSpeedBonus(tier: number): number {
  const level = assertVipTier(tier);
  const raw = (Math.min(level, VIP_GATHER_SPEED_CAP_TIER) / VIP_GATHER_SPEED_CAP_TIER) * VIP_GATHER_SPEED_CAP;
  return Math.min(VIP_GATHER_SPEED_CAP, Number(raw.toFixed(4)));
}

/** Building speed ramps to a hard cap of +30.0% at tier 15. */
export function buildingSpeedBonus(tier: number): number {
  const level = assertVipTier(tier);
  const raw = (level / VIP_MAX_TIER) * VIP_BUILDING_SPEED_CAP;
  return Math.min(VIP_BUILDING_SPEED_CAP, Number(raw.toFixed(4)));
}

export function vipPerks(tier: number): VipPerks {
  const level = assertVipTier(tier);
  return {
    tier: level,
    gatherSpeedBonus: gatherSpeedBonus(level),
    buildingSpeedBonus: buildingSpeedBonus(level),
    extraMarchSlots: 1 + Math.floor((level - 1) / 3),
    extraGuildHelpTaps: level,
    dailyVipChests: 1,
  };
}

export function productionMultipliers(tier: number): { gatherSpeedBonus: number; buildingSpeedBonus: number } {
  return { gatherSpeedBonus: gatherSpeedBonus(tier), buildingSpeedBonus: buildingSpeedBonus(tier) };
}
