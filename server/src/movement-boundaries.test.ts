import { describe, expect, it } from "vitest";
import { MovementAuthority, applyAuthoritativePlayerInput, createDefaultPlayer } from "./player.js";
import { parseClientMessage } from "./protocol.js";

describe("movement boundary acceptance for issue 120", () => {
  it.each([-1, 0.5, Number.MAX_SAFE_INTEGER + 1, Number.NaN, Number.POSITIVE_INFINITY])(
    "rejects invalid sequence %s without consuming the next valid input",
    (sequence) => {
      const authority = new MovementAuthority();
      authority.prime("player", 1_000);
      expect(authority.evaluate("player", { dx: 1, dy: 0, sequence }, 1_025))
        .toMatchObject({ accepted: false, reason: "INVALID_SEQUENCE", serverDt: 0 });
      expect(authority.evaluate("player", { dx: 1, dy: 0, sequence: 0 }, 1_050))
        .toMatchObject({ accepted: true, serverDt: 0.05, sequenceGap: 0 });
    },
  );

  it("records a sequence gap without granting movement for skipped packets", () => {
    const authority = new MovementAuthority();
    authority.prime("player", 1_000);
    authority.evaluate("player", { dx: 1, dy: 0, sequence: 0 }, 1_025);
    expect(authority.evaluate("player", { dx: 1, dy: 0, sequence: 100 }, 1_050))
      .toMatchObject({ accepted: true, serverDt: 0.025, sequenceGap: 99 });
  });

  it("resets the packet allowance at exactly the one-second boundary", () => {
    const authority = new MovementAuthority();
    authority.prime("player", 1_000);
    for (let sequence = 0; sequence < 40; sequence += 1) {
      expect(authority.evaluate("player", { dx: 1, dy: 0, sequence }, 1_001 + sequence).accepted).toBe(true);
    }
    expect(authority.evaluate("player", { dx: 1, dy: 0, sequence: 40 }, 1_999))
      .toMatchObject({ accepted: false, reason: "RATE_LIMITED" });
    expect(authority.evaluate("player", { dx: 1, dy: 0, sequence: 41 }, 2_000))
      .toMatchObject({ accepted: true, serverDt: 0.001 });
    expect(authority.evaluate("player", { dx: 1, dy: 0, sequence: 41 }, 2_001))
      .toMatchObject({ accepted: false, reason: "DUPLICATE_SEQUENCE" });
  });

  it("clears old sequence and flood state on reset and primes only the new session clock", () => {
    const authority = new MovementAuthority();
    authority.prime("player", 1_000);
    for (let sequence = 0; sequence <= 40; sequence += 1) {
      authority.evaluate("player", { dx: 1, dy: 0, sequence }, 1_001 + sequence);
    }
    authority.reset("player");
    expect(authority.evaluate("player", { dx: 1, dy: 0, sequence: 0 }, 5_000))
      .toMatchObject({ accepted: true, serverDt: 0, sequenceGap: 0 });
    authority.prime("player", 6_000);
    expect(authority.evaluate("player", { dx: 1, dy: 0, sequence: 0 }, 6_050))
      .toMatchObject({ accepted: true, serverDt: 0.05, sequenceGap: 0 });
  });

  it.each([
    '{"type":"move","dx":1e400,"dy":0,"sequence":0}',
    '{"type":"move","dx":0,"dy":-1e400,"sequence":0}',
    '{"type":"move","dx":null,"dy":0,"sequence":0}',
    '{"type":"move","dx":"NaN","dy":0,"sequence":0}',
    '{"type":"move","dx":{},"dy":0,"sequence":0}',
    '{"type":"move","dx":1,"dy":0,"sequence":9007199254740992}',
    '{"type":"move","dx":1,"dy":0,"sequence":0.5}',
  ])("rejects malformed or non-finite wire input: %s", (wire) => {
    expect(parseClientMessage(wire)).toBeNull();
  });

  it("strips client multipliers before applying a server-owned slow", () => {
    const message = parseClientMessage('{"type":"move","dx":1,"dy":0,"sequence":0,"dt":60,"speedMultiplier":100}');
    expect(message).toEqual({ type: "move", dx: 1, dy: 0, sequence: 0 });
    if (message?.type !== "move") throw new Error("Expected a valid movement message");
    const normal = createDefaultPlayer("normal");
    const slowed = createDefaultPlayer("slowed");
    applyAuthoritativePlayerInput(normal, message, 0.05);
    applyAuthoritativePlayerInput(slowed, { ...message, speedMultiplier: 0.35 }, 0.05);
    expect(normal.x).toBeCloseTo(0.125, 8);
    expect(slowed.x).toBeCloseTo(0.04375, 8);
    expect(slowed.y).toBe(0);
  });
});
