import { randomInt } from "node:crypto";
import type { Pool, PoolClient } from "pg";
import { applyInventoryDelta, cloneInventory, parseGoldDoubloons } from "./economy.js";

export type WorldEventType = "world_boss"|"treasure_storm"|"ghost_fleet"|"kraken"|"dragon_migration";
export type WorldEventStatus = "active"|"completed"|"expired";

export interface WorldEventSummary {
  id:string; eventType:WorldEventType; status:WorldEventStatus; regionId:number|null;
  centerX:number; centerY:number; maxHealth:string|null; currentHealth:string|null;
  state:Record<string,unknown>; startedAt:string; endsAt:string;
}
interface EventRow {
  id:string; event_type:WorldEventType; status:WorldEventStatus; region_id:number|null;
  center_x:number; center_y:number; max_health:string|null; current_health:string|null;
  state:Record<string,unknown>; started_at:Date; ends_at:Date;
}
const EVENT_TYPES:WorldEventType[]=["world_boss","treasure_storm","ghost_fleet","kraken","dragon_migration"];
const EVENT_DURATION_MS=15*60_000;
const SPAWN_INTERVAL_MS=10*60_000;

function durationFor(type:WorldEventType):number{
  if(type==="treasure_storm") return 10*60_000;
  if(type==="dragon_migration") return 20*60_000;
  return EVENT_DURATION_MS;
}
function bossHealth(type:WorldEventType):bigint|null{
  if(type==="world_boss") return 5_000_000n;
  if(type==="kraken") return 10_000_000n;
  return null;
}
function eventState(type:WorldEventType):Record<string,unknown>{
  if(type==="world_boss") return {boss:"world_titan",phase:1,environment:"storm"};
  if(type==="kraken") return {boss:"kraken",phase:1,environment:"ocean_storm"};
  if(type==="dragon_migration") return {species:"sky_dragon",migrationPath:"regional",spawnMultiplier:3};
  if(type==="ghost_fleet") return {fleet:"spectral_armada",encounters:0};
  return {treasureMapMultiplier:3};
}
function effectFor(type:WorldEventType):{key:string;value:Record<string,unknown>}{
  if(type==="treasure_storm") return {key:"treasure_map_find_multiplier",value:{multiplier:3}};
  if(type==="ghost_fleet") return {key:"ghost_fleet_active",value:{active:true}};
  if(type==="kraken") return {key:"kraken_hazard_active",value:{active:true}};
  if(type==="dragon_migration") return {key:"dragon_migration_spawn_multiplier",value:{multiplier:3}};
  return {key:"world_boss_active",value:{active:true}};
}
function toSummary(row:EventRow):WorldEventSummary{
  return {id:row.id,eventType:row.event_type,status:row.status,regionId:row.region_id,centerX:row.center_x,centerY:row.center_y,
    maxHealth:row.max_health,currentHealth:row.current_health,state:row.state,startedAt:row.started_at.toISOString(),endsAt:row.ends_at.toISOString()};
}
function rewardFor(type:WorldEventType,contribution:bigint,rank:number):{gold:bigint;items:Record<string,number>}{
  const base=contribution>0n?BigInt(Math.min(250_000,Math.max(100,rank===1?5_000:1_000))):0n;
  if(type==="treasure_storm") return {gold:base,items:{"resource.pearl":Math.max(1,rank===1?3:1)}};
  if(type==="ghost_fleet") return {gold:base+2_000n,items:{"resource.ancient-relics":Math.max(1,rank===1?2:1)}};
  if(type==="dragon_migration") return {gold:base+3_000n,items:{"resource.dragon-scales":Math.max(1,rank===1?3:1)}};
  if(type==="kraken") return {gold:base+5_000n,items:{"resource.mermaid-pearls":Math.max(1,rank===1?3:1)}};
  return {gold:base+4_000n,items:{"resource.ancient-relics":Math.max(1,rank===1?3:1)}};
}

export class WorldEventCoordinator {
  constructor(private readonly db:Pool, private readonly playerLevel:(userId:string)=>number|undefined){}

  async listActive():Promise<WorldEventSummary[]>{
    const r=await this.db.query<EventRow>("SELECT id,event_type,status,region_id,center_x,center_y,max_health,current_health,state,started_at,ends_at FROM world_events WHERE status='active' ORDER BY started_at DESC");
    return r.rows.map(toSummary);
  }

  async spawn(type:WorldEventType, regionId:number|null, centerX:number, centerY:number):Promise<WorldEventSummary>{
    if(!EVENT_TYPES.includes(type)) throw new Error("INVALID_WORLD_EVENT_TYPE");
    const duration=durationFor(type), health=bossHealth(type), effect=effectFor(type);
    const seed=BigInt(randomInt(1,2_000_000_000));
    const r=await this.db.query<EventRow>(
      "INSERT INTO world_events(event_type,region_id,center_x,center_y,max_health,current_health,state,seed,ends_at) VALUES($1,$2,$3,$4,$5,$5,$6::jsonb,$7,CURRENT_TIMESTAMP+($8::bigint*INTERVAL '1 millisecond')) RETURNING id,event_type,status,region_id,center_x,center_y,max_health,current_health,state,started_at,ends_at",
      [type,regionId,centerX,centerY,health?.toString()??null,JSON.stringify(eventState(type)),seed.toString(),duration]);
    if(!r.rows[0]) throw new Error("WORLD_EVENT_CREATE_FAILED");
    await this.db.query("INSERT INTO world_event_effects(event_id,effect_key,effect_value,expires_at) VALUES($1,$2,$3::jsonb,CURRENT_TIMESTAMP+($4::bigint*INTERVAL '1 millisecond'))",[r.rows[0].id,effect.key,JSON.stringify(effect.value),duration]);
    return toSummary(r.rows[0]);
  }

