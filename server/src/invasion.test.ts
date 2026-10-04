import {describe,expect,it} from "vitest";
import {buildWavePlan,calculateThreatScore,nextPhaseAt,PHASE_SECONDS,INVASION_PHASES} from "./invasion.js";
describe("Gate 13 invasion engine",()=>{
 it("scales threat from server-side factors and clamps the result",()=>{
  expect(calculateThreatScore({playerLevel:10,guildLevel:5,territoryStrength:100,previousVictories:2,activePlayers:4,baseDefense:500,regionalThreat:200} )).toBe(2125);
  expect(calculateThreatScore({playerLevel:9999,guildLevel:9999,territoryStrength:999999,previousVictories:9999,activePlayers:9999,baseDefense:999999,regionalThreat:999999})).toBe(100000);
 });
 it("builds deterministic multi-unit waves",()=>{
  const waves=buildWavePlan(10000);
  expect(waves.length).toBeGreaterThanOrEqual(2);
  expect(waves.every(w=>w.quantity>0&&w.attack>0&&w.defense>=0)).toBe(true);
 });
 it("uses the required lifecycle in order",()=>{
  expect(INVASION_PHASES.slice(0,8)).toEqual(["WARNING","MUSTER","ARRIVAL","ASSAULT","BATTLE","RESOLUTION","REWARD","COOLDOWN"]);
  const start=new Date("2026-10-05T00:00:00Z");expect(nextPhaseAt("WARNING",start).getTime()-start.getTime()).toBe(PHASE_SECONDS.WARNING*1000);
 });
});