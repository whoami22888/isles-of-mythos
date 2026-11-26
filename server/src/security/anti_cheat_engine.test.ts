import { describe, expect, it } from "vitest";
import {
  ILLEGAL_SPEED_AUDIT_FLAG,
  recordIllegalMovementAudit,
  validateSpatialUpdate,
} from "./anti_cheat_engine.js";

describe("anti-cheat movement validation", () => {
  it("rolls back a 1,000-meter jump in one second and writes an audit flag", async () => {
    const previous = { x: 0, y: 0, atMs: 0 };
    const next = { x: 1_000, y: 0, atMs: 1_000 };
    const verdict = validateSpatialUpdate(previous, next);
    expect(verdict.legal).toBe(false);
    expect(verdict.velocity).toBe(1_000);
    expect(verdict.rolledBackTo).toEqual(previous);
    const flags: string[] = [];
    await recordIllegalMovementAudit(async (flag) => { flags.push(flag); }, verdict);
    expect(flags).toEqual([ILLEGAL_SPEED_AUDIT_FLAG]);
  });

  it("accepts movement at or under the published ship speed budget", () => {
    const previous = { x: 0, y: 0, atMs: 0 };
    const next = { x: 40, y: 0, atMs: 1_000 };
    expect(validateSpatialUpdate(previous, next).legal).toBe(true);
  });
});
