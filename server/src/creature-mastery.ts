/**
 * Research and creature-command policy, not a client authority or a save system.
 * Callers must verify research costs, award provenance, event idempotency and
 * database persistence in one server transaction before committing changes.
 */
export const MAX_SKILL_RANK = 5;
export const MAX_PRACTICE_AWARD = 50;
export const MAX_SKILL_EXPERIENCE = 900;
const RANK_THRESHOLDS = [0, 100, 250, 500, MAX_SKILL_EXPERIENCE] as const;

export type SkillId =
  | "tracking" | "trapcraft" | "animal_handling" | "creature_training"
  | "beast_labour" | "mounted_riding" | "aerial_riding"
  | "tactical_creatures" | "creature_husbandry";
export type FacilityType = "command_centre" | "research_laboratory" | "creature_stable" | "barracks" | "breeding_pen";
export interface SkillDefinition {
  readonly prerequisites: readonly SkillId[];
  readonly facilities: Readonly<Partial<Record<FacilityType, number>>>;
}
export const CREATURE_SKILLS: Readonly<Record<SkillId, SkillDefinition>> = {
  tracking: { prerequisites: [], facilities: { command_centre: 1 } },
  trapcraft: { prerequisites: ["tracking"], facilities: { command_centre: 1, research_laboratory: 1 } },
  animal_handling: { prerequisites: ["tracking"], facilities: { creature_stable: 1 } },
  creature_training: { prerequisites: ["animal_handling"], facilities: { creature_stable: 1, research_laboratory: 1 } },
  beast_labour: { prerequisites: ["creature_training"], facilities: { creature_stable: 1 } },
  mounted_riding: { prerequisites: ["creature_training"], facilities: { creature_stable: 2 } },
  aerial_riding: { prerequisites: ["mounted_riding", "creature_training"], facilities: { research_laboratory: 2, creature_stable: 2 } },
  tactical_creatures: { prerequisites: ["creature_training"], facilities: { barracks: 1, research_laboratory: 1 } },
  creature_husbandry: { prerequisites: ["animal_handling"], facilities: { creature_stable: 2, breeding_pen: 1 } },
};

export interface SkillProgress { readonly unlocked: boolean; readonly experience: number; }
export interface BuildingProgress { readonly type: string; readonly level: number; readonly active: boolean; }
export type PlayerSkills = Readonly<Record<string, SkillProgress | undefined>>;
export type ResearchDenial = "UNKNOWN_SKILL" | "SKILL_PREREQUISITE_MISSING" | "RESEARCH_FACILITY_MISSING";

/** Checks only research requirements; the transactional caller spends earned resources. */
export function canResearchSkill(skill: string, playerSkills: PlayerSkills, buildings: readonly BuildingProgress[]): ResearchDenial | null {
  if (!Object.prototype.hasOwnProperty.call(CREATURE_SKILLS, skill)) return "UNKNOWN_SKILL";
  const definition = CREATURE_SKILLS[skill as SkillId];
  if (definition.prerequisites.some(prerequisite => playerSkills[prerequisite]?.unlocked !== true)) {
    return "SKILL_PREREQUISITE_MISSING";
  }
  for (const [facility, requiredLevel] of Object.entries(definition.facilities)) {
    if (!buildings.some(building => building.active === true && building.type === facility
      && Number.isSafeInteger(building.level) && building.level >= requiredLevel)) {
      return "RESEARCH_FACILITY_MISSING";
    }
  }
  return null;
}

export function rankForExperience(experience: number): number {
  if (!Number.isSafeInteger(experience) || experience < 0) throw new Error("INVALID_SKILL_EXPERIENCE");
  let rank = 1;
  for (const threshold of RANK_THRESHOLDS.slice(1)) if (experience >= threshold) rank++;
  return Math.min(MAX_SKILL_RANK, rank);
}

function safeAward(experience: number, award: number): number {
  if (!Number.isSafeInteger(experience) || experience < 0) throw new Error("INVALID_SKILL_EXPERIENCE");
  // Award provenance and once-only event keys belong to the server transaction.
  if (!Number.isSafeInteger(award) || award < 1 || award > MAX_PRACTICE_AWARD) {
    throw new Error("INVALID_PRACTICE_AWARD");
  }
  return Math.min(MAX_SKILL_EXPERIENCE, experience + award);
}

/** A practice event must be server-verified and non-replayable by its caller. */
export function awardPlayerPractice(progress: SkillProgress, serverAward: number): SkillProgress {
  if (!progress.unlocked) throw new Error("SKILL_LOCKED");
  return { unlocked: true, experience: safeAward(progress.experience, serverAward) };
}

