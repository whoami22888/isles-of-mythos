import {describe,expect,it} from "vitest";
import type {FastifyInstance} from "fastify";
import {buildApp} from "./app.js";
import {createDbPool} from "./db.js";
import {BaseStore} from "./base.js";

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
      const bases=new BaseStore(db);
      const base=await bases.create(userId,"Storage Base",0,0);
      await db.query("UPDATE player_profiles SET inventory=jsonb_build_object('wood',100) WHERE user_id=$1",[userId]);

      const first=await bases.mutateStorage(userId,{wood:10},"base-storage-replay","storage|wood|10");
      expect(first.transactionId).toMatch(/^[0-9a-f-]{36}$/i);
      expect(first.storage.wood).toBe(10);

      await app.close();
      const restarted=new BaseStore(db);
      const replay=await restarted.mutateStorage(userId,{wood:10},"base-storage-replay","storage|wood|10");
      expect(replay).toEqual(first);

      await expect(restarted.mutateStorage(userId,{wood:5},"base-storage-replay","storage|wood|5")).rejects.toThrow("BASE_STORAGE_REQUEST_CONFLICT");

      const profile=await db.query<{inventory:Record<string,number>}>("SELECT inventory FROM player_profiles WHERE user_id=$1",[userId]);
      const stored=await db.query<{quantity:string}>("SELECT quantity FROM base_storage WHERE base_id=$1 AND resource_key='wood'",[base.id]);
      expect(profile.rows[0]?.inventory.wood).toBe(90);
      expect(stored.rows[0]?.quantity).toBe("10");

      const ledger=await db.query<{transaction_id:string;response:{transactionId:string;storage:Record<string,number>}}>("SELECT transaction_id,response FROM base_storage_requests WHERE request_key=$1",[userId+":base-storage-replay"]);
      expect(ledger.rows[0]?.transaction_id).toBe(first.transactionId);
      expect(ledger.rows[0]?.response.transactionId).toBe(first.transactionId);

      const second=await restarted.mutateStorage(userId,{wood:5},"base-storage-second","storage|wood|5");
      expect(second.transactionId).not.toBe(first.transactionId);
      expect(second.storage.wood).toBe(15);
    }finally{
      if(app.server.listening)await app.close();
      await db.end();
    }
  });
});
