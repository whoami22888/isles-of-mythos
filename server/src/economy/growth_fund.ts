export const GROWTH_FUND_SKU = "island_growth_fund";
export const GROWTH_FUND_PRICE_USD = 19.99;

export const GROWTH_FUND_MILESTONES = Object.freeze({
  5: Object.freeze({ pearls: 50, wood: 1_000, steel: 0 }),
  10: Object.freeze({ pearls: 200, wood: 50_000, steel: 0 }),
  15: Object.freeze({ pearls: 500, wood: 0, steel: 10_000 }),
  20: Object.freeze({ pearls: 2_000, wood: 100_000, steel: 50_000 }),
} as const);

export type GrowthMilestone = keyof typeof GROWTH_FUND_MILESTONES;

export const MILESTONE_ALREADY_CLAIMED = "MILESTONE_ALREADY_CLAIMED";
export const GROWTH_FUND_NOT_PURCHASED = "GROWTH_FUND_NOT_PURCHASED";
export const MILESTONE_NOT_REACHED = "MILESTONE_NOT_REACHED";

export interface GrowthClaimResult {
  milestone: GrowthMilestone;
  pearls: number;
  wood: number;
  steel: number;
}

export function rewardFor(milestone: number): GrowthClaimResult | null {
  if (milestone !== 5 && milestone !== 10 && milestone !== 15 && milestone !== 20) return null;
  const reward = GROWTH_FUND_MILESTONES[milestone];
  return { milestone, ...reward };
}

export function assertCanClaim(input: {
  purchased: boolean;
  citadelLevel: number;
  alreadyClaimed: boolean;
  milestone: number;
}): GrowthClaimResult {
  const reward = rewardFor(input.milestone);
  if (!reward) {
    throw Object.assign(new Error("Unknown growth-fund milestone"), { code: "UNKNOWN_MILESTONE" });
  }
  if (!input.purchased) {
    throw Object.assign(new Error("Island Growth Fund has not been purchased"), { code: GROWTH_FUND_NOT_PURCHASED });
  }
  if (input.citadelLevel < input.milestone) {
    throw Object.assign(new Error(`Citadel Level ${input.milestone} required`), { code: MILESTONE_NOT_REACHED });
  }
  if (input.alreadyClaimed) {
    throw Object.assign(new Error("Milestone already claimed"), { code: MILESTONE_ALREADY_CLAIMED });
  }
  return reward;
}
