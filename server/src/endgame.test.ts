import { describe, expect, it } from "vitest";
import { calculateGuildBattleScore, calculateHighLevelCreatureDamage, calculateRealmWarScore } from "./endgame.js";

describe("Gate 16 endgame calculations",()=>{
  it("scales realm war score from server-derived army power and guild level",()=>{
    expect(calculateRealmWarScore(1000n,10)).toBe(10000n);
    expect(calculateRealmWarScore(1000n,100)).toBe(100000n);
  });
  it("scales large guild battle score identically and safely",()=>{
    expect(calculateGuildBattleScore(2500n,20)).toBe(50000n);
  });
  it("requires high-level player access and produces bounded deterministic creature damage",()=>{
    expect(calculateHighLevelCreatureDamage(50,75)).toBe(400);
    expect(calculateHighLevelCreatureDamage(100,50)).toBe(850);
    expect(()=>calculateHighLevelCreatureDamage(49,75)).toThrow("ENDGAME_LEVEL_REQUIRED");
  });
});