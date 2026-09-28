import { describe, expect, it, vi } from "vitest";
import { WebSocket } from "ws";
import { buildApp } from "./app.js";
import { calculateDamage, createCombatTarget, weaponFor } from "./combat.js";
import { CreatureStore } from "./creature.js";
import { parseClientMessage } from "./protocol.js";

type Obj=Record<string,unknown>;
const isObj=(v:unknown):v is Obj=>typeof v==="object"&&v!==null&&!Array.isArray(v);
const getObj=(v:Obj,k:string):Obj=>{const x=v[k];if(!isObj(x))throw new Error("Expected object");return x;};
const getStr=(v:Obj,k:string)=>{const x=v[k];if(typeof x!=="string")throw new Error("Expected string");return x;};
function wait(socket:WebSocket,p:(v:unknown)=>boolean):Promise<unknown>{
  return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{socket.off("message",on);reject(new Error("Timed out waiting for creature message"));},3000);
    const on=(raw:Buffer)=>{let v:unknown;try{v=JSON.parse(raw.toString());}catch { return; }if(!p(v))return;clearTimeout(timer);socket.off("message",on);resolve(v);};socket.on("message",on);});
}
async function socketFor(app:Awaited<ReturnType<typeof buildApp>>){await app.listen({host:"127.0.0.1",port:0});const a=app.server.address();if(!a||typeof a==="string")throw new Error("No test address");return new WebSocket(`ws://127.0.0.1:${a.port}/ws`);}
describe("creature foundation",()=>{
  it("parses authoritative creature commands",()=>{
    expect(parseClientMessage('{"type":"capture","requestId":"c1","targetId":"creature:1:2"}')).toEqual({type:"capture",requestId:"c1",targetId:"creature:1:2"});
    expect(parseClientMessage('{"type":"tame","requestId":"t1","creatureId":"bad"}')).toEqual({type:"tame",requestId:"t1",creatureId:"bad"});
    expect(parseClientMessage('{"type":"set_creature_party","requestId":"p1","creatureId":"bad","slot":2}')).toEqual({type:"set_creature_party",requestId:"p1",creatureId:"bad",slot:2});
    expect(parseClientMessage('{"type":"set_creature_party","requestId":"p1","creatureId":"bad","slot":3}')).toBeNull();
    expect(parseClientMessage('{"type":"set_creature_ai","requestId":"a1","creatureId":"bad","mode":"follow"}')).toEqual({type:"set_creature_ai",requestId:"a1",creatureId:"bad",mode:"follow"});
  });
  it("captures, tames, parties and persists a wild creature server-side",async()=>{
    const app=await buildApp(); const unique=Date.now(); const randomSpy=vi.spyOn(Math,"random").mockReturnValue(0.99);
    const reg=await app.inject({method:"POST",url:"/auth/register",payload:{username:`creature_${unique}`,email:`creature_${unique}@example.com`,password:"Correct-Horse-Battery-9"}});
    expect(reg.statusCode).toBe(201); const body=JSON.parse(reg.body) as Obj; const token=getStr(body,"accessToken"); const userId=getStr(getObj(body,"user"),"id");
    const cutlass=weaponFor("cutlass"); if(!cutlass)throw new Error("Missing cutlass test weapon");
    let spawn:Obj|null=null; let targetMaxHealth=0; let targetHits=Number.POSITIVE_INFINITY;
    for(let y=0;y<8;y++)for(let x=0;x<8;x++){const r=await app.inject({method:"GET",url:`/world/chunks/${x}/${y}`});const c=JSON.parse(r.body) as Obj;const list=c.creatures;
      if(!Array.isArray(list))continue;
      for(const candidate of list){if(!isObj(candidate))continue;const id=candidate.id;const species=candidate.species;const sx=Number(candidate.x),sy=Number(candidate.y),level=Number(candidate.level);
        if(typeof id!=="string"||typeof species!=="string"||!Number.isFinite(sx)||!Number.isFinite(sy)||!Number.isFinite(level))continue;
        const target=createCombatTarget(id,species,sx,sy,level); const damage=calculateDamage(cutlass,target,0.99).amount; const hits=Math.ceil((target.maxHealth*0.75)/damage);
        const preferred=species==="slime"||species==="boar"; const currentPreferred=spawn?((getStr(spawn,"species")==="slime"||getStr(spawn,"species")==="boar")):false;
        if(hits<=6&&(!spawn|| (preferred&&!currentPreferred)|| (preferred===currentPreferred&&(hits<targetHits||(hits===targetHits&&target.maxHealth<targetMaxHealth))))){spawn=candidate;targetMaxHealth=target.maxHealth;targetHits=hits;}
      }
    }
    if(!spawn)throw new Error("No deterministic creature can reach the capture threshold within six cutlass hits"); const targetId=getStr(spawn,"id"); const tx=Number(spawn.x),ty=Number(spawn.y);
    const db=(await import("./db.js")).createDbPool();
    await db.query(
      "INSERT INTO player_profiles (user_id,x,y,health,defense,inventory,hotbar,selected_hotbar_slot) VALUES ($1,$2,$3,100,5,$4::jsonb,'[\"cutlass\",\"flintlock\",null,null,null,null,null,null]'::jsonb,0) ON CONFLICT (user_id) DO UPDATE SET x=EXCLUDED.x,y=EXCLUDED.y,health=EXCLUDED.health,defense=EXCLUDED.defense,inventory=EXCLUDED.inventory,hotbar=EXCLUDED.hotbar,selected_hotbar_slot=EXCLUDED.selected_hotbar_slot",
      [userId,tx-0.5,ty,JSON.stringify({"ammo.flintlock":30,"capture.orb":3,"creature.feed":4})],
    );
    const socket=await socketFor(app);
    try{
      await new Promise<void>((res,rej)=>{socket.once("open",()=>res());socket.once("error",rej);});
      const auth=wait(socket,v=>isObj(v)&&v.type==="auth_ok"); const state=wait(socket,v=>isObj(v)&&v.type==="player_state");
      socket.send(JSON.stringify({type:"auth",token})); await auth; await state;
      for(let i=0;i<6;i++){
        const requestId="hit-"+i;
        let response:Obj;
        for(let attempt=0;;attempt++){
          const hit=wait(socket,v=>isObj(v)&&((v.type==="combat_result"&&v.requestId===requestId)||(v.type==="error")));
          socket.send(JSON.stringify({type:"attack",requestId,targetId,facingX:1,facingY:0}));
          const candidate=await hit as Obj;
          if(candidate.type!=="error"){response=candidate;break;}
          const code=getStr(candidate,"code");
          if(code==="PLAYER_STUNNED"&&attempt<3){await new Promise(r=>setTimeout(r,800));continue;}
          throw new Error("Attack "+requestId+" rejected: "+code);
        }
        const result=response; const hpValue=result.targetHealth;
        if(typeof hpValue!=="number")throw new Error("Missing target health");
        if(result.killed===true)throw new Error("Creature was killed before capture threshold");
        if(hpValue<=targetMaxHealth*0.25)break;
        if(i===5)throw new Error(`Creature was not reduced to capture threshold (health=${hpValue}, max=${targetMaxHealth}, expectedHits=${targetHits})`);
        await new Promise(r=>setTimeout(r,500));
      }
      const captureResponse=wait(socket,v=>isObj(v)&&((v.type==="creature_state"&&v.requestId==="cap-1")||v.type==="error"));
      socket.send(JSON.stringify({type:"capture",requestId:"cap-1",targetId}));
      const captureMessage=await captureResponse as Obj;
      if(captureMessage.type==="error")throw new Error("Capture rejected: "+getStr(captureMessage,"code"));
      const creature=getObj(captureMessage,"creature"); const creatureId=getStr(creature,"id");
      const inventoryAfterCapture=await db.query<{ capture_orbs: string | null }>("SELECT inventory->>'capture.orb' AS capture_orbs FROM player_profiles WHERE user_id=$1",[userId]); expect(Number(inventoryAfterCapture.rows[0]?.capture_orbs)).toBe(2);
      expect(creature.species).toBe(getStr(spawn,"species")); expect(creature.tameProgress).toBe(0);
      const tameProgress:number[]=[];
      for(let i=0;i<4;i++){const t=wait(socket,v=>isObj(v)&&v.type==="creature_state"&&v.requestId===`t-${i}`);socket.send(JSON.stringify({type:"tame",requestId:`t-${i}`,creatureId}));const m=await t;tameProgress.push(Number(getObj(m as Obj,"creature").tameProgress));}
      expect(tameProgress).toEqual([25,50,75,100]);
      const party=wait(socket,v=>isObj(v)&&v.type==="creature_party");const partyState=wait(socket,v=>isObj(v)&&v.type==="creature_state"&&v.requestId==="party-1");socket.send(JSON.stringify({type:"set_creature_party",requestId:"party-1",creatureId,slot:0}));await partyState;const partyMessage=await party;expect(Array.isArray((partyMessage as Obj).creatures)).toBe(true);
      const ai=wait(socket,v=>isObj(v)&&v.type==="creature_state"&&v.requestId==="ai-1");socket.send(JSON.stringify({type:"set_creature_ai",requestId:"ai-1",creatureId,mode:"stay"}));const aiMessage=await ai;expect(getObj(aiMessage as Obj,"creature").aiMode).toBe("stay");
      socket.close();
      await new Promise<void>((resolve)=>socket.once("close",()=>resolve()));
      let persistedRow:Obj|null=null;
      for(let attempt=0;attempt<20;attempt++){
        const persisted=await db.query("SELECT tame_progress,party_slot,ai_mode FROM player_creatures WHERE id=$1",[creatureId]);
        const row=persisted.rows[0] as Obj|undefined;
        if(row){persistedRow=row;if(row.tame_progress===100&&row.party_slot===0&&row.ai_mode==="stay")break;}
        await new Promise(r=>setTimeout(r,50));
      }
      expect(persistedRow).toMatchObject({tame_progress:100,party_slot:0,ai_mode:"stay"});
    }finally{socket.close();randomSpy.mockRestore();await db.end();await app.close();}
  });
  it("deduplicates concurrent tame requests and consumes one feed",async()=>{
    const app=await buildApp(); const unique=Date.now();
    const reg=await app.inject({method:"POST",url:"/auth/register",payload:{username:`tame_retry_${unique}`,email:`tame_retry_${unique}@example.com`,password:"Correct-Horse-Battery-9"}});
    expect(reg.statusCode).toBe(201); const body=JSON.parse(reg.body) as Obj; const token=getStr(body,"accessToken"); const userId=getStr(getObj(body,"user"),"id");
    const db=(await import("./db.js")).createDbPool();
    try{
      await db.query(
        "INSERT INTO player_profiles (user_id,inventory,hotbar,selected_hotbar_slot) VALUES ($1,$2::jsonb,'[\"cutlass\",null,null,null,null,null,null,null]'::jsonb,0) ON CONFLICT (user_id) DO UPDATE SET inventory=EXCLUDED.inventory,hotbar=EXCLUDED.hotbar,selected_hotbar_slot=EXCLUDED.selected_hotbar_slot",
        [userId,JSON.stringify({"capture.orb":0,"creature.feed":4})],
      );
      const inserted=await db.query<{id:string}>(
        "INSERT INTO player_creatures(owner_user_id,wild_source_id,species,level,xp,health,max_health,attack,defense,element,ability_ids,tame_progress,party_slot,ai_mode,x,y) VALUES($1,$2,'slime',1,0,45,45,18,2,'water','[]'::jsonb,0,NULL,'follow',1,1) RETURNING id",
        [userId,`tame-retry-${unique}`],
      );
      const creatureId=inserted.rows[0]?.id; if(!creatureId)throw new Error("Missing creature id");
      const socket=await socketFor(app);
      try{
        await new Promise<void>((res,rej)=>{socket.once("open",()=>res());socket.once("error",rej);});
        const auth=wait(socket,v=>isObj(v)&&v.type==="auth_ok"); const state=wait(socket,v=>isObj(v)&&v.type==="player_state");
        socket.send(JSON.stringify({type:"auth",token})); await auth; await state;
        const responses:Obj[]=[];
        const responsePromise=new Promise<void>((resolve,reject)=>{
          const timer=setTimeout(()=>reject(new Error("Timed out waiting for duplicate tame responses")),3000);
          const on=(raw:Buffer)=>{
            let v:unknown;try{v=JSON.parse(raw.toString());}catch{return;}
            if(!isObj(v)||v.type!=="creature_state"||v.requestId!=="dup-tame")return;
            responses.push(v);
            if(responses.length===2){clearTimeout(timer);socket.off("message",on);resolve();}
          };
          socket.on("message",on);
        });
        const payload=JSON.stringify({type:"tame",requestId:"dup-tame",creatureId});
        socket.send(payload); socket.send(payload);
        await responsePromise;
        expect(responses.every((response)=>Number(getObj(response,"creature").tameProgress)===25)).toBe(true);
        const inventory=await db.query<{feeds:string|null}>("SELECT inventory->>'creature.feed' AS feeds FROM player_profiles WHERE user_id=$1",[userId]);
        expect(Number(inventory.rows[0]?.feeds)).toBe(3);
      }finally{socket.close();await new Promise<void>((resolve)=>socket.once("close",()=>resolve()));}
    }finally{await db.end();await app.close();}
  });

  it("does not respawn a captured world source after server restart",async()=>{
    const app=await buildApp(); const unique=Date.now();
    const reg=await app.inject({method:"POST",url:"/auth/register",payload:{username:`restart_${unique}`,email:`restart_${unique}@example.com`,password:"Correct-Horse-Battery-9"}});
    expect(reg.statusCode).toBe(201); const userId=getStr(getObj(JSON.parse(reg.body) as Obj,"user"),"id");
    let spawn:Obj|null=null; let chunkX=0; let chunkY=0;
    for(let y=0;y<8&&!spawn;y++)for(let x=0;x<8&&!spawn;x++){
      const response=await app.inject({method:"GET",url:`/world/chunks/${x}/${y}`}); const chunk=JSON.parse(response.body) as Obj; const creatures=chunk.creatures;
      if(Array.isArray(creatures)){const candidate=creatures.find(isObj);if(candidate){spawn=candidate;chunkX=x;chunkY=y;}}
    }
    if(!spawn)throw new Error("No deterministic world creature available");
    const db=(await import("./db.js")).createDbPool();
    try{
      await db.query(
        "INSERT INTO player_creatures(owner_user_id,wild_source_id,species,level,xp,health,max_health,attack,defense,element,ability_ids,tame_progress,party_slot,ai_mode,x,y) VALUES($1,$2,$3,1,0,45,45,18,2,'water','[]'::jsonb,0,NULL,'follow',$4,$5)",
        [userId,getStr(spawn,"id"),getStr(spawn,"species"),Number(spawn.x),Number(spawn.y)],
      );
    }finally{await app.close();}
    const restarted=await buildApp();
    try{
      const response=await restarted.inject({method:"GET",url:`/world/chunks/${chunkX}/${chunkY}`});
      expect(response.statusCode).toBe(200);
      const chunk=JSON.parse(response.body) as Obj; const creatures=chunk.creatures;
      expect(Array.isArray(creatures)).toBe(true);
      expect((creatures as unknown[]).some((value)=>isObj(value)&&value.id===spawn?.id)).toBe(false);
    }finally{await db.end();await restarted.close();}
  });

  it("rejects cross-account creature mutation",async()=>{
    const app=await buildApp(); const unique=Date.now();
    const registrations=await Promise.all([
      app.inject({method:"POST",url:"/auth/register",payload:{username:`owner_${unique}`,email:`owner_${unique}@example.com`,password:"Correct-Horse-Battery-9"}}),
      app.inject({method:"POST",url:"/auth/register",payload:{username:`intruder_${unique}`,email:`intruder_${unique}@example.com`,password:"Correct-Horse-Battery-9"}}),
    ]);
    expect(registrations.every((response)=>response.statusCode===201)).toBe(true);
    const ownerId=getStr(getObj(JSON.parse(registrations[0]?.body??"{}") as Obj,"user"),"id");
    const intruderId=getStr(getObj(JSON.parse(registrations[1]?.body??"{}") as Obj,"user"),"id");
    const db=(await import("./db.js")).createDbPool();
    try{
      await db.query(
        "INSERT INTO player_profiles (user_id,inventory,hotbar,selected_hotbar_slot) VALUES ($1,$3::jsonb,'["cutlass",null,null,null,null,null,null,null]'::jsonb,0),($2,$3::jsonb,'["cutlass",null,null,null,null,null,null,null]'::jsonb,0)",
        [ownerId,intruderId,JSON.stringify({"capture.orb":0,"creature.feed":4})],
      );
      const inserted=await db.query<{id:string}>(
        "INSERT INTO player_creatures(owner_user_id,wild_source_id,species,level,xp,health,max_health,attack,defense,element,ability_ids,tame_progress,party_slot,ai_mode,x,y) VALUES($1,$2,'slime',1,0,45,45,18,2,'water','[]'::jsonb,25,NULL,'follow',1,1) RETURNING id",
        [ownerId,`ownership-${unique}`],
      );
      const creatureId=inserted.rows[0]?.id; if(!creatureId)throw new Error("Missing creature id");
      const store=new CreatureStore(db); await store.load(intruderId);
      await expect(store.tame(intruderId,creatureId)).rejects.toThrow("CREATURE_NOT_FOUND");
      await expect(store.setPartySlot(intruderId,creatureId,0)).rejects.toThrow("CREATURE_NOT_FOUND");
      expect(()=>store.setAiMode(intruderId,creatureId,"stay")).toThrow("CREATURE_NOT_FOUND");
      const row=await db.query<{feeds:string|null;tame_progress:number}>("SELECT (SELECT inventory->>'creature.feed' FROM player_profiles WHERE user_id=$1) AS feeds,tame_progress FROM player_creatures WHERE id=$2",[intruderId,creatureId]);
      expect(row.rows[0]?.feeds).toBe("4");
      expect(row.rows[0]?.tame_progress).toBe(25);
    }finally{await db.end();await app.close();}
  });

  it("rejects concurrent capture of one wild spawn across owners",async()=>{
    const app=await buildApp(); const unique=Date.now();
    const registrations=await Promise.all([
      app.inject({method:"POST",url:"/auth/register",payload:{username:"capture_a_"+unique,email:"capture_a_"+unique+"@example.com",password:"Correct-Horse-Battery-9"}}),
      app.inject({method:"POST",url:"/auth/register",payload:{username:"capture_b_"+unique,email:"capture_b_"+unique+"@example.com",password:"Correct-Horse-Battery-9"}}),
    ]);
    expect(registrations.every((response)=>response.statusCode===201)).toBe(true);
    const userIds=registrations.map((response)=>getStr(getObj(JSON.parse(response.body) as Obj,"user"),"id"));
    const db=(await import("./db.js")).createDbPool();
    try{
      await db.query("INSERT INTO player_profiles (user_id,inventory,hotbar,selected_hotbar_slot) VALUES ($1,$3::jsonb,'[\"cutlass\",null,null,null,null,null,null,null]'::jsonb,0),($2,$3::jsonb,'[\"cutlass\",null,null,null,null,null,null,null]'::jsonb,0)",[userIds[0],userIds[1],JSON.stringify({"capture.orb":1,"creature.feed":0})]);
      const target=createCombatTarget("creature:concurrent-test","slime",1,1,1);
      const first=new CreatureStore(db); const second=new CreatureStore(db);
      const results=await Promise.allSettled([first.capture(userIds[0],target),second.capture(userIds[1],target)]);
      expect(results.filter((result)=>result.status==="fulfilled")).toHaveLength(1);
      const rejected=results.find((result)=>result.status==="rejected");
      expect(rejected&&rejected.reason instanceof Error?rejected.reason.message:rejected).toBe("CREATURE_ALREADY_CAPTURED");
      const ownership=await db.query<{count:string}>("SELECT COUNT(*)::text AS count FROM player_creatures WHERE wild_source_id=$1",[target.id]);
      expect(Number(ownership.rows[0]?.count)).toBe(1);
    }finally{await db.end();await app.close();}
  });
});
