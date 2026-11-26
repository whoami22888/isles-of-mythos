import { describe, expect, it } from "vitest";
import { MILESTONE_ALREADY_CLAIMED, assertCanClaim, rewardFor } from "./growth_fund.js";

describe("Island Growth Fund", () => {
  it("pays the published Level 10 reward once and rejects a second claim", () => {
    const first = assertCanClaim({ purchased: true, citadelLevel: 10, alreadyClaimed: false, milestone: 10 });
    expect(first).toEqual(rewardFor(10));
    expect(first).toEqual({ milestone: 10, pearls: 200, wood: 50_000, steel: 0 });
    try {
      assertCanClaim({ purchased: true, citadelLevel: 10, alreadyClaimed: true, milestone: 10 });
      throw new Error("expected a second claim to fail");
    } catch (error) {
      expect((error as Error & { code: string }).code).toBe(MILESTONE_ALREADY_CLAIMED);
    }
  });
});
