import { describe, expect, it } from "vitest";
import {
  HIGH_FRUSTRATION_THRESHOLD,
  MONETIZATION_SUPPRESSION_MS,
  evaluateSentiment,
  frustrationIndex,
} from "./sentiment_monitor.js";

describe("fair sentiment monitor", () => {
  it("computes Fi above 7.5 from a high defeat count and never secretly boosts capture odds", () => {
    const telemetry = { defeats1h: 8, failedCaptures: 0, idleQueueHours: 0, successfulQuests: 0 };
    const fi = frustrationIndex(telemetry);
    expect(fi).toBeGreaterThan(HIGH_FRUSTRATION_THRESHOLD);
    const now = 1_700_000_000_000;
    const snapshot = evaluateSentiment(telemetry, now);
    expect(snapshot.highChurnRisk).toBe(true);
    expect(snapshot.secretCaptureOddsBoost).toBe(false);
    expect(snapshot.pressureOfferTriggered).toBe(false);
    expect(snapshot.standardDropTables).toBe(true);
    expect(snapshot.monetizationSuppressedUntilMs).toBe(now + MONETIZATION_SUPPRESSION_MS);
    expect(snapshot.disclosedRecoveryCrate).toBe(true);
  });

  it("keeps standard drop tables and no spend prompts when velocity is high (Fi < 1.5)", () => {
    const snapshot = evaluateSentiment({ defeats1h: 0, failedCaptures: 0, idleQueueHours: 0, successfulQuests: 10 });
    expect(snapshot.highVelocity).toBe(true);
    expect(snapshot.standardDropTables).toBe(true);
    expect(snapshot.pressureOfferTriggered).toBe(false);
    expect(snapshot.monetizationSuppressedUntilMs).toBeNull();
  });
});
