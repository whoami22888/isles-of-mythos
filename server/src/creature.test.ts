import { describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { buildApp } from "./app.js";
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
    const app=await buildApp(); const unique=Date.now();
    const reg=await app.inject({method:"POST",url:"/auth/register",payload:{username:`creature_${unique}`,email:`creature_${unique}@example.com`,password:"Correct-Horse-Battery-9"}});
    expect(reg.statusCode).toBe(201); const body=JSON.parse(reg.body) as Obj; const token=getStr(body,"accessToken"); const userId=getStr(getObj(body,"user"),"id");
    let spawn:Obj|null=null;
    for(let y=0;y<8&&!spawn;y++)for(let x=0;x<8&&!spawn;x++){const r=await app.inject({method:"GET",url:`/world/chunks/${x}/${y}`});const c=JSON.parse(r.body) as Obj;const list=c.creatures;if(Array.isArray(list)){const found=list.find(isObj);if(found)spawn=found;}}
    if(!spawn)throw new Error("No deterministic creature spawn"); const targetId=getStr(spawn,"id"); const tx=Number(spawn.x),ty=Number(spawn.y);
    const db=(await import("./db.js")).createDbPool();
    await db.query(
      "INSERT INTO player_profiles (user_id,x,y,health,inventory,hotbar,selected_hotbar_slot) VALUES ($1,$2,$3,100,$4::jsonb,'[\"cutlass\",\"flintlock\",null,null,null,null,null,null]'::jsonb,0) ON CONFLICT (user_id) DO UPDATE SET x=EXCLUDED.x,y=EXCLUDED.y,health=EXCLUDED.health,inventory=EXCLUDED.inventory,hotbar=EXCLUDED.hotbar,selected_hotbar_slot=EXCLUDED.selected_hotbar_slot",
      [userId,tx-0.5,ty,JSON.stringify({"ammo.flintlock":30,"capture.orb":3,"creature.feed":4})],
    );
    const socket=await socketFor(app);
    try{
      await new Promise<void>((res,rej)=>{socket.once("open",()=>res());socket.once("error",rej);});
      const auth=wait(socket,v=>isObj(v)&&v.type==="auth_ok"); const state=wait(socket,v=>isObj(v)&&v.type==="player_state");
      socket.send(JSON.stringify({type:"auth",token})); await auth; await state;
      for(let i=0;i<6;i++){
        const requestId="hit-"+i;
        const hit=wait(socket,v=>isObj(v)&&((v.type==="combat_result"&&v.requestId===requestId)||(v.type==="error")));
        socket.send(JSON.stringify({type:"attack",requestId,targetId,facingX:1,facingY:0}));
        const response=await hit as Obj;
        if(response.type==="error") throw new Error("Attack "+requestId+" rejected: "+getStr(response,"code"));
        const result=response;
        const hpValue=result.targetHealth;
        if(typeof hpValue!=="number")throw new Error("Missing target health");
        if(hpValue<=Number(spawn.health)*0.25)break;
        await new Promise(r=>setTimeout(r,500));
        if(i===5)throw new Error("Creature was not reduced to capture threshold");
      }
      const captured=wait(socket,v=>isObj(v)&&v.type==="creature_state"&&v.requestId==="cap-1");
      socket.send(JSON.stringify({type:"capture",requestId:"cap-1",targetId}));
      const capturedMessage=await captured; const creature=getObj(capturedMessage as Obj,"creature"); const creatureId=getStr(creature,"id"); const inventoryAfterCapture=await db.query<{ capture_orbs: string | null }>("SELECT inventory->>'capture.orb' AS capture_orbs FROM player_profiles WHERE user_id=$1",[userId]); expect(Number(inventoryAfterCapture.rows[0]?.capture_orbs)).toBe(2);
      expect(creature.species).toBe(getStr(spawn,"species")); expect(creature.tameProgress).toBe(0);
      const tameProgress:number[]=[];
      for(let i=0;i<4;i++){const t=wait(socket,v=>isObj(v)&&v.type==="creature_state"&&v.requestId===`t-${i}`);socket.send(JSON.stringify({type:"tame",requestId:`t-${i}`,creatureId}));const m=await t;tameProgress.push(Number(getObj(m as Obj,"creature").tameProgress));}
      expect(tameProgress).toEqual([25,50,75,100]);
      const party=wait(socket,v=>isObj(v)&&v.type==="creature_party");const partyState=wait(socket,v=>isObj(v)&&v.type==="creature_state"&&v.requestId==="party-1");socket.send(JSON.stringify({type:"set_creature_party",requestId:"party-1",creatureId,slot:0}));await partyState;const partyMessage=await party;expect(Array.isArray((partyMessage as Obj).creatures)).toBe(true);
      const ai=wait(socket,v=>isObj(v)&&v.type==="creature_state"&&v.requestId==="ai-1");socket.send(JSON.stringify({type:"set_creature_ai",requestId:"ai-1",creatureId,mode:"stay"}));const aiMessage=await ai;expect(getObj(aiMessage as Obj,"creature").aiMode).toBe("stay");
      socket.close();
      await new Promise<void>((resolve)=>socket.once("close",()=>resolve()));
      const persisted=await db.query("SELECT tame_progress,party_slot,ai_mode FROM player_creatures WHERE id=$1",[creatureId]);
      expect(persisted.rows[0]).toMatchObject({tame_progress:100,party_slot:0,ai_mode:"stay"});
    }finally{socket.close();await db.end();await app.close();}
  });
});