  async contribute(userId:string,eventId:string):Promise<WorldEventSummary>{
    const client=await this.db.connect();
    try{
      await client.query("BEGIN");
      await client.query("SELECT pg_advisory_xact_lock(15015)");
      const event=await client.query<EventRow>("SELECT id,event_type,status,region_id,center_x,center_y,max_health,current_health,state,started_at,ends_at FROM world_events WHERE id=$1 FOR UPDATE",[eventId]);
      const row=event.rows[0]; if(!row) throw new Error("WORLD_EVENT_NOT_FOUND");
      if(row.status!=="active" || row.ends_at.getTime()<=Date.now()) throw new Error("WORLD_EVENT_NOT_ACTIVE");
      const level=this.playerLevel(userId); if(level===undefined) throw new Error("PLAYER_NOT_LOADED");
      const prior=await client.query<{last_contributed_at:Date}>("SELECT last_contributed_at FROM world_event_contributions WHERE event_id=$1 AND user_id=$2 FOR UPDATE",[eventId,userId]);
      if(prior.rows[0] && Date.now()-prior.rows[0].last_contributed_at.getTime()<2_000) throw new Error("WORLD_EVENT_RATE_LIMITED");
      const contribution=Math.max(1,Math.min(1000,level*10));
      await client.query("INSERT INTO world_event_contributions(event_id,user_id,contribution,actions) VALUES($1,$2,$3,1) ON CONFLICT(event_id,user_id) DO UPDATE SET contribution=world_event_contributions.contribution+EXCLUDED.contribution,actions=world_event_contributions.actions+1,last_contributed_at=CURRENT_TIMESTAMP",[eventId,userId,contribution]);
      if(row.max_health!==null && row.current_health!==null){
        const rawNext=BigInt(row.current_health)-BigInt(contribution); const next=rawNext>0n?rawNext:0n;
        await client.query("UPDATE world_events SET current_health=$2,state=jsonb_set(state,'{phase}',to_jsonb(GREATEST(1,LEAST(5,1+FLOOR((1.0-($2::numeric/$3::numeric))*5)))),true),updated_at=CURRENT_TIMESTAMP WHERE id=$1",[eventId,next.toString(),row.max_health]);
        if(next===0n) await this.completeLocked(client,eventId);
      }
      const updated=await client.query<EventRow>("SELECT id,event_type,status,region_id,center_x,center_y,max_health,current_health,state,started_at,ends_at FROM world_events WHERE id=$1",[eventId]);
      await client.query("COMMIT");
      if(!updated.rows[0]) throw new Error("WORLD_EVENT_NOT_FOUND");
      return toSummary(updated.rows[0]);
    }catch(e){await client.query("ROLLBACK");throw e}finally{client.release()}
  }

