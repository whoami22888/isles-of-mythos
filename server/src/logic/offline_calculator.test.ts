import { describe, expect, it } from "vitest";
import { MAX_OFFLINE_SECONDS, computeOfflineYield, offlineDeltaSeconds } from "./offline_calculator.js";

describe("offline production calculator", () => {
  it("caps a 48-hour absence at exactly 86,400 seconds", () => {
    const last = Date.parse("2026-01-01T00:00:00Z");
    const now = last + 48 * 60 * 60 * 1000;
    expect(offlineDeltaSeconds(last, now)).toBe(MAX_OFFLINE_SECONDS);
    expect(offlineDeltaSeconds(last, now)).toBe(86_400);
  });

  it("applies rate, creature buffs, and VIP, then caps to vault free space", () => {
    const last = 0;
    const now = 10_000;
    const result = computeOfflineYield({
      lastOnlineMs: last,
      nowMs: now,
      baseRatePerSecond: 2,
      creatureBuffs: [0.1, 0.15],
      vipBuff: 1.1,
      stored: 95,
      storageCapacity: 100,
    });
    expect(result.deltaSeconds).toBe(10);
    expect(result.uncappedYield).toBeCloseTo(10 * 2 * 1.25 * 1.1);
    expect(result.appliedYield).toBe(5);
    expect(result.storedAfter).toBe(100);
  });
});
