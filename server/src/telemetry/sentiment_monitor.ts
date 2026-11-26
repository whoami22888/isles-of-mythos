/** Fair player-experience telemetry. Frustration is observed, never used to hide odds or sell under pressure. */

export const SENTIMENT_TICK_MS = 10_000;
export const HIGH_FRUSTRATION_THRESHOLD = 7.5;
export const LOW_FRUSTRATION_THRESHOLD = 1.5;
export const MONETIZATION_SUPPRESSION_MS = 48 * 60 * 60 * 1000;

export interface SessionTelemetry {
  defeats1h: number;
  failedCaptures: number;
  idleQueueHours: number;
  successfulQuests: number;
}

export interface SentimentSnapshot {
  frustrationIndex: number;
  highChurnRisk: boolean;
  highVelocity: boolean;
  monetizationSuppressedUntilMs: number | null;
  disclosedRecoveryCrate: boolean;
  /** Always false: capture odds are never secretly changed. */
  secretCaptureOddsBoost: false;
  /** Always false: no frustration-triggered spend prompts. */
  pressureOfferTriggered: false;
  standardDropTables: boolean;
}

export function frustrationIndex(telemetry: SessionTelemetry): number {
  const defeats = Math.max(0, telemetry.defeats1h);
  const failed = Math.max(0, telemetry.failedCaptures);
  const idle = Math.max(0, telemetry.idleQueueHours);
  const quests = Math.max(0, telemetry.successfulQuests);
  return (defeats * 2.5 + failed * 1.8 + idle * 1.2) / (quests + 1);
}

export function evaluateSentiment(telemetry: SessionTelemetry, nowMs = Date.now()): SentimentSnapshot {
  const fi = frustrationIndex(telemetry);
  const high = fi > HIGH_FRUSTRATION_THRESHOLD;
  const low = fi < LOW_FRUSTRATION_THRESHOLD;
  return {
    frustrationIndex: fi,
    highChurnRisk: high,
    highVelocity: low,
    // High frustration suppresses monetization for 48 hours. It does not alter drop odds or spawn paid offers.
    monetizationSuppressedUntilMs: high ? nowMs + MONETIZATION_SUPPRESSION_MS : null,
    disclosedRecoveryCrate: high,
    secretCaptureOddsBoost: false,
    pressureOfferTriggered: false,
    standardDropTables: true,
  };
}

export class SentimentMonitor {
  evaluate(telemetry: SessionTelemetry, nowMs = Date.now()): SentimentSnapshot {
    return evaluateSentiment(telemetry, nowMs);
  }

  tick(getTelemetry: () => SessionTelemetry, nowMs = Date.now()): SentimentSnapshot {
    return this.evaluate(getTelemetry(), nowMs);
  }
}
