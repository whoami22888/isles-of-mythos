import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { PlayerStore } from "./player.js";
import { WorldEventCoordinator } from "./world-events.js";

async function users(){
  const db=createDbPool();const app=await buildApp({db});
  const create=async(prefix:string)=>{
    const id=randomUUID().replace(/-/g,"").slice(0,20);
    const r=await app.inject({method:"POST",url:"/auth/register",payload:{username:prefix+"_"+id,email:prefix+"_"+id+"@example.com",password:"Correct-Horse-Battery-9"}});
    expect(r.statusCode).toBe(201);
    const user=(JSON.parse(r.body) as {user:{id:string}}).user.id;
    await new PlayerStore(db).loadOrCreate(user);
    return user;
  };
  return {db,app,a:await create("events_a"),b:await create("events_b")};
}

describe("Gate 15 world event authority",()=>{
  it("aggregates contributions globally and persists event effects",async()=>{
    const {db,app,a,b}=await users();
    try{
      const players=new PlayerStore(db);await players.loadOrCreate(a);await players.loadOrCreate(b);
      const events=new WorldEventCoordinator(db,(userId)=>players.get(userId)?.level);
      const event=await events.spawn("kraken",null,100,-50);
      expect(event.status).toBe("active");
      expect((await db.query("SELECT effect_key FROM world_event_effects WHERE event_id=$1",[event.id])).rows).toEqual([{effect_key:"kraken_hazard_active"}]);
      const first=await events.contribute(a,event.id);expect(first.currentHealth).toBe("9999990");
      const second=await events.contribute(b,event.id);expect(second.currentHealth).toBe("9999980");
      expect((await db.query<{contribution:string}>("SELECT contribution FROM world_event_contributions WHERE event_id=$1 ORDER BY user_id",[event.id])).rows).toHaveLength(2);
    }finally{await app.close();await db.end();}
  });

  it("settles server-side rewards once and rejects concurrent duplicate claims",async()=>{
    const {db,app,a}=await users();
    try{
      const players=new PlayerStore(db);await players.loadOrCreate(a);
      const events=new WorldEventCoordinator(db,(userId)=>players.get(userId)?.level);
      const event=await events.spawn("treasure_storm",null,0,0);
      await events.contribute(a,event.id);
      await db.query("UPDATE world_events SET ends_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[event.id]);
      expect(await events.tick()).toBeGreaterThanOrEqual(1);
      const claims=await Promise.allSettled([events.claimReward(a,event.id),events.claimReward(a,event.id)]);
      expect(claims.filter(x=>x.status==="fulfilled")).toHaveLength(1);
      expect(claims.filter(x=>x.status==="rejected")).toHaveLength(1);
      const reward=await events.rewards(a,event.id);expect(reward?.claimed).toBe(true);
      const row=await db.query<{gold:string}>("SELECT gold FROM player_profiles WHERE user_id=$1",[a]);
      expect(BigInt(row.rows[0].gold)).toBe(1000n);
    }finally{await app.close();await db.end();}
  });
});
