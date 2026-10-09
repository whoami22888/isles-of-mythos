import { describe, expect, it } from "vitest";
import { AntiCheatService } from "./anti-cheat.js";

describe("anti-cheat evidence service", () => {
  it("records movement rate abuse with evidence and suspicion", () => {
    const service = new AntiCheatService();
    const event = service.observeMovement("u1", {
      accepted: false,
      reason: "RATE_LIMITED",
      sequenceGap: 3,
      serverDt: 0,
    }, 1_000);
    expect(event).toMatchObject({
      userId: "u1",
      type: "MOVEMENT_RATE_LIMIT",
      severity: "HIGH",
      timestampMs: 1_000,
      evidence: { sequenceGap: 3, serverDt: 0 },
    });
    expect(service.suspicionScore("u1", 1_000)).toBe(5);
  });

  it("decays suspicion instead of permanently escalating one anomaly", () => {
    const service = new AntiCheatService();
    service.record("u1", "MOVEMENT_INVALID_SEQUENCE", "MEDIUM", {}, 1_000);
    expect(service.suspicionScore("u1", 3_000)).toBe(0);
  });

  it("records sequence gaps as lower-severity evidence", () => {
    const service = new AntiCheatService();
    const event = service.observeMovement("u1", {
      accepted: true,
      sequenceGap: 2,
      serverDt: 0.05,
    }, 2_000);
    expect(event?.type).toBe("MOVEMENT_SEQUENCE_GAP");
    expect(event?.severity).toBe("LOW");
  });

  it("bounds recent evidence output", () => {
    const service = new AntiCheatService();
    for (let index = 0; index < 120; index += 1) {
      service.record("u1", "MOVEMENT_INVALID_SEQUENCE", "LOW", { index }, index);
    }
    expect(service.listRecent("u1", 20)).toHaveLength(20);
  });
  it("detects repeated attack attempts rejected by the server cooldown", () => {
    const service = new AntiCheatService();
    for (let index = 0; index < 7; index += 1) {
      expect(service.observeRejectedAction("u1", "ATTACK_COOLDOWN_SPAM", { cooldownRemainingMs: 100 }, 1_000 + index * 100)).toBeNull();
    }
    const event = service.observeRejectedAction("u1", "ATTACK_COOLDOWN_SPAM", { cooldownRemainingMs: 100 }, 1_700);
    expect(event).toMatchObject({
      type: "ATTACK_COOLDOWN_SPAM",
      severity: "HIGH",
      evidence: { rejectedCount: 8, windowMs: 5_000 },
    });
    expect(service.suspicionScore("u1", 1_700)).toBe(5);
  });

  it("detects repeated out-of-range resource requests", () => {
    const isolatedService = new AntiCheatService();
    expect(isolatedService.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", { distance: 8 }, 1_900)).toBeNull();

    const service = new AntiCheatService();
    for (let index = 0; index < 4; index += 1) {
      expect(service.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", { distance: 8 }, 2_000 + index * 100)).toBeNull();
    }
    const event = service.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", { distance: 8 }, 2_400);
    expect(event).toMatchObject({
      type: "RESOURCE_RANGE_ABUSE",
      severity: "MEDIUM",
      evidence: { rejectedCount: 5, windowMs: 10_000 },
    });
  });

  it("expires rejected-action counts outside the observation window", () => {
    const service = new AntiCheatService();
    for (let index = 0; index < 4; index += 1) {
      service.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", {}, 1_000 + index * 100);
    }
    expect(service.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", {}, 12_000)).toBeNull();
  });

  it("clears rejected-action windows when a user is reset", () => {
    const service = new AntiCheatService();
    for (let index = 0; index < 4; index += 1) {
      service.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", {}, 1_000 + index * 100);
    }
    service.reset("u1");
    expect(service.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", {}, 1_500)).toBeNull();
  });

});
