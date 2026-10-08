import {describe,expect,it} from "vitest";
import type {FastifyInstance} from "fastify";
import {buildApp} from "./app.js";
import {createDbPool} from "./db.js";
import {BaseStore} from "./base.js";
import {PlayerStore} from "./player.js";
import {GuildStore} from "./guild.js";
import {ShipStore} from "./ship.js";
import {ShipInventoryStore} from "./ship-inventory.js";

async function register(app:FastifyInstance,tag:string):Promise<string>{
  const unique=tag+"_"+Date.now().toString(36)+"_"+Math.random().toString(36).slice(2,6);
  const response=await app.inject({method:"POST",url:"/auth/register",payload:{username:unique,email:unique+"@example.com",password:"Correct-Horse-Battery-9"}});
  expect(response.statusCode).toBe(201);
  return (JSON.parse(response.body) as {user:{id:string}}).user.id;
}

describe("PDF §92/§93 base storage durability",()=>{
  it("replays the same storage mutation after application restart and rejects request conflicts",async()=>{
    const db=createDbPool();
    const app=await buildApp({db});
    try{
      const userId=await register(app,"base_storage");
      await new PlayerStore(db).loadOrCreate(userId);
      const bases=new BaseStore(db);
      const base=await bases.create(userId,"Storage Base",0,0);
      await db.query("UPDATE player_profiles SET inventory=jsonb_build_object('wood',100) WHERE user_id=$1",[userId]);

      const first=await bases.mutateStorage(userId,{wood:10},"base-storage-replay","storage|wood|10");
      expect(first.transactionId).toMatch(/^[0-9a-f-]{36}$/i);
      expect(first.storage.wood).toBe(510);

      await app.close();
      const restarted=new BaseStore(db);
      const replay=await restarted.mutateStorage(userId,{wood:10},"base-storage-replay","storage|wood|10");
      expect(replay).toEqual(first);

      await expect(restarted.mutateStorage(userId,{wood:5},"base-storage-replay","storage|wood|5")).rejects.toThrow("BASE_STORAGE_REQUEST_CONFLICT");

      const profile=await db.query<{inventory:Record<string,number>}>("SELECT inventory FROM player_profiles WHERE user_id=$1",[userId]);
      const stored=await db.query<{quantity:string}>("SELECT quantity FROM base_storage WHERE base_id=$1 AND resource_key='wood'",[base.id]);
      expect(profile.rows[0]?.inventory.wood).toBe(90);
      expect(stored.rows[0]?.quantity).toBe("510");

      const ledger=await db.query<{transaction_id:string;response:{transactionId:string;storage:Record<string,number>}}>("SELECT transaction_id,response FROM base_storage_requests WHERE request_key=$1",[userId+":base-storage-replay"]);
      expect(ledger.rows[0]?.transaction_id).toBe(first.transactionId);
      expect(ledger.rows[0]?.response.transactionId).toBe(first.transactionId);

      const second=await restarted.mutateStorage(userId,{wood:5},"base-storage-second","storage|wood|5");
      expect(second.transactionId).not.toBe(first.transactionId);
      expect(second.storage.wood).toBe(515);
    }finally{
      if(app.server.listening)await app.close();
      await db.end();
    }
  });
});


describe("PDF §92/§93 request ID persistence bounds",()=>{
  it("rejects oversized request IDs before guild, ship, or base mutation",async()=>{
    const db=createDbPool();
    const app=await buildApp({db});
    const oversized="x".repeat(65);
    try{
      const userId=await register(app,"request_id_bounds");
      await new PlayerStore(db).loadOrCreate(userId);

      const bases=new BaseStore(db);
      const base=await bases.create(userId,"Bounds Base",0,0);
      await db.query("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'guild_hall',1,1,0,true)",[base.id]);
      await db.query("UPDATE player_profiles SET inventory=jsonb_build_object('wood',10),gold=100 WHERE user_id=$1",[userId]);

      const guilds=new GuildStore(db);
      const guild=await guilds.create(userId,"Bounds Guild","BND");
      await expect(guilds.bankDeposit(userId,guild.id,"wood",1,"1",oversized,"guild_bank_deposit|wood|1|1")).rejects.toThrow("INVALID_REQUEST_ID");
      const guildProfile=await db.query<{inventory:Record<string,number>;gold:string}>("SELECT inventory,gold FROM player_profiles WHERE user_id=$1",[userId]);
      expect(guildProfile.rows[0]?.inventory.wood).toBe(10);
      expect(guildProfile.rows[0]?.gold).toBe("100");
      const guildLedger=await db.query<{count:string}>("SELECT COUNT(*)::text AS count FROM guild_bank_requests WHERE request_key LIKE $1",[userId+":%"]);
      expect(guildLedger.rows[0]?.count).toBe("0");

      const ships=new ShipStore(db);
      const ship=await ships.create(userId,"Bounds Sloop","sloop");
      const inventory=new ShipInventoryStore(db);
      await expect(inventory.mutate(userId,ship.id,"wood",1,oversized,"ship_cargo|wood|1")).rejects.toThrow("INVALID_REQUEST_ID");
      const shipLedger=await db.query<{count:string}>("SELECT COUNT(*)::text AS count FROM ship_cargo_requests WHERE request_key LIKE $1",[userId+":%"]);
      expect(shipLedger.rows[0]?.count).toBe("0");
      const shipInventory=await db.query<{count:string}>("SELECT COUNT(*)::text AS count FROM ship_inventory WHERE ship_id=$1",[ship.id]);
      expect(shipInventory.rows[0]?.count).toBe("0");

      await expect(bases.mutateStorage(userId,{wood:10},oversized,"storage|wood|10")).rejects.toThrow("INVALID_REQUEST_ID");
      const baseLedger=await db.query<{count:string}>("SELECT COUNT(*)::text AS count FROM base_storage_requests WHERE request_key LIKE $1",[userId+":%"]);
      expect(baseLedger.rows[0]?.count).toBe("0");
      const stored=await db.query<{count:string}>("SELECT COUNT(*)::text AS count FROM base_storage WHERE base_id=$1",[base.id]);
      expect(stored.rows[0]?.count).toBe("0");
    }finally{
      if(app.server.listening)await app.close();
      await db.end();
    }
  });
});
