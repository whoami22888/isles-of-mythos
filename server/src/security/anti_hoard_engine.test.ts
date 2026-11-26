import { describe, expect, it } from "vitest";
import { evaluateSeaRaider } from "./anti_hoard_engine.js";

describe("anti-hoard sea raider", () => {
  it("triggers a non-destructive raid after 73 hours at 90% storage without an upgrade", () => {
    const start = 0;
    const event = evaluateSeaRaider({
      stored: 90,
      capacity: 100,
      hoardStartedAtMs: start,
      lastUpgradeAtMs: start - 1,
    }, start + 73 * 3_600_000);
    expect(event.triggered).toBe(true);
    expect(event.utilization).toBeCloseTo(0.9);
    expect(event.seized).toBeCloseTo((90 - 85) * 0.05);
    expect(event.storedAfter).toBeCloseTo(90 - event.seized);
  });

  it("does not raid if the player started an upgrade during the hoard window", () => {
    const start = 0;
    const event = evaluateSeaRaider({
      stored: 90,
      capacity: 100,
      hoardStartedAtMs: start,
      lastUpgradeAtMs: start + 10 * 3_600_000,
    }, start + 73 * 3_600_000);
    expect(event.triggered).toBe(false);
    expect(event.seized).toBe(0);
  });
});
