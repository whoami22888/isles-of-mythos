import {describe,expect,it} from "vitest";
import type {FastifyInstance} from "fastify";
import type {Pool} from "pg";
import {buildApp} from "./app.js";
import {createDbPool} from "./db.js";
import {BaseStore} from "./base.js";
import {ShipStore,SHIP_CLASSES,CANNONBALL_ITEM} from "./ship.js";

async function register(app:FastifyInstance,tag:string):Promise<string>{
  const unique=Date.now()+"_"+tag+"_"+Math.random().toString(36).slice(2,8);
  const response=await app.inject({method:"POST",url:"/auth/register",payload:{username:"ship_"+unique,email:"ship_"+unique+"@example.com",password:"Correct-Horse-Battery-9"}});
  expect(response.statusCode).toBe(201);
  return (JSON.parse(response.body) as {user:{id:string}}).user.id;
}

async function baseFixture(db:Pool,userId:string):Promise<{baseId:string;shipyardId:string}>{
  const bases=new BaseStore(db);const base=await bases.create(userId,"Shipyard Base",0,0);
  await db.query("INSERT INTO base_storage(base_id,resource_key,quantity) VALUES($1,'steel',100) ON CONFLICT(base_id,resource_key) DO UPDATE SET quantity=EXCLUDED.quantity",[base.id]);
  const pen=await db.query<{id:string}>("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'shipyard',1,1,0,true) RETURNING id",[base.id]);
  return {baseId:base.id,shipyardId:pen.rows[0].id};
}

describe("Gate 9 ships",()=>{
  it("defines all authoritative ship classes",()=>{expect(Object.keys(SHIP_CLASSES)).toHaveLength(9);expect(SHIP_CLASSES.galleon.crew).toBe(25);expect(SHIP_CLASSES.ancient_warship.cannons).toBe(40);});
  it("creates a ship through a shipyard, seeds cannon inventory, and persists sailing",async()=>{
    const app=await buildApp();const db=createDbPool();try{
      const user=await register(app,"create");const f=await baseFixture(db,user);const store=new ShipStore(db);
      const ship=await store.create(user,"Sea Wraith","sloop");
      expect(ship.shipClass).toBe("sloop");expect(ship.hull).toBe(SHIP_CLASSES.sloop.hull);
      const inventory=await store.inventory(user,ship.id);expect(inventory.find(i=>i.itemId===CANNONBALL_ITEM)?.quantity).toBe(8);
      const moved=await store.sail(user,ship.id,1,0,10);expect(moved.x).toBeGreaterThan(0);expect(moved.fuel).toBeLessThan(ship.fuel);
      const persisted=await store.list(user);expect(persisted[0]?.x).toBe(moved.x);expect(f.baseId).toBeTruthy();
    }finally{await db.end();await app.close();}
  });
  it("assigns a creature crew member and resolves transactional naval cannon damage",async()=>{
    const app=await buildApp();const db=createDbPool();try{
      const attackerUser=await register(app,"attacker"),defenderUser=await register(app,"defender");
      await baseFixture(db,attackerUser);await baseFixture(db,defenderUser);
      const attackerStore=new ShipStore(db),defenderStore=new ShipStore(db);
      const attacker=await attackerStore.create(attackerUser,"Black Tide","sloop");
      const defender=await defenderStore.create(defenderUser,"Red Wake","raft");
      const creature=await db.query<{id:string}>(`INSERT INTO player_creatures(owner_user_id,wild_source_id,species,level,xp,health,max_health,attack,defense,element,ability_ids,tame_progress,party_slot,ai_mode,x,y,genetics,generation) VALUES($1,$2,'boar',1,0,70,70,10,5,'earth','[]'::jsonb,100,NULL,'follow',0,0,'{}'::jsonb,0) RETURNING id`,[attackerUser,"ship-crew-"+Date.now()]);
      const crew=await attackerStore.assignCrew(attackerUser,attacker.id,creature.rows[0].id,"gunner",50,100);expect(crew.role).toBe("gunner");
      const result=await attackerStore.fireCannon(attackerUser,attacker.id,defender.id);expect(result.damage).toBeGreaterThan(0);expect(result.target.hull).toBeLessThan(defender.hull);
      await expect(attackerStore.fireCannon(attackerUser,attacker.id,defender.id)).rejects.toThrow("CANNON_COOLDOWN");
    }finally{await db.end();await app.close();}
  });
});
