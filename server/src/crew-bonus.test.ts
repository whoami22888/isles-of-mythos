import { describe, expect, it } from "vitest";
import { CREW_BONUS_CAPS, CREW_STACK_DECAY, stackCrewContributions } from "./crew-bonus.js";

// Finding D: crew bonuses were plain sums, so recruiting more crew scaled power without bound.
// Contributions now stack with diminishing returns (best first, each next weighted by DECAY^rank) and a hard cap.
describe("stackCrewContributions", () => {
  it("one contributor is unchanged (no nerf to a lone specialist)", () => {
    expect(stackCrewContributions([80], 1000)).toBe(80);
  });
  it("returns 0 for no crew and ignores invalid, negative and non-finite contributions", () => {
    expect(stackCrewContributions([], 1000)).toBe(0);
    expect(stackCrewContributions([NaN, -5, Infinity, 0], 1000)).toBe(0);
  });
  it("is order independent", () => {
    expect(stackCrewContributions([10, 90, 40], 1000)).toBe(stackCrewContributions([90, 40, 10], 1000));
  });
  it("each extra crew member adds strictly less than the one before (diminishing returns)", () => {
    const totals = [1, 2, 3, 4, 5, 6].map(n => stackCrewContributions(Array(n).fill(100), 10_000));
    const gains = totals.slice(1).map((v, i) => v - totals[i]);
    for (let i = 1; i < gains.length; i++) expect(gains[i]).toBeLessThan(gains[i - 1]);
    expect(gains[0]).toBeCloseTo(100 * CREW_STACK_DECAY);
  });
  it("is bounded by best/(1-decay) however many identical crew are added, even with no explicit cap", () => {
    const ceiling = 100 / (1 - CREW_STACK_DECAY);
    expect(stackCrewContributions(Array(1000).fill(100), Number.POSITIVE_INFINITY)).toBeLessThanOrEqual(ceiling);
  });
  it("a hard cap is enforced regardless of the raw stack", () => {
    expect(stackCrewContributions(Array(50).fill(100), 120)).toBe(120);
  });
  it("quantity cannot beat quality: ten weak crew do not outweigh two strong ones", () => {
    expect(stackCrewContributions(Array(10).fill(10), 1000)).toBeLessThan(stackCrewContributions([100, 90], 1000));
  });
  it("duplicate crew cannot be used to multiply one specialist (same total as the equivalent distinct stack)", () => {
    expect(stackCrewContributions([100, 100], 1000)).toBe(150);
  });
  it("rejects an invalid cap by failing closed to 0", () => {
    expect(stackCrewContributions([100], NaN)).toBe(0);
    expect(stackCrewContributions([100], -1)).toBe(0);
  });
  it("exposes positive finite named caps", () => {
    for (const v of Object.values(CREW_BONUS_CAPS)) { expect(Number.isFinite(v)).toBe(true); expect(v).toBeGreaterThan(0); }
  });
});
