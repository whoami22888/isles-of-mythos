import type { Pool, PoolClient } from "pg";
import { applyInventoryDelta, runEconomyMutation } from "./economy.js";
import {
  CREATURE_SKILLS, MAX_PRACTICE_AWARD, awardCreatureTraining, awardPlayerPractice,
  canResearchSkill, type BuildingProgress, type SkillId,
} from "./creature-mastery.js";

/** Server-side progression only; never expose award amounts/events to clients. */
export interface ResearchResult { skillId: SkillId; experience: number; unlocked: true; }
export interface TrainingResult { creatureId: string; experience: number; bond: number; }

type Material = Readonly<{ itemId: string; quantity: number }>;
/** Earnable inventory materials; costs need balancing before live-ops. */
export const RESEARCH_MATERIALS: Readonly<Record<SkillId, readonly Material[]>> = {
  tracking: [{ itemId:"resource.herb",quantity:1 }],
  trapcraft: [{ itemId:"resource.wood",quantity:4 },{ itemId:"resource.stone",quantity:2 }],
  animal_handling: [{ itemId:"resource.herb",quantity:2 }],
  creature_training: [{ itemId:"resource.herb",quantity:3 },{ itemId:"resource.wood",quantity:4 }],
  beast_labour: [{ itemId:"resource.wood",quantity:5 },{ itemId:"resource.stone",quantity:5 }],
  mounted_riding: [{ itemId:"resource.wood",quantity:8 },{ itemId:"resource.herb",quantity:4 }],
  aerial_riding: [{ itemId:"resource.wood",quantity:10 },{ itemId:"resource.stone",quantity:10 },{ itemId:"resource.herb",quantity:8 }],
  tactical_creatures: [{ itemId:"resource.stone",quantity:6 },{ itemId:"resource.herb",quantity:4 }],
  creature_husbandry: [{ itemId:"resource.herb",quantity:6 },{ itemId:"resource.wood",quantity:4 }],
};

function validEventId(eventId: string): void {
  if (!/^[A-Za-z0-9._:-]{1,64}$/.test(eventId)) throw new Error("INVALID_PROGRESSION_REQUEST_ID");
}
function validAward(award: number): void {
  if (!Number.isSafeInteger(award) || award < 1 || award > MAX_PRACTICE_AWARD) throw new Error("INVALID_PRACTICE_AWARD");
}
function assertKnownSkill(skillId: string): asserts skillId is SkillId {
  if (!Object.prototype.hasOwnProperty.call(CREATURE_SKILLS, skillId)) throw new Error("UNKNOWN_SKILL");
}
function validStoredXp(value: number): number {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("INVALID_STORED_PROGRESS");
  return value;
}

export class CreatureResearchStore {
  constructor(private readonly db: Pool) {}

  /** Persists an operation and its replay result in the SAME database transaction. */
  private async once<T>(userId: string, eventId: string, fingerprint: string, operation: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.db.connect();
    let rollbackFailure: Error | undefined;
    try {
      await client.query("BEGIN");
      // Locks serialize the user's progression, materials and event decisions across processes.
      const owner = await client.query("SELECT 1 FROM player_profiles WHERE user_id=$1 FOR UPDATE", [userId]);
      if (!owner.rows[0]) throw new Error("PLAYER_NOT_FOUND");
      const key = userId + ":" + eventId;
      const inserted = await client.query(
        "INSERT INTO creature_progression_requests(request_key,user_id,fingerprint,response) VALUES($1,$2,$3,'{}'::jsonb) ON CONFLICT(request_key) DO NOTHING RETURNING request_key",
        [key,userId,fingerprint],
      );
      if (inserted.rowCount !== 1) {
        const existing = await client.query<{ fingerprint: string; response: T }>(
          "SELECT fingerprint,response FROM creature_progression_requests WHERE request_key=$1 FOR UPDATE",[key],
        );
        const row = existing.rows[0];
        if (!row || row.fingerprint !== fingerprint) throw new Error("PROGRESSION_REQUEST_CONFLICT");
        await client.query("COMMIT");
        return row.response;
      }
      const result = await operation(client);
      await client.query("UPDATE creature_progression_requests SET response=$2::jsonb WHERE request_key=$1",[key,JSON.stringify(result)]);
      await client.query("COMMIT");
      return result;
    } catch (error) {
      try { await client.query("ROLLBACK"); }
      catch (rollbackError) {
        rollbackFailure = rollbackError instanceof Error ? rollbackError : new Error(String(rollbackError));
      }
      throw error;
    } finally { client.release(rollbackFailure); }
  }

