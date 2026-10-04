import {describe,expect,it} from "vitest";
import type {FastifyInstance} from "fastify";
import {buildApp} from "./app.js";
import {createDbPool} from "./db.js";
import {PlayerStore} from "./player.js";
import {BaseStore} from "./base.js";
import {InvasionStore} from "./invasion.js";

async function register(app:FastifyInstance){
 const id="inv_"+Date.now().toString(36)+"_"+Math.random().toString(36).slice(2,6);
 const r=await app.inject({method:"POST",url:"/auth/register",payload:{username:id,email:id+"@example.com",password:"Correct-Horse-Battery-9"}});
 expect(r.statusCode).toBe(201);return (JSON.parse(r.body) as {user:{id:string}}).user.id;
}
describe("Gate 13 invasion persistence",()=>{
 it("creates, joins, advances, resolves and rewards a persistent invasion",async()=>{
  const app=await buildApp();const db=createDbPool();
  try{
   const user=await register(app);await new PlayerStore(db).loadOrCreate(user);
   const base=await new BaseStore(db).create(user,"Invasion Base",-100,0);
   await db.query("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'barracks',1,1,0,true)",[base.id]);
   const army=await db.query<{id:string}>("INSERT INTO armies(owner_user_id,name) VALUES($1,'Invasion Guard') RETURNING id",[user]);
   await db.query("INSERT INTO army_units(army_id,unit_type,category,quantity,health,max_health,attack,defense,range,speed,ability_ids) VALUES($1,'pirate_infantry','infantry',1000,100000,100000,1000,1000,1,3,'[]'::jsonb)",[army.rows[0].id]);
   const db2=createDbPool();try{
    const invasionStore=new InvasionStore(db2);
    const territory=(await db2.query<{id:string}>("SELECT id FROM territories WHERE name='Sunken Coast'")).rows[0];expect(territory).toBeTruthy();
    const invasion=await invasionStore.create(user,territory.id,"npc_realm",5000);
    expect(invasion.phase).toBe("WARNING");
    await invasionStore.join(user,invasion.id,army.rows[0].id);
    await db2.query("UPDATE invasions SET phase='ARRIVAL',phase_started_at=CURRENT_TIMESTAMP-INTERVAL '60 seconds',phase_ends_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[invasion.id]);
    await invasionStore.tick();
    expect((await invasionStore.waves(invasion.id)).length).toBeGreaterThan(0);
    await db2.query("UPDATE invasions SET phase='BATTLE',phase_started_at=CURRENT_TIMESTAMP-INTERVAL '120 seconds',phase_ends_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[invasion.id]);
    await invasionStore.tick();
    const resolution=(await invasionStore.list(territory.id))[0];expect(resolution.phase).toBe("RESOLUTION");
    await db2.query("UPDATE invasions SET phase_ends_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[invasion.id]);await invasionStore.tick();
    const reward=(await invasionStore.list(territory.id))[0];expect(reward.phase).toBe("REWARD");
    await db2.query("UPDATE invasions SET phase_ends_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[invasion.id]);await invasionStore.tick();
    const cooldown=(await invasionStore.list(territory.id))[0];expect(cooldown.phase).toBe("COOLDOWN");
    const rewards=await db2.query("SELECT gold,triumph_badges FROM invasion_rewards WHERE invasion_id=$1 AND user_id=$2",[invasion.id,user]);expect(rewards.rows).toHaveLength(1);expect(BigInt(rewards.rows[0].gold)).toBeGreaterThan(0n);
   }finally{await db2.end();}
  }finally{await db.end();if(app.server.listening)await app.close();}
 });
});