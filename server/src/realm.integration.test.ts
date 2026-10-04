import {describe,expect,it} from "vitest";
import type {FastifyInstance} from "fastify";
import {buildApp} from "./app.js";
import {createDbPool} from "./db.js";
import {BaseStore} from "./base.js";
import {PlayerStore} from "./player.js";
import {GuildStore} from "./guild.js";
import {ArmyStore} from "./army.js";
import {RealmStore} from "./realm.js";

async function register(app:FastifyInstance){
 const id="realm_"+Date.now().toString(36)+"_"+Math.random().toString(36).slice(2,5);
 const r=await app.inject({method:"POST",url:"/auth/register",payload:{username:id,email:id+"@example.com",password:"Correct-Horse-Battery-9"}});
 expect(r.statusCode).toBe(201);return (JSON.parse(r.body) as {user:{id:string}}).user.id;
}
describe("Gate 12 realms",()=>{
 it("persists realms, territory ownership, routes, reputation and AI state",async()=>{
  const app=await buildApp();const db=createDbPool();
  try{
   const user=await register(app);await new PlayerStore(db).loadOrCreate(user);
   const base=await new BaseStore(db).create(user,"Realm Base",-100,0);
   await db.query("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'guild_hall',1,1,0,true),($1,'barracks',1,2,0,true)",[base.id]);
   const guild=new GuildStore(db);const g=await guild.create(user,"Realm Wardens","REALM");
   const army=new ArmyStore(db);const a=await army.create(user,"Territory Guard");
   await db.query("INSERT INTO army_units(army_id,unit_type,category,quantity,health,max_health,attack,defense,range,speed,ability_ids) VALUES($1,'pirate_infantry','infantry',1,100,100,1500,100,1,3,'[]'::jsonb)",[a.id]);
   await army.garrison(user,a.id,base.id);
   const realms=new RealmStore(db);const all=await realms.list();expect(all).toHaveLength(6);
   const territory=await realms.territoryAt(-100,0);expect(territory?.name).toBe("Sunken Coast");
   await realms.claimGuildTerritory(user,territory!.id,g.id);
   const owned=(await realms.territories()).find(x=>x.id===territory!.id);expect(owned?.guild_owner_id).toBe(g.id);expect(owned?.realm_owner_id).toBeNull();
   const rep=await realms.reputation(user,"Sunken Kingdom",750);expect(rep.tier).toBe("respected");
   const territories=await realms.territories();const destination=territories.find(x=>x.id!==territory!.id)!;
   const route=await realms.createTradeRoute(user,territory!.id,destination.id,"iron","1000",60,g.id,null);expect(route).toBeTruthy();
   expect((await realms.routes()).some(x=>x.id===route)).toBe(true);
   await realms.tickAI();
   expect((await realms.list()).every(x=>BigInt(x.economy)>=0n&&BigInt(x.military_strength)>=0n)).toBe(true);
  }finally{await db.end();if(app.server.listening)await app.close();}
 });
});