  private async completeLocked(client:PoolClient,eventId:string):Promise<void>{
    const event=await client.query<EventRow>("SELECT id,event_type,status,region_id,center_x,center_y,max_health,current_health,state,started_at,ends_at FROM world_events WHERE id=$1 FOR UPDATE",[eventId]);
    const row=event.rows[0]; if(!row || row.status!=="active") return;
    const contributions=await client.query<{user_id:string;contribution:string}>("SELECT user_id,contribution FROM world_event_contributions WHERE event_id=$1 AND contribution>0 ORDER BY contribution DESC,user_id",[eventId]);
    for(let i=0;i<contributions.rows.length;i++){
      const c=contributions.rows[i], reward=rewardFor(row.event_type,BigInt(c.contribution),i+1);
      await client.query("INSERT INTO world_event_rewards(event_id,user_id,reward) VALUES($1,$2,$3::jsonb) ON CONFLICT(event_id,user_id) DO NOTHING",[eventId,c.user_id,JSON.stringify({gold:reward.gold.toString(),items:reward.items})]);
    }
    await client.query("UPDATE world_events SET status='completed',completed_at=CURRENT_TIMESTAMP,current_health=0,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[eventId]);
  }

  async tick():Promise<number>{
    const client=await this.db.connect();let changed=0;
    try{
      await client.query("BEGIN");
      const due=await client.query<{id:string;event_type:WorldEventType}>("SELECT id,event_type FROM world_events WHERE status='active' AND ends_at<=CURRENT_TIMESTAMP ORDER BY ends_at,id FOR UPDATE SKIP LOCKED");
      for(const row of due.rows){
        const event=await client.query<{max_health:string|null;current_health:string|null}>("SELECT max_health,current_health FROM world_events WHERE id=$1 FOR UPDATE",[row.id]);
        if(event.rows[0]?.max_health!==null && event.rows[0]?.current_health==="0") await this.completeLocked(client,row.id);
        else {
          const contributors=await client.query<{user_id:string;contribution:string}>("SELECT user_id,contribution FROM world_event_contributions WHERE event_id=$1 AND contribution>0 ORDER BY contribution DESC,user_id",[row.id]);
          for(let i=0;i<contributors.rows.length;i++){
            const reward=rewardFor(row.event_type,BigInt(contributors.rows[i].contribution),i+1);
            await client.query("INSERT INTO world_event_rewards(event_id,user_id,reward) VALUES($1,$2,$3::jsonb) ON CONFLICT(event_id,user_id) DO NOTHING",[row.id,contributors.rows[i].user_id,JSON.stringify({gold:reward.gold.toString(),items:reward.items})]);
          }
          await client.query("UPDATE world_events SET status='expired',completed_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[row.id]);
        }
        changed++;
      }
      await client.query("SELECT pg_advisory_xact_lock(15015)");
      const latest=await client.query<{created_at:Date}>("SELECT created_at FROM world_events ORDER BY created_at DESC LIMIT 1");
      const last=latest.rows[0]?.created_at?.getTime()??0;
      if(Date.now()-last>=SPAWN_INTERVAL_MS){
        const type=EVENT_TYPES[randomInt(0,EVENT_TYPES.length)];
        const x=randomInt(-500,501),y=randomInt(-500,501);
        const duration=durationFor(type),health=bossHealth(type);
        const seed=BigInt(randomInt(1,2_000_000_000));
        const effect=effectFor(type);
        const inserted=await client.query<{id:string}>("INSERT INTO world_events(event_type,region_id,center_x,center_y,max_health,current_health,state,seed,ends_at) VALUES($1,$2,$3,$4,$5,$5,$6::jsonb,$7,CURRENT_TIMESTAMP+($8::bigint*INTERVAL '1 millisecond')) RETURNING id",[type,null,x,y,health?.toString()??null,JSON.stringify(eventState(type)),seed.toString(),duration]);
        if(inserted.rows[0]) await client.query("INSERT INTO world_event_effects(event_id,effect_key,effect_value,expires_at) VALUES($1,$2,$3::jsonb,CURRENT_TIMESTAMP+($4::bigint*INTERVAL '1 millisecond'))",[inserted.rows[0].id,effect.key,JSON.stringify(effect.value),duration]);
        changed++;
      }
      await client.query("DELETE FROM world_event_effects WHERE expires_at<=CURRENT_TIMESTAMP");
      await client.query("COMMIT"); return changed;
    }catch(e){await client.query("ROLLBACK");throw e}finally{client.release()}
  }

  async rewards(userId:string,eventId:string):Promise<{gold:string;items:Record<string,number>;claimed:boolean}|null>{
    const r=await this.db.query<{reward:{gold:string;items:Record<string,number>};claimed_at:Date|null}>("SELECT reward,claimed_at FROM world_event_rewards WHERE event_id=$1 AND user_id=$2",[eventId,userId]);
    const row=r.rows[0]; return row?{gold:row.reward.gold,items:row.reward.items,claimed:row.claimed_at!==null}:null;
  }

  async claimReward(userId:string,eventId:string):Promise<{gold:string;items:Record<string,number>}>{
    const client=await this.db.connect();
    try{
      await client.query("BEGIN");
      const reward=await client.query<{reward:{gold:string;items:Record<string,number>};claimed_at:Date|null}>("SELECT reward,claimed_at FROM world_event_rewards WHERE event_id=$1 AND user_id=$2 FOR UPDATE",[eventId,userId]);
      const row=reward.rows[0]; if(!row) throw new Error("WORLD_EVENT_REWARD_NOT_FOUND"); if(row.claimed_at) throw new Error("WORLD_EVENT_REWARD_ALREADY_CLAIMED");
      const profile=await client.query<{gold:string;inventory:Record<string,number>}>("SELECT gold,inventory FROM player_profiles WHERE user_id=$1 FOR UPDATE",[userId]);
      if(!profile.rows[0]) throw new Error("PLAYER_NOT_FOUND");
      const gold=parseGoldDoubloons(profile.rows[0].gold)+BigInt(row.reward.gold);
      let inventory=cloneInventory(profile.rows[0].inventory); for(const [itemId,quantity] of Object.entries(row.reward.items)) inventory=applyInventoryDelta(inventory,itemId,quantity);
      await client.query("UPDATE player_profiles SET gold=$2,inventory=$3::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[userId,gold.toString(),JSON.stringify(inventory)]);
      await client.query("UPDATE world_event_rewards SET claimed_at=CURRENT_TIMESTAMP WHERE event_id=$1 AND user_id=$2",[eventId,userId]);
      await client.query("COMMIT");
      return {gold:row.reward.gold,items:row.reward.items};
    }catch(e){await client.query("ROLLBACK");throw e}finally{client.release()}
  }
}
