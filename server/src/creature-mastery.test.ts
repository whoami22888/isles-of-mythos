import { describe, expect, it } from "vitest";
import {
  CREATURE_SKILLS, MAX_SKILL_RANK, awardPlayerPractice, awardCreatureTraining,
  canResearchSkill, canIssueCreatureCommand, rankForExperience,
} from "./creature-mastery.js";

const buildings = [
  { type: "command_centre", level: 3, active: true },
  { type: "research_laboratory", level: 2, active: true },
  { type: "creature_stable", level: 2, active: true },
  { type: "barracks", level: 1, active: true },
];
const skills = {
  tracking: { unlocked: true, experience: 500 },
  animal_handling: { unlocked: true, experience: 500 },
  creature_training: { unlocked: true, experience: 500 },
  beast_labour: { unlocked: true, experience: 500 },
  mounted_riding: { unlocked: true, experience: 500 },
  aerial_riding: { unlocked: true, experience: 500 },
  tactical_creatures: { unlocked: true, experience: 500 },
};
const dragon = { tamed: true, bond: 85, creatureExperience: 500, learnedCommands: ["follow", "ride", "fly", "scout"], capabilities: ["mount", "flight", "scout"], role: "idle" as const };

describe("research-earned creature skills", () => {
  it("requires player research prerequisites before skill can be unlocked", () => {
    expect(canResearchSkill("aerial_riding", {}, buildings)).toBe("SKILL_PREREQUISITE_MISSING");
    expect(canResearchSkill("aerial_riding", skills, buildings)).toBeNull();
    expect(canResearchSkill("nonexistent", skills, buildings)).toBe("UNKNOWN_SKILL");
  });
  it("requires actual active buildings at minimum level", () => {
    expect(canResearchSkill("aerial_riding", skills, [{type:"research_laboratory",level:1,active:true}])).toBe("RESEARCH_FACILITY_MISSING");
    expect(canResearchSkill("aerial_riding", skills, buildings.map(b=>b.type==="creature_stable"?{...b,active:false}:b))).toBe("RESEARCH_FACILITY_MISSING");
  });
  it("defines an acyclic tree with research-gated training branches", () => {
    const all = Object.keys(CREATURE_SKILLS);
    expect(all.length).toBeGreaterThanOrEqual(7);
    const seen = new Set<string>();
    const visit=(id:string,path=new Set<string>())=>{
      expect(path.has(id)).toBe(false);
      if(seen.has(id))return;
      const next = new Set(path); next.add(id);
      for(const prior of CREATURE_SKILLS[id as keyof typeof CREATURE_SKILLS].prerequisites)visit(prior,next);
      seen.add(id);
    };
    for(const id of all)visit(id);
    expect(seen.size).toBe(all.length);
  });
  it("makes earned practice improve rank but refuses malformed or unearned XP", () => {
    expect(rankForExperience(0)).toBe(1);
    // Exact boundaries: one point below and at each earned-rank threshold.
    expect(rankForExperience(99)).toBe(1);
    expect(rankForExperience(100)).toBe(2);
    expect(rankForExperience(249)).toBe(2);
    expect(rankForExperience(250)).toBe(3);
    expect(rankForExperience(499)).toBe(3);
    expect(rankForExperience(500)).toBe(4);
    expect(rankForExperience(899)).toBe(4);
    expect(rankForExperience(900)).toBe(5);
    expect(rankForExperience(1_000_000)).toBe(MAX_SKILL_RANK);
    expect(awardPlayerPractice({unlocked:true,experience:95}, 10)).toEqual({unlocked:true,experience:105});
    expect(()=>awardPlayerPractice({unlocked:false,experience:0},10)).toThrow("SKILL_LOCKED");
    expect(()=>awardPlayerPractice({unlocked:true,experience:0},Number.POSITIVE_INFINITY)).toThrow("INVALID_PRACTICE_AWARD");
    expect(()=>awardPlayerPractice({unlocked:true,experience:0},100000)).toThrow("INVALID_PRACTICE_AWARD");
  });
  it("tracks creature practice separately from player mastery", () => {
    expect(awardCreatureTraining({tamed:true,experience:90},20)).toEqual({tamed:true,experience:110});
    expect(()=>awardCreatureTraining({tamed:false,experience:90},20)).toThrow("CREATURE_NOT_TAMED");
    expect(()=>awardCreatureTraining({tamed:true,experience:90},0)).toThrow("INVALID_PRACTICE_AWARD");
  });
  it("requires both research and creature training before flight", () => {
    expect(canIssueCreatureCommand("fly",skills,dragon)).toBeNull();
    expect(canIssueCreatureCommand("fly",{...skills,aerial_riding:{unlocked:false,experience:500}},dragon)).toBe("PLAYER_SKILL_LOCKED");
    expect(canIssueCreatureCommand("fly",skills,{...dragon,creatureExperience:0})).toBe("CREATURE_NOT_TRAINED");
    expect(canIssueCreatureCommand("fly",skills,{...dragon,bond:10})).toBe("CREATURE_BOND_TOO_LOW");
    expect(canIssueCreatureCommand("fly",skills,{...dragon,capabilities:["mount"]})).toBe("SPECIES_CANNOT_PERFORM_TASK");
    expect(canIssueCreatureCommand("fly",skills,{...dragon,learnedCommands:["follow","ride"]})).toBe("COMMAND_NOT_LEARNED");
  });
  it("gates work and combat by natural capabilities and role exclusivity", () => {
    const worker = {...dragon,capabilities:["mine","haul"],learnedCommands:["mine","haul","follow"]};
    expect(canIssueCreatureCommand("mine",skills,worker)).toBeNull();
    expect(canIssueCreatureCommand("mine",skills,{...worker,role:"combat" as const})).toBe("CREATURE_BUSY");
    expect(canIssueCreatureCommand("mine",skills,{...worker,capabilities:["flight"]})).toBe("SPECIES_CANNOT_PERFORM_TASK");
    expect(canIssueCreatureCommand("defend",skills,worker)).toBe("SPECIES_CANNOT_PERFORM_TASK");
    expect(canIssueCreatureCommand("ride",skills,{...worker,role:"breeding" as const})).toBe("CREATURE_BUSY");
  });
});
