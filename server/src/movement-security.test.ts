import { describe, expect, it } from "vitest";
import {
  MovementAuthority,
  MOVEMENT_MAX_PACKETS_PER_SECOND,
  applyAuthoritativePlayerInput,
  createDefaultPlayer,
} from "./player.js";
import { parseClientMessage } from "./protocol.js";

describe("P0 movement speedhack regressions", () => {
  it("does not expose client timing or speed multipliers in parsed movement input", () => {
    expect(parseClientMessage(JSON.stringify({
      type: "move",
      dx: 1,
      dy: 0,
      sequence: 7,
      dt: 60,
      speedMultiplier: 1,
    }))).toEqual({
      type: "move",
      dx: 1,
      dy: 0,
      sequence: 7,
    });
  });

  it("bounds repeated forged-time movement to elapsed server time and the packet budget", () => {
    const authority = new MovementAuthority();
    const player = createDefaultPlayer("forged-time-regression");
    const startMs = 10_000;
    authority.evaluate("forged-time-regression", { dx: 1, dy: 0, sequence: 0 }, startMs);

    let accepted = 0;
    for (let sequence = 1; sequence <= MOVEMENT_MAX_PACKETS_PER_SECOND + 10; sequence += 1) {
      const decision = authority.evaluate(
        "forged-time-regression",
        { dx: 1, dy: 0, sequence },
        startMs + sequence,
      );
      if (decision.accepted) {
        accepted += 1;
        applyAuthoritativePlayerInput(player, { dx: 1, dy: 0, sequence }, decision.serverDt);
      } else {
        expect(decision.reason).toBe("RATE_LIMITED");
      }
    }

    const elapsedSeconds = (MOVEMENT_MAX_PACKETS_PER_SECOND + 10) / 1_000;
    expect(accepted).toBeLessThanOrEqual(MOVEMENT_MAX_PACKETS_PER_SECOND - 1);
    expect(player.x).toBeLessThanOrEqual(4 * elapsedSeconds + 1e-9);
    expect(player.x).toBeLessThan(1);
  });

  it("rejects non-finite and malformed directions at the protocol boundary", () => {
    expect(parseClientMessage('{"type":"move","dx":null,"dy":0,"sequence":1}')).toBeNull();
    expect(parseClientMessage('{"type":"move","dx":1,"dy":"Infinity","sequence":1}')).toBeNull();
    expect(parseClientMessage('{"type":"move","dx":1,"dy":0,"sequence":-1}')).toBeNull();
  });

  it("does not let a sequence replay or an invalid sequence grant movement time", () => {
    const authority = new MovementAuthority();
    const first = authority.evaluate("sequence-regression", { dx: 1, dy: 0, sequence: 4 }, 20_000);
    const replay = authority.evaluate("sequence-regression", { dx: 1, dy: 0, sequence: 4 }, 20_100);
    const invalid = authority.evaluate("sequence-regression", { dx: 1, dy: 0, sequence: Number.MAX_SAFE_INTEGER + 1 }, 20_200);
    expect(first.accepted).toBe(false);
    expect(replay.reason).toBe("DUPLICATE_SEQUENCE");
    expect(invalid.reason).toBe("INVALID_SEQUENCE");
    const next = authority.evaluate("sequence-regression", { dx: 1, dy: 0, sequence: 5 }, 20_250);
    expect(next.serverDt).toBeCloseTo(0.05, 6);
  });
});
