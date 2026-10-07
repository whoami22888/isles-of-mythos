import {describe,expect,it} from "vitest";
import type {Pool} from "pg";
import type {FastifyInstance} from "fastify";
import {buildApp} from "./app.js";
import {createDbPool} from "./db.js";
import {BaseStore} from "./base.js";
import {ArmyStore} from "./army.js";
import {PlayerStore} from "./player.js";

async function register(app:FastifyInstance,label:string){
  const unique="army_"+label+"_"+Date.now().toString(36).slice(-5)+"_"+Math.random().toString(36).slice(2,4);
  const r=await app.inject({method:"POST",url:"/auth/register",payload:{username:unique,email:unique+"@example.com",password:"Correct-Horse-Battery-9"}});
  expect(r.statusCode).toBe(201);return (JSON.parse(r.body) as {user:{id:string}}).user.id;
}
async function fixture(db:Pool,userId:string){
  const bases=new BaseStore(db);const b=await bases.create(userId,"Army Base",0,0);
  await db.query("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'barracks',1,1,0,true)",[b.id]);
  await db.query("INSERT INTO base_storage(base_id,resource_key,quantity) VALUES($1,'steel',1000) ON CONFLICT(base_id,resource_key) DO UPDATE SET quantity=EXCLUDED.quantity",[b.id]);
  return b.id;
}
describe("Gate 11 tactical armies",()=>{
  it("persists armies, training, formations, garrison, defense and server battle resolution",async()=>{
    const db=createDbPool();const app=await buildApp({db});
    try{
      const user=await register(app,"owner");await new PlayerStore(db).loadOrCreate(user);const baseId=await fixture(db,user);const armies=new ArmyStore(db);
      const a=await armies.create(user,"Defenders"),b=await armies.create(user,"Raiders");
      expect(a.units).toHaveLength(0);
      const q=await armies.train(user,a.id,"pirate_infantry",10);expect(q.queueId).toBeTruthy();
      await db.query("UPDATE army_training_queue SET completes_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[q.queueId]);
      const trained=await armies.get(user,a.id);expect(trained.units[0]?.quantity).toBe(10);
      await armies.garrison(user,a.id,baseId);await armies.assignment(user,a.id,"garrison");
      const formation=await armies.formation(user,a.id,"Line","line",{slots:[0,1,2]});expect(formation.activeFormation?.formationType).toBe("line");
      const defense=await armies.defense(user,baseId,"spike_trap",2,2);expect(defense.type).toBe("spike_trap");
      await db.query("INSERT INTO army_units(army_id,unit_type,category,quantity,health,max_health,attack,defense,range,speed,ability_ids) VALUES($1,'pirate_infantry','infantry',5,500,500,14,12,1,3,'[\"shield_wall\"]'::jsonb)",[b.id]);
      const battle=await armies.battleCreate(user,a.id,b.id,5,5);expect(battle.status).toBe("active");
      await armies.deploy(user,battle.id,trained.units[0]?.id ?? (()=>{throw new Error("TRAINED_UNIT_MISSING")})(),0);
      const enemy=await db.query<{id:string}>("SELECT id FROM army_units WHERE army_id=$1",[b.id]);const enemyId=enemy.rows[0]?.id;if(!enemyId)throw new Error("ENEMY_UNIT_MISSING");
      await armies.deploy(user,battle.id,enemyId,1);
      const acted=await armies.action(user,battle.id,trained.units[0]?.id ?? (()=>{throw new Error("TRAINED_UNIT_MISSING")})(),"ability",enemyId);expect(acted.turn).toBe(1);
      const after=await armies.turn(user,battle.id);expect(after.turn).toBeGreaterThan(1);
      const reloaded=await armies.get(user,a.id);expect(reloaded.garrisonBaseIds).toContain(baseId);
    }finally{await db.end();if(app.server.listening)await app.close();}
  });
});
