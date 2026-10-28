import { describe, expect, it } from "vitest";
import { CREW_START_MORALE, deriveCreatureCrewSkill, deriveNpcCrewSkill } from "./crew-stats.js";

describe("server-derived crew stats", () => {
  it("creature crew skill is the creature level clamped to 1..100", () => {
    expect(deriveCreatureCrewSkill(1)).toBe(1);
    expect(deriveCreatureCrewSkill(37)).toBe(37);
    expect(deriveCreatureCrewSkill(100)).toBe(100);
    expect(deriveCreatureCrewSkill(0)).toBe(1);
    expect(deriveCreatureCrewSkill(250)).toBe(100);
    expect(deriveCreatureCrewSkill(Number.NaN)).toBe(1);
    expect(deriveCreatureCrewSkill(12.9)).toBe(12);
  });
  it("npc skill depends only on the npc type, identically for every call", () => {
    for (const t of ["pirate", "mermaid", "dragon", "npc_specialist"] as const) {
      const v = deriveNpcCrewSkill(t);
      expect(Number.isSafeInteger(v) && v >= 1 && v <= 100, t).toBe(true);
      expect(deriveNpcCrewSkill(t)).toBe(v);
    }
  });
  it("starting morale is a server constant within 0..100", () => {
    expect(CREW_START_MORALE).toBeGreaterThanOrEqual(0);
    expect(CREW_START_MORALE).toBeLessThanOrEqual(100);
  });
});
