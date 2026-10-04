import {describe,expect,it} from "vitest";
import type {FastifyInstance} from "fastify";
import {buildApp} from "./app.js";
import {createDbPool} from "./db.js";
import {BaseStore} from "./base.js";
import {BreedingStore} from "./breeding.js";

async function register(app:FastifyInstance,tag:string):Promise<string>{
  const unique=Date.now()+"_"+tag;
  const response=await app.inject({method:"POST",url:"/auth/register",payload:{username:"breed_"+unique,email:"breed_"+unique+"@example.com",password:"Correct-Horse-Battery-9"}});
  expect(response.statusCode).toBe(201);
  return (JSON.parse(response.body) as {user:{id:string}}).user.id;
}

async function fixture(){
  const app=await buildApp();
  const userId=await register(app,"fixture");
  const db=createDbPool();
  const bases=new BaseStore(db);
  const base=await bases.create(userId,"Breeding Test Base",0,0);
  const pen=await db.query<{id:string}>("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'breeding_pen',1,1,0,true) RETURNING id",[base.id]);
  await db.query("UPDATE player_bases SET maximum_creatures=10,maximum_breeding_slots=1 WHERE id=$1",[base.id]);
  await db.query("UPDATE player_profiles SET inventory=COALESCE(inventory,'{}'::jsonb) || '{\"creature.feed\":10}'::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[userId]);
  const feed=await db.query<{value:string|null}>("SELECT inventory->>'creature.feed' AS value FROM player_profiles WHERE user_id=$1",[userId]);
  expect(feed.rows[0]?.value).toBe("10");
  const parents=await db.query<{id:string}>(`
    INSERT INTO player_creatures(owner_user_id,wild_source_id,species,level,xp,health,max_health,attack,defense,element,ability_ids,tame_progress,party_slot,ai_mode,x,y,genetics,generation)
    VALUES
      ($1,$2,'slime',1,0,45,45,10,2,'water','["acid_burst"]'::jsonb,100,NULL,'follow',0,0,$3::jsonb,0),
      ($1,$4,'boar',1,0,70,70,11,5,'earth','["charge"]'::jsonb,100,NULL,'follow',1,0,$5::jsonb,0)
    RETURNING id
  `,[userId,"breed-parent-a-"+Date.now(),JSON.stringify({element:"water",strength:10,speed:1.4,workEfficiency:1,carryCapacity:1,abilityPotential:1,rarityPotential:10,cosmeticTraits:["stripe"]}),"breed-parent-b-"+Date.now(),JSON.stringify({element:"earth",strength:11,speed:2.1,workEfficiency:1.1,carryCapacity:1.2,abilityPotential:1,rarityPotential:20,cosmeticTraits:["horn"]})]);
  return {app,db,userId,baseId:base.id,penId:pen.rows[0].id,parentA:parents.rows[0].id,parentB:parents.rows[1].id};
}

describe("Gate 8 breeding persistence",()=>{
  it("creates an active job atomically and consumes feed",async()=>{
    const f=await fixture();try{
      const store=new BreedingStore(f.db);const job=await store.start(f.userId,f.baseId,f.penId,f.parentA,f.parentB,60_000);
      expect(job.status).toBe("active");
      const row=await f.db.query<{feed:string;count:string}>("SELECT inventory->>'creature.feed' feed,(SELECT COUNT(*)::text FROM breeding_jobs WHERE owner_user_id=$1 AND status='active') count FROM player_profiles WHERE user_id=$1",[f.userId]);
      expect(row.rows[0]?.feed).toBe("9");expect(row.rows[0]?.count).toBe("1");
    }finally{await f.db.end();await f.app.close();}
  });

  it("serializes concurrent starts against one pen",async()=>{
    const f=await fixture();try{
      const a=new BreedingStore(f.db),b=new BreedingStore(f.db);
      const results=await Promise.allSettled([a.start(f.userId,f.baseId,f.penId,f.parentA,f.parentB,60_000),b.start(f.userId,f.baseId,f.penId,f.parentA,f.parentB,60_000)]);
      expect(results.filter(x=>x.status==="fulfilled")).toHaveLength(1);
      expect(results.filter(x=>x.status==="rejected")).toHaveLength(1);
      const jobs=await f.db.query<{count:string}>("SELECT COUNT(*)::text count FROM breeding_jobs WHERE owner_user_id=$1 AND status='active'",[f.userId]);
      expect(jobs.rows[0]?.count).toBe("1");
    }finally{await f.db.end();await f.app.close();}
  });

  it("completes persisted jobs into lineage-linked offspring",async()=>{
    const f=await fixture();try{
      const store=new BreedingStore(f.db);const job=await store.start(f.userId,f.baseId,f.penId,f.parentA,f.parentB,1);
      const completed=await store.completeDue(new Date(job.completesAt+1));
      expect(completed).toBe(1);
      const row=await f.db.query<{status:string;offspring_id:string;generation:number;parent_a_id:string;parent_b_id:string}>("SELECT status,offspring_id,(SELECT generation FROM player_creatures WHERE id=breeding_jobs.offspring_id) generation,parent_a_id,parent_b_id FROM breeding_jobs WHERE id=$1",[job.id]);
      expect(row.rows[0]?.status).toBe("completed");expect(row.rows[0]?.offspring_id).toBeTruthy();expect(row.rows[0]?.generation).toBe(1);expect(row.rows[0]?.parent_a_id).toBe(f.parentA);expect(row.rows[0]?.parent_b_id).toBe(f.parentB);
      const child=await f.db.query<{parent_a_id:string;parent_b_id:string;genetics:unknown}>("SELECT parent_a_id,parent_b_id,genetics FROM player_creatures WHERE id=$1",[row.rows[0]?.offspring_id]);
      expect(child.rows[0]?.parent_a_id).toBe(f.parentA);expect(child.rows[0]?.parent_b_id).toBe(f.parentB);expect(child.rows[0]?.genetics).toBeTruthy();
    }finally{await f.db.end();await f.app.close();}
  });
});
