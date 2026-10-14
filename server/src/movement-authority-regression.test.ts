import { describe, expect, it } from "vitest";
import { MovementAuthority, MOVEMENT_MAX_PACKETS_PER_SECOND, createDefaultPlayer, applyAuthoritativePlayerInput } from "./player.js";
import { parseClientMessage } from "./protocol.js";
import { AntiCheatService } from "./anti-cheat.js";

describe("P0 movement authority integrated regressions", () => {
  it("does not allow client time or speed modifiers to change a parsed move", () => {
    expect(parseClientMessage(JSON.stringify({
      type: "move", dx: 1, dy: 0, sequence: 2, dt: 60, speedMultiplier: 100,
    }))).toEqual({ type: "move", dx: 1, dy: 0, sequence: 2 });
  });

  it("bounds displacement by monotonic server time and rejects rate-limited movement", () => {
    const authority = new MovementAuthority();
    const userId = "server-time-budget";
    const player = createDefaultPlayer(userId);
    authority.prime(userId, 10_000);
    let accepted = 0;
    for (let sequence = 1; sequence <= MOVEMENT_MAX_PACKETS_PER_SECOND + 5; sequence += 1) {
      const decision = authority.evaluate(userId, { dx: 1, dy: 0, sequence }, 10_000 + sequence);
      if (decision.accepted) {
        accepted += 1;
        applyAuthoritativePlayerInput(player, { dx: 1, dy: 0, sequence }, decision.serverDt);
      } else {
        expect(decision.reason).toBe("RATE_LIMITED");
      }
    }
    expect(accepted).toBeLessThanOrEqual(MOVEMENT_MAX_PACKETS_PER_SECOND);
    expect(player.x).toBeLessThan(1);
  });

  it("rejects replayed, stale, negative and unsafe sequences without displacement", () => {
    const authority = new MovementAuthority();
    const userId = "sequence-contract";
    const player = createDefaultPlayer(userId);
    authority.prime(userId, 20_000);
    const accepted = authority.evaluate(userId, { dx: 1, dy: 0, sequence: 4 }, 20_050);
    expect(accepted.accepted).toBe(true);
    applyAuthoritativePlayerInput(player, { dx: 1, dy: 0, sequence: 4 }, accepted.serverDt);
    const before = player.x;
    expect(authority.evaluate(userId, { dx: 1, dy: 0, sequence: 4 }, 20_100).reason).toBe("DUPLICATE_SEQUENCE");
    expect(authority.evaluate(userId, { dx: 1, dy: 0, sequence: 3 }, 20_150).reason).toBe("DUPLICATE_SEQUENCE");
    expect(authority.evaluate(userId, { dx: 1, dy: 0, sequence: -1 }, 20_200).reason).toBe("INVALID_SEQUENCE");
    expect(authority.evaluate(userId, { dx: 1, dy: 0, sequence: Number.MAX_SAFE_INTEGER + 1 }, 20_250).reason).toBe("INVALID_SEQUENCE");
    expect(player.x).toBe(before);
  });

  it("restarts sequence state on prime/reset and rolls the rate window at one second", () => {
    const authority = new MovementAuthority();
    const userId = "window-rollover";
    authority.prime(userId, 30_000);
    authority.evaluate(userId, { dx: 1, dy: 0, sequence: 0 }, 30_000);
    for (let sequence = 1; sequence <= MOVEMENT_MAX_PACKETS_PER_SECOND - 1; sequence += 1) {
      authority.evaluate(userId, { dx: 1, dy: 0, sequence }, 30_000 + sequence);
    }
    expect(authority.evaluate(userId, { dx: 1, dy: 0, sequence: MOVEMENT_MAX_PACKETS_PER_SECOND }, 30_050).reason).toBe("RATE_LIMITED");
    const afterRollover = authority.evaluate(
      userId,
      { dx: 1, dy: 0, sequence: MOVEMENT_MAX_PACKETS_PER_SECOND + 1 },
      31_000,
    );
    expect(afterRollover.accepted).toBe(true);
    authority.reset(userId);
    const newSession = authority.evaluate(userId, { dx: 1, dy: 0, sequence: 0 }, 32_000);
    expect(newSession.accepted).toBe(false);
    const next = authority.evaluate(userId, { dx: 1, dy: 0, sequence: 1 }, 32_050);
    expect(next.accepted).toBe(true);
  });

  it("records repeated anomalies as evidence instead of applying automatic permanent bans", () => {
    const antiCheat = new AntiCheatService();
    const first = antiCheat.observeMovement("evidence-user", {
      accepted: false, reason: "RATE_LIMITED", sequenceGap: 0, serverDt: 0,
    }, 40_000);
    expect(first?.type).toBe("MOVEMENT_RATE_LIMIT");
    expect(antiCheat.suspicionScore("evidence-user", 40_000)).toBeGreaterThan(0);
    expect(antiCheat.listRecent("evidence-user")).toHaveLength(1);
  });
});
