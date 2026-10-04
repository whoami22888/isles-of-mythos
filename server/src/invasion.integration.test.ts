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
    await invasionStore.join(user,invasion.id,army.rows[0].id,"tank");
    const participant=await db2.query<{role:string}>("SELECT role FROM invasion_participants WHERE invasion_id=$1 AND user_id=$2",[invasion.id,user]);
    expect(participant.rows[0]?.role).toBe("tank");
    await db2.query("UPDATE invasions SET phase='ARRIVAL',phase_started_at=CURRENT_TIMESTAMP-INTERVAL '60 seconds',phase_ends_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[invasion.id]);
    await Promise.all([invasionStore.tick(),new InvasionStore(db2).tick()]);
    const wavesAfterArrival=await invasionStore.waves(invasion.id);
    expect(wavesAfterArrival.length).toBeGreaterThan(0);
    expect(wavesAfterArrival[0]?.aggro_range).toBeGreaterThan(0);
    await db2.query("INSERT INTO base_defensive_structures(base_id,structure_type,grid_x,grid_y,health,max_health,ammo,active) VALUES($1,'cannon_tower',2,0,500,500,10,true)",[base.id]);
    const beforeBattleHealth=wavesAfterArrival[0]?.current_health??0;
    await db2.query("UPDATE invasions SET phase='BATTLE',phase_started_at=CURRENT_TIMESTAMP-INTERVAL '120 seconds',phase_ends_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[invasion.id]);
    await invasionStore.tick();
    const battleDefense=await db2.query<{ammo:number}>("SELECT ammo FROM base_defensive_structures WHERE base_id=$1 AND structure_type='cannon_tower'",[base.id]);
    expect(battleDefense.rows[0]?.ammo).toBe(9);
    const afterBattle=await invasionStore.waves(invasion.id);
    expect(afterBattle[0]?.current_health??beforeBattleHealth).toBeLessThan(beforeBattleHealth);
    const resolution=(await invasionStore.list(territory.id))[0];expect(resolution.phase).toBe("RESOLUTION");
    await db2.query("UPDATE invasions SET phase_ends_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[invasion.id]);await invasionStore.tick();
    const reward=(await invasionStore.list(territory.id))[0];expect(reward.phase).toBe("REWARD");
    await db2.query("UPDATE invasions SET phase_ends_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[invasion.id]);await invasionStore.tick();
    const cooldown=(await invasionStore.list(territory.id))[0];expect(cooldown.phase).toBe("COOLDOWN");
    await db2.query("UPDATE invasion_schedules SET next_run_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE territory_id=$1",[territory.id]);
    await invasionStore.tick();
    expect((await invasionStore.list(territory.id)).length).toBe(1);
    const rewards=await db2.query<{gold:string;triumph_badges:string}>(
     "SELECT gold,triumph_badges FROM invasion_rewards WHERE invasion_id=$1 AND user_id=$2",
     [invasion.id,user],
    );
    expect(rewards.rows).toHaveLength(1);
    expect(BigInt(rewards.rows[0]?.gold??"0")).toBeGreaterThan(0n);
    const inventory=await db2.query<{inventory:Record<string,number>}>("SELECT inventory FROM player_profiles WHERE user_id=$1",[user]);
    expect(inventory.rows[0]?.inventory["resource.wood"]).toBeGreaterThan(0);
    expect(inventory.rows[0]?.inventory["resource.steel"]).toBeGreaterThan(0);
    expect(inventory.rows[0]?.inventory["treasure.map.high-tier"]).toBeGreaterThan(0);
   }finally{await db2.end();}
  }finally{await db.end();if(app.server.listening)await app.close();}
 });
});