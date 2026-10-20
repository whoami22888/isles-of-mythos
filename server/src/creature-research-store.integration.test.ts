import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { BaseStore } from "./base.js";
import { createDbPool } from "./db.js";
import { CreatureResearchStore } from "./creature-research-store.js";

async function register() {
  const app = await buildApp();
  const id = randomUUID().replace(/-/g, "").slice(0, 20);
  const response = await app.inject({ method:"POST", url:"/auth/register", payload:{
    username:`research_${id}`, email:`research_${id}@example.com`, password:"Correct-Horse-Battery-9",
  }});
  expect(response.statusCode).toBe(201);
  const userId = (JSON.parse(response.body) as {user:{id:string}}).user.id;
  await app.close();
  return userId;
}

describe("IOM-04 persistent research and independent creature mastery", () => {
  it("spends earned materials atomically, replays requests after restart and trains creatures separately", async () => {
    const db = createDbPool();
    try {
      const userId = await register();
      await db.query("INSERT INTO player_profiles(user_id,inventory) VALUES($1,$2::jsonb) ON CONFLICT(user_id) DO UPDATE SET inventory=EXCLUDED.inventory",[
        userId,JSON.stringify({"resource.wood":20,"resource.stone":20,"resource.herb":10}),
      ]);
      const base = await new BaseStore(db).create(userId,"Research Outpost",0,0);
      await db.query("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'research_laboratory',2,2,0,true),($1,'creature_stable',2,3,0,true)",[base.id]);
      const store = new CreatureResearchStore(db);
      await expect(store.unlock(userId,"early-tame","creature_training")).rejects.toThrow("SKILL_PREREQUISITE_MISSING");
      expect(await store.unlock(userId,"research-track","tracking")).toEqual({skillId:"tracking",unlocked:true,experience:0});
      // Same request ID cannot deduct materials twice, even through a new store instance.
      const recovered = new CreatureResearchStore(db);
      expect(await recovered.unlock(userId,"research-track","tracking")).toEqual({skillId:"tracking",unlocked:true,experience:0});
      await expect(recovered.unlock(userId,"research-track","animal_handling")).rejects.toThrow("PROGRESSION_REQUEST_CONFLICT");
      await store.unlock(userId,"research-handle","animal_handling");
      await store.unlock(userId,"research-train","creature_training");
      const inv = await db.query<{inventory:Record<string,number>}>("SELECT inventory FROM player_profiles WHERE user_id=$1",[userId]);
      expect(inv.rows[0]?.inventory).toMatchObject({"resource.herb":4,"resource.wood":16,"resource.stone":20});
      expect(await store.awardPlayerPractice(userId,"event-player1","creature_training",20)).toMatchObject({experience:20});
      expect(await recovered.awardPlayerPractice(userId,"event-player1","creature_training",20)).toMatchObject({experience:20});
      await expect(store.awardPlayerPractice(userId,"event-player1","creature_training",30)).rejects.toThrow("PROGRESSION_REQUEST_CONFLICT");
      const creatureIdResult = await db.query<{id:string}>(
        "INSERT INTO player_creatures(owner_user_id,wild_source_id,species,level,xp,health,max_health,attack,defense,element,ability_ids,tame_progress,party_slot,ai_mode,x,y) VALUES($1,$2,'slime',1,0,45,45,18,2,'water','[]'::jsonb,100,NULL,'follow',1,1) RETURNING id",
        [userId,`research-${randomUUID()}`],
      );
      const creatureId = creatureIdResult.rows[0].id;
      expect(await store.awardCreatureTraining(userId,"event-creature1",creatureId,30)).toEqual({creatureId,experience:30,bond:42});
      expect(await recovered.awardCreatureTraining(userId,"event-creature1",creatureId,30)).toEqual({creatureId,experience:30,bond:42});
      expect(await store.awardCreatureTraining(userId,"event-creature2",creatureId,30)).toEqual({creatureId,experience:60,bond:44});
      const actual = await db.query<{experience:number;bond:number}>("SELECT experience,bond FROM creature_training_progress WHERE creature_id=$1",[creatureId]);
      expect(actual.rows[0]).toMatchObject({experience:60,bond:44});
      const intruder = await register();
      await db.query("INSERT INTO player_profiles(user_id) VALUES($1) ON CONFLICT(user_id) DO NOTHING",[intruder]);
      await db.query("INSERT INTO player_creature_skills(user_id,skill_id,experience) VALUES($1,'creature_training',0)",[intruder]);
      await expect(store.awardCreatureTraining(intruder,"event-intruder",creatureId,10)).rejects.toThrow("CREATURE_NOT_FOUND");
    } finally { await db.end(); }
  });
  it("rolls back a failed research deduction without creating an event or skill", async () => {
    const db = createDbPool();
    try {
      const userId = await register();
      await db.query("INSERT INTO player_profiles(user_id,inventory) VALUES($1,'{}'::jsonb) ON CONFLICT(user_id) DO UPDATE SET inventory='{}'::jsonb",[userId]);
      await new BaseStore(db).create(userId,"No Materials",0,0);
      const store = new CreatureResearchStore(db);
      await expect(store.unlock(userId,"missing-materials","tracking")).rejects.toThrow("INSUFFICIENT_INVENTORY");
      const remaining=await db.query<{count:string}>("SELECT COUNT(*)::text AS count FROM creature_progression_requests WHERE user_id=$1",[userId]);
      expect(Number(remaining.rows[0]?.count)).toBe(0);
      const skills=await db.query<{count:string}>("SELECT COUNT(*)::text AS count FROM player_creature_skills WHERE user_id=$1",[userId]);
      expect(Number(skills.rows[0]?.count)).toBe(0);
    } finally { await db.end(); }
  });
});