  async unlock(userId: string, requestId: string, skillId: SkillId): Promise<ResearchResult> {
    validEventId(requestId);
    assertKnownSkill(skillId);
    return this.once(userId,requestId,"unlock|"+skillId,async client=>{
      const progress = await client.query<{skill_id:string;experience:number}>(
        "SELECT skill_id,experience FROM player_creature_skills WHERE user_id=$1",[userId],
      );
      const skills: Record<string,{unlocked:true;experience:number}> = {};
      for (const entry of progress.rows) skills[entry.skill_id]={unlocked:true,experience:validStoredXp(entry.experience)};
      if (skills[skillId]?.unlocked) throw new Error("SKILL_ALREADY_UNLOCKED");
      const buildings = await client.query<BuildingProgress>(
        "SELECT b.type,b.level,b.active FROM base_buildings b JOIN player_bases p ON p.id=b.base_id WHERE p.owner_user_id=$1",[userId],
      );
      const denial = canResearchSkill(skillId,skills,buildings.rows);
      if (denial) throw new Error(denial);
      await runEconomyMutation(client,userId,({gold,inventory})=>{
        let next = inventory;
        for (const material of RESEARCH_MATERIALS[skillId]) next=applyInventoryDelta(next,material.itemId,-material.quantity);
        return {gold,inventory:next,value:undefined};
      },"creature_skill_research");
      await client.query("INSERT INTO player_creature_skills(user_id,skill_id,experience) VALUES($1,$2,0)",[userId,skillId]);
      return {skillId,unlocked:true,experience:0};
    });
  }

  /** Call ONLY from a validated server-side event source (never a client-supplied award). */
  async awardPlayerPractice(userId: string, eventId: string, skillId: SkillId, award: number): Promise<ResearchResult> {
    validEventId(eventId); validAward(award); assertKnownSkill(skillId);
    return this.once(userId,eventId,`practice|${skillId}|${award}`,async client=>{
      const found = await client.query<{experience:number}>(
        "SELECT experience FROM player_creature_skills WHERE user_id=$1 AND skill_id=$2 FOR UPDATE",[userId,skillId],
      );
      if (!found.rows[0]) throw new Error("SKILL_LOCKED");
      const progress = awardPlayerPractice({unlocked:true,experience:validStoredXp(found.rows[0].experience)},award);
      await client.query("UPDATE player_creature_skills SET experience=$3,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1 AND skill_id=$2",[userId,skillId,progress.experience]);
      return {skillId,unlocked:true,experience:progress.experience};
    });
  }

  /** Per-creature progression requires owner, full tame and researched trainer. */
  async awardCreatureTraining(userId: string, eventId: string, creatureId: string, award: number): Promise<TrainingResult> {
    validEventId(eventId); validAward(award);
    return this.once(userId,eventId,`creature|${creatureId}|${award}`,async client=>{
      const trainer = await client.query("SELECT 1 FROM player_creature_skills WHERE user_id=$1 AND skill_id='creature_training'",[userId]);
      if (!trainer.rows[0]) throw new Error("SKILL_LOCKED");
      const found = await client.query<{tame_progress:number}>(
        "SELECT tame_progress FROM player_creatures WHERE owner_user_id=$1 AND id=$2 FOR UPDATE",[userId,creatureId],
      );
      if (!found.rows[0]) throw new Error("CREATURE_NOT_FOUND");
      if (found.rows[0].tame_progress < 100) throw new Error("CREATURE_NOT_TAMED");
      await client.query("INSERT INTO creature_training_progress(creature_id,experience,bond) VALUES($1,0,40) ON CONFLICT(creature_id) DO NOTHING",[creatureId]);
      const previous = await client.query<{experience:number;bond:number}>(
        "SELECT experience,bond FROM creature_training_progress WHERE creature_id=$1 FOR UPDATE",[creatureId],
      );
      const old = previous.rows[0];
      if (!old) throw new Error("CREATURE_TRAINING_STATE_MISSING");
      const progress = awardCreatureTraining({tamed:true,experience:validStoredXp(old.experience)},award);
      if (!Number.isSafeInteger(old.bond) || old.bond < 0 || old.bond > 100) throw new Error("INVALID_STORED_BOND");
      const bond = Math.min(100,old.bond+2);
      await client.query("UPDATE creature_training_progress SET experience=$2,bond=$3,updated_at=CURRENT_TIMESTAMP WHERE creature_id=$1",[creatureId,progress.experience,bond]);
      return {creatureId,experience:progress.experience,bond};
    });
  }
}
