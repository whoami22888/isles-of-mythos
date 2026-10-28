import { describe, expect, it } from "vitest";
import { AntiCheatService } from "./anti-cheat.js";
import { MemoryAntiCheatStateStore } from "./anti-cheat-store.js";

describe("anti-cheat evidence service", () => {
  it("records movement rate abuse with evidence and suspicion", async () => {
    const service = new AntiCheatService();
    const event = await service.observeMovement("u1", {
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
    expect(await service.suspicionScore("u1", 1_000)).toBe(5);
  });

  it("decays suspicion instead of permanently escalating one anomaly", async () => {
    const service = new AntiCheatService();
    await service.record("u1", "MOVEMENT_INVALID_SEQUENCE", "MEDIUM", {}, 1_000);
    expect(await service.suspicionScore("u1", 3_000)).toBe(0);
  });

  it("records sequence gaps as lower-severity evidence", async () => {
    const service = new AntiCheatService();
    const event = await service.observeMovement("u1", {
      accepted: true,
      sequenceGap: 2,
      serverDt: 0.05,
    }, 2_000);
    expect(event?.type).toBe("MOVEMENT_SEQUENCE_GAP");
    expect(event?.severity).toBe("LOW");
  });

  it("records impossible displacement and rejects non-finite coordinates as evidence", async () => {
    const service = new AntiCheatService();
    expect(await service.observePosition("u1", { x: 0, y: 0 }, { x: 1, y: 0 }, 0.1, 2_000)).toMatchObject({
      type: "IMPOSSIBLE_MOVEMENT",
      severity: "HIGH",
      evidence: { distance: 1, maxDistance: 0.401 },
    });
    expect(await service.observePosition("u2", { x: 0, y: 0 }, { x: Number.NaN, y: 0 }, 0.1, 2_000)).toMatchObject({
      type: "IMPOSSIBLE_MOVEMENT",
      severity: "CRITICAL",
      evidence: { reason: "NON_FINITE_POSITION" },
    });
  });

  it("bounds recent evidence output", async () => {
    const service = new AntiCheatService();
    for (let index = 0; index < 120; index += 1) {
      await service.record("u1", "MOVEMENT_INVALID_SEQUENCE", "LOW", { index }, index);
    }
    expect(service.listRecent("u1", 20)).toHaveLength(20);
  });
  it("detects repeated attack attempts rejected by the server cooldown", async () => {
    const service = new AntiCheatService();
    for (let index = 0; index < 7; index += 1) {
      expect(await service.observeRejectedAction("u1", "ATTACK_COOLDOWN_SPAM", { cooldownRemainingMs: 100 }, 1_000 + index * 100)).toBeNull();
    }
    const event = await service.observeRejectedAction("u1", "ATTACK_COOLDOWN_SPAM", { cooldownRemainingMs: 100 }, 1_700);
    expect(event).toMatchObject({
      type: "ATTACK_COOLDOWN_SPAM",
      severity: "HIGH",
      evidence: { rejectedCount: 8, windowMs: 5_000 },
    });
    expect(await service.suspicionScore("u1", 1_700)).toBe(5);
  });

  it("detects repeated out-of-range resource requests", async () => {
    const isolatedService = new AntiCheatService();
    expect(await isolatedService.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", { distance: 8 }, 1_900)).toBeNull();

    const service = new AntiCheatService();
    for (let index = 0; index < 4; index += 1) {
      expect(await service.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", { distance: 8 }, 2_000 + index * 100)).toBeNull();
    }
    const event = await service.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", { distance: 8 }, 2_400);
    expect(event).toMatchObject({
      type: "RESOURCE_RANGE_ABUSE",
      severity: "MEDIUM",
      evidence: { rejectedCount: 5, windowMs: 10_000 },
    });
  });

  it("detects repeated rejected inventory mutations without sensitive identifiers", async () => {
    const service = new AntiCheatService();
    for (let index = 0; index < 4; index += 1) {
      expect(await service.observeRejectedAction("u1", "INVENTORY_MUTATION_REJECTED", { action: "craft", reason: "INSUFFICIENT_INVENTORY" }, 3_000 + index * 100)).toBeNull();
    }
    const event = await service.observeRejectedAction("u1", "INVENTORY_MUTATION_REJECTED", { action: "craft", reason: "INSUFFICIENT_INVENTORY" }, 3_400);
    expect(event).toMatchObject({
      type: "INVENTORY_MUTATION_REJECTED",
      severity: "MEDIUM",
      evidence: { action: "craft", reason: "INSUFFICIENT_INVENTORY", rejectedCount: 5, windowMs: 10_000 },
    });
    expect(JSON.stringify(event)).not.toContain("requestId");
    expect(JSON.stringify(event)).not.toContain("itemId");
  });

  it("keeps rejected inventory windows separate by action and reason", async () => {
    const service = new AntiCheatService();
    for (let index = 0; index < 4; index += 1) {
      expect(await service.observeRejectedAction("u1", "INVENTORY_MUTATION_REJECTED", { action: "craft", reason: "INSUFFICIENT_INVENTORY" }, 4_000 + index * 100)).toBeNull();
    }
    expect(await service.observeRejectedAction("u1", "INVENTORY_MUTATION_REJECTED", { action: "shop_purchase", reason: "INVENTORY_LIMIT" }, 4_400)).toBeNull();
    expect(await service.observeRejectedAction("u1", "INVENTORY_MUTATION_REJECTED", { action: "craft", reason: "INSUFFICIENT_INVENTORY" }, 4_500)).toMatchObject({
      evidence: { action: "craft", reason: "INSUFFICIENT_INVENTORY", rejectedCount: 5 },
    });
    for (let index = 1; index < 4; index += 1) {
      expect(await service.observeRejectedAction("u1", "INVENTORY_MUTATION_REJECTED", { action: "shop_purchase", reason: "INVENTORY_LIMIT" }, 4_400 + index * 100)).toBeNull();
    }
    expect(await service.observeRejectedAction("u1", "INVENTORY_MUTATION_REJECTED", { action: "shop_purchase", reason: "INVENTORY_LIMIT" }, 4_900)).toMatchObject({
      evidence: { action: "shop_purchase", reason: "INVENTORY_LIMIT", rejectedCount: 5 },
    });
  });

  it("expires rejected-action counts outside the observation window", async () => {
    const service = new AntiCheatService();
    for (let index = 0; index < 4; index += 1) {
      await service.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", {}, 1_000 + index * 100);
    }
    expect(await service.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", {}, 12_000)).toBeNull();
  });

  it("clears rejected-action windows when a user is reset", async () => {
    const service = new AntiCheatService();
    for (let index = 0; index < 4; index += 1) {
      await service.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", {}, 1_000 + index * 100);
    }
    await service.reset("u1");
    expect(await service.observeRejectedAction("u1", "RESOURCE_RANGE_ABUSE", {}, 1_500)).toBeNull();
  });

  it("records repeated replay and coalescing outcomes without request identifiers", async () => {
    const service = new AntiCheatService();
    for (let index = 0; index < 4; index += 1) {
      expect(await service.observeRequestDuplicate("u1", "REPLAYED", 6_000 + index * 100)).toBeNull();
    }
    const event = await service.observeRequestDuplicate("u1", "REPLAYED", 6_400);
    expect(event).toMatchObject({
      type: "REQUEST_DUPLICATION",
      severity: "MEDIUM",
      evidence: { action: "request_duplicate", reason: "REPLAYED", rejectedCount: 5 },
    });
    expect(JSON.stringify(event)).not.toContain("requestId");
    expect(await service.observeRequestDuplicate("u1", "COALESCED", 6_500)).toBeNull();
  });

  it("records excessive same-user sockets with a cooldown and no socket identifiers", async () => {
    const service = new AntiCheatService();
    expect(await service.observeMultiSocket("u1", 3, 8_000)).toBeNull();
    const event = await service.observeMultiSocket("u1", 4, 8_100);
    expect(event).toMatchObject({
      type: "MULTI_SOCKET_ABUSE",
      severity: "MEDIUM",
      evidence: { connectionCount: 4, threshold: 4, windowMs: 10_000 },
    });
    expect(await service.observeMultiSocket("u1", 5, 8_200)).toBeNull();
    expect(await service.observeMultiSocket("u1", 5, 18_200)).toMatchObject({ type: "MULTI_SOCKET_ABUSE" });
    expect(JSON.stringify(event)).not.toContain("socketId");
  });


  describe("socket lease lifecycle", () => {
    // A store whose lease write can be held back, to force a disconnect to overtake an in-flight registration.
    class GatedStore extends MemoryAntiCheatStateStore {
      entered: (() => void) | null = null;
      release: (() => void) | null = null;
      gate = false;
      override async leaseSocket(...args: Parameters<MemoryAntiCheatStateStore["leaseSocket"]>): Promise<number> {
        if (this.gate) {
          this.gate = false;
          await new Promise<void>((resolve) => {
            this.release = resolve;
            this.entered?.();
          });
        }
        return super.leaseSocket(...args);
      }
    }

    it("does not leave a lease behind when disconnect overtakes an in-flight registration", async () => {
      const store = new GatedStore();
      const service = new AntiCheatService({ store });
      const entered = new Promise<void>((resolve) => {
        store.entered = resolve;
      });
      store.gate = true;
      const connecting = service.connectSocket("u1", "s1", 1_000);
      await entered; // the lease write is now waiting on the (simulated) network
      const disconnecting = service.disconnectSocket("u1", "s1");
      store.release?.();
      await Promise.all([connecting, disconnecting]);
      // A fresh probe socket must be the only lease the shared store knows about.
      expect(await store.leaseSocket({ userId: "u1", socketId: "probe", ttlMs: 60_000, nowMs: 1_100 })).toBe(1);
      await service.close();
    });

    it("never registers a socket that was already disconnected before its lease ran", async () => {
      const store = new GatedStore();
      const service = new AntiCheatService({ store });
      const first = service.connectSocket("u1", "s1", 1_000);
      const second = service.disconnectSocket("u1", "s1");
      await Promise.all([first, second]);
      expect(await store.leaseSocket({ userId: "u1", socketId: "probe", ttlMs: 60_000, nowMs: 1_100 })).toBe(1);
      await service.close();
    });
  });
});