export interface CreatureTrainingProgress { readonly tamed: boolean; readonly experience: number; }
/** Taming and training are separate events; never award training XP for capture. */
export function awardCreatureTraining(progress: CreatureTrainingProgress, serverAward: number): CreatureTrainingProgress {
  if (!progress.tamed) throw new Error("CREATURE_NOT_TAMED");
  return { tamed: true, experience: safeAward(progress.experience, serverAward) };
}

export type CreatureCommand = "follow" | "gather" | "mine" | "log" | "haul" | "scout" | "defend" | "ride" | "fly";
export type CreatureRole = "idle" | "worker" | "combat" | "mount" | "breeding";
export type Capability = "gather" | "mine" | "log" | "haul" | "scout" | "combat" | "mount" | "flight";
export interface TrainableCreature {
  readonly tamed: boolean;
  readonly bond: number;
  readonly creatureExperience: number;
  readonly learnedCommands: readonly string[];
  readonly capabilities: readonly string[];
  readonly role: CreatureRole;
}
interface CommandRequirement {
  readonly playerSkill: SkillId;
  readonly playerRank: number;
  readonly creatureRank: number;
  readonly capability: readonly Capability[];
  readonly role: CreatureRole;
  readonly minimumBond: number;
}
const COMMAND_REQUIREMENTS: Readonly<Record<CreatureCommand, CommandRequirement>> = {
  follow: { playerSkill:"creature_training",playerRank:1,creatureRank:1,capability:[],role:"idle",minimumBond:40 },
  gather: { playerSkill:"beast_labour",playerRank:2,creatureRank:2,capability:["gather"],role:"worker",minimumBond:60 },
  mine: { playerSkill:"beast_labour",playerRank:2,creatureRank:2,capability:["mine"],role:"worker",minimumBond:60 },
  log: { playerSkill:"beast_labour",playerRank:2,creatureRank:2,capability:["log"],role:"worker",minimumBond:60 },
  haul: { playerSkill:"beast_labour",playerRank:2,creatureRank:2,capability:["haul"],role:"worker",minimumBond:60 },
  scout: { playerSkill:"tracking",playerRank:2,creatureRank:2,capability:["scout"],role:"worker",minimumBond:60 },
  defend: { playerSkill:"tactical_creatures",playerRank:2,creatureRank:2,capability:["combat"],role:"combat",minimumBond:60 },
  ride: { playerSkill:"mounted_riding",playerRank:2,creatureRank:2,capability:["mount"],role:"mount",minimumBond:70 },
  fly: { playerSkill:"aerial_riding",playerRank:3,creatureRank:3,capability:["mount","flight"],role:"mount",minimumBond:80 },
};
export type CommandDenial = "UNKNOWN_COMMAND" | "CREATURE_NOT_TAMED" | "CREATURE_BUSY" | "PLAYER_SKILL_LOCKED" | "PLAYER_SKILL_INSUFFICIENT" | "SPECIES_CANNOT_PERFORM_TASK" | "CREATURE_BOND_TOO_LOW" | "CREATURE_NOT_TRAINED" | "COMMAND_NOT_LEARNED";

/** Does not execute a command. Run this at the authoritative command boundary. */
export function canIssueCreatureCommand(command: string, skills: PlayerSkills, creature: TrainableCreature): CommandDenial | null {
  if (!Object.prototype.hasOwnProperty.call(COMMAND_REQUIREMENTS, command)) return "UNKNOWN_COMMAND";
  if (!creature.tamed) return "CREATURE_NOT_TAMED";
  const rule = COMMAND_REQUIREMENTS[command as CreatureCommand];
  if (creature.role !== "idle" && creature.role !== rule.role) return "CREATURE_BUSY";
  const skill = skills[rule.playerSkill];
  if (!skill?.unlocked) return "PLAYER_SKILL_LOCKED";
  if (rankForExperience(skill.experience) < rule.playerRank) return "PLAYER_SKILL_INSUFFICIENT";
  if (rule.capability.some(capability => !creature.capabilities.includes(capability))) return "SPECIES_CANNOT_PERFORM_TASK";
  if (!Number.isFinite(creature.bond) || creature.bond < rule.minimumBond || creature.bond > 100) return "CREATURE_BOND_TOO_LOW";
  if (rankForExperience(creature.creatureExperience) < rule.creatureRank) return "CREATURE_NOT_TRAINED";
  if (!creature.learnedCommands.includes(command)) return "COMMAND_NOT_LEARNED";
  return null;
}
