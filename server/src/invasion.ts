import type {Pool,PoolClient} from "pg";

export const INVASION_PHASES=["WARNING","MUSTER","ARRIVAL","ASSAULT","BATTLE","RESOLUTION","REWARD","COOLDOWN","COMPLETE"] as const;
export type InvasionPhase=typeof INVASION_PHASES[number];
export const INVASION_SOURCES=["npc_realm","ancient_monster","pirate_fleet","dragon_army","undead_fleet","sea_monster","rival_faction"] as const;
export type InvasionSource=typeof INVASION_SOURCES[number];

export const PHASE_SECONDS:Record<InvasionPhase,number>={WARNING:60,MUSTER:60,ARRIVAL:30,ASSAULT:30,BATTLE:120,RESOLUTION:1,REWARD:1,COOLDOWN:300,COMPLETE:0};
export const WAVE_TEMPLATES=[
 {unitType:"pirate_infantry",category:"infantry",health:100,attack:14,defense:12,multiplier:1},
 {unitType:"musketeer",category:"infantry",health:80,attack:24,defense:8,multiplier:0.7},
 {unitType:"archer",category:"infantry",health:75,attack:20,defense:7,multiplier:0.7},
 {unitType:"elemental_warrior",category:"magic",health:125,attack:28,defense:16,multiplier:0.35},
 {unitType:"dragon",category:"creature",health:260,attack:48,defense:28,multiplier:0.12},
 {unitType:"cannon",category:"siege",health:150,attack:60,defense:12,multiplier:0.08},
] as const;

export interface ThreatInputs{playerLevel:number;guildLevel:number;territoryStrength:number;previousVictories:number;activePlayers:number;baseDefense:number;regionalThreat:number}
export function calculateThreatScore(i:ThreatInputs):number{
 const raw=i.playerLevel*50+i.guildLevel*75+i.territoryStrength*2+i.previousVictories*100+i.activePlayers*150+Math.floor(i.baseDefense/10)+i.regionalThreat;
 return Math.max(500,Math.min(100000,Math.floor(raw)));
}
export function buildWavePlan(threat:number,waves=Math.max(2,Math.min(6,Math.ceil(threat/5000)))) {
 const safeThreat=Math.max(500,Math.min(100000,Math.floor(threat)));
 return WAVE_TEMPLATES.map(t=>({...t,quantity:Math.max(1,Math.floor(safeThreat*t.multiplier/100))})).filter(x=>x.quantity>0).slice(0,waves);
}
function phaseIndex(p:InvasionPhase){return INVASION_PHASES.indexOf(p)}
function nextPhase(p:InvasionPhase):InvasionPhase{return INVASION_PHASES[Math.min(INVASION_PHASES.length-1,phaseIndex(p)+1)]}
function addSeconds(d:Date,s:number){return new Date(d.getTime()+s*1000)}
export function nextPhaseAt(phase:InvasionPhase,started:Date){return addSeconds(started,PHASE_SECONDS[phase])}

export interface InvasionSummary{id:string;territoryId:string;sourceType:InvasionSource;targetBaseId:string|null;phase:InvasionPhase;threatScore:number;outcome:string|null;phaseEndsAt:string}

export class InvasionStore{
 constructor(private readonly db:Pool){}
 private async activeForTerritory(c:PoolClient,territoryId:string){return (await c.query<{id:string}>("SELECT id FROM invasions WHERE territory_id=$1 AND phase NOT IN ('COMPLETE','COOLDOWN') LIMIT 1",[territoryId])).rows[0]??null}
 async create(userId:string|null,territoryId:string,sourceType:InvasionSource,threatScore:number):Promise<InvasionSummary>{
  if(!Number.isSafeInteger(threatScore)||threatScore<500||threatScore>100000)throw new Error("INVALID_INVASION_THREAT");
  if(!INVASION_SOURCES.includes(sourceType))throw new Error("INVALID_INVASION_SOURCE");
  const c=await this.db.connect();try{await c.query("BEGIN");
   const t=await c.query<{id:string;realm_owner_id:string|null;control_points:number}>("SELECT id,realm_owner_id,control_points FROM territories WHERE id=$1 FOR UPDATE",[territoryId]);if(!t.rows[0])throw new Error("TERRITORY_NOT_FOUND");
   if(await this.activeForTerritory(c,territoryId))throw new Error("INVASION_ALREADY_ACTIVE");
   const target=await c.query<{id:string;owner_user_id:string}>("SELECT b.id,b.owner_user_id FROM player_bases b WHERE b.x BETWEEN (SELECT min_x FROM territories WHERE id=$1) AND (SELECT max_x FROM territories WHERE id=$1) AND b.y BETWEEN (SELECT min_y FROM territories WHERE id=$1) AND (SELECT max_y FROM territories WHERE id=$1) ORDER BY b.updated_at DESC,b.id LIMIT 1",[territoryId]);
   const source=await c.query<{id:string}>("SELECT id FROM realms WHERE id<>$1 ORDER BY military_strength DESC,name LIMIT 1",[t.rows[0].realm_owner_id]);
   const now=new Date(),phaseEnd=nextPhaseAt("WARNING",now);
   const r=await c.query<{id:string;phase_ends_at:Date}>("INSERT INTO invasions(territory_id,source_realm_id,source_type,target_base_id,phase,threat_score,started_at,phase_started_at,phase_ends_at,metadata) VALUES($1,$2,$3,$4,'WARNING',$5,$6,$6,$7,$8::jsonb) RETURNING id,phase_ends_at",[territoryId,source.rows[0]?.id??null,sourceType,target.rows[0]?.id??null,threatScore,now,phaseEnd,JSON.stringify({createdBy:userId,controlPoints:t.rows[0].control_points})]);
   await c.query("UPDATE invasion_schedules SET next_run_at=CURRENT_TIMESTAMP+INTERVAL '900 seconds' WHERE territory_id=$1",[territoryId]);
   await c.query("UPDATE invasion_threats SET last_invasion_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE territory_id=$1",[territoryId]);
   await c.query("COMMIT");return {id:r.rows[0].id,territoryId,sourceType,targetBaseId:target.rows[0]?.id??null,phase:"WARNING",threatScore,outcome:null,phaseEndsAt:r.rows[0].phase_ends_at.toISOString()};
  }catch(e){await c.query("ROLLBACK");throw e}finally{c.release()}
 }
 async join(userId:string,invasionId:string,armyId:string):Promise<void>{
  const c=await this.db.connect();try{await c.query("BEGIN");await c.query("SELECT id FROM users WHERE id=$1 FOR UPDATE",[userId]);
   const inv=await c.query<{id:string;phase:InvasionPhase}>("SELECT id,phase FROM invasions WHERE id=$1 FOR UPDATE",[invasionId]);if(!inv.rows[0])throw new Error("INVASION_NOT_FOUND");if(!["WARNING","MUSTER","ARRIVAL","ASSAULT","BATTLE"].includes(inv.rows[0].phase))throw new Error("INVASION_NOT_JOINABLE");
   const army=await c.query<{owner_user_id:string;assignment:string}>("SELECT owner_user_id,assignment FROM armies WHERE id=$1 FOR UPDATE",[armyId]);if(!army.rows[0])throw new Error("ARMY_NOT_FOUND");if(army.rows[0].owner_user_id!==userId)throw new Error("ARMY_NOT_OWNED");
   const power=await c.query<{power:string}>("SELECT COALESCE(SUM((attack+defense)*quantity),0)::text power FROM army_units WHERE army_id=$1",[armyId]);
   await c.query("INSERT INTO invasion_participants(invasion_id,user_id,army_id,contribution,actions) VALUES($1,$2,$3,$4,0) ON CONFLICT(invasion_id,user_id) DO UPDATE SET army_id=EXCLUDED.army_id,contribution=GREATEST(invasion_participants.contribution,EXCLUDED.contribution),updated_at=CURRENT_TIMESTAMP",[invasionId,userId,armyId,power.rows[0]?.power??"0"]);
   await c.query("UPDATE armies SET assignment='invasion',status='deployed',updated_at=CURRENT_TIMESTAMP WHERE id=$1",[armyId]);
   await c.query("COMMIT");
  }catch(e){await c.query("ROLLBACK");throw e}finally{c.release()}
 }
 async act(userId:string,invasionId:string,action:"attack"|"reinforce"|"retreat",waveId:string|null):Promise<InvasionSummary>{
  const c=await this.db.connect();try{await c.query("BEGIN");
   const inv=await c.query<{id:string;phase:InvasionPhase;threat_score:number;territory_id:string;target_base_id:string|null}>("SELECT id,phase,threat_score,territory_id,target_base_id FROM invasions WHERE id=$1 FOR UPDATE",[invasionId]);if(!inv.rows[0])throw new Error("INVASION_NOT_FOUND");if(inv.rows[0].phase!=="BATTLE")throw new Error("INVASION_NOT_IN_BATTLE");
   const p=await c.query<{contribution:string}>("SELECT contribution FROM invasion_participants WHERE invasion_id=$1 AND user_id=$2 FOR UPDATE",[invasionId,userId]);if(!p.rows[0])throw new Error("INVASION_NOT_PARTICIPANT");
   if(action==="attack"){
    if(!waveId)throw new Error("INVASION_WAVE_REQUIRED");const w=await c.query<{id:string;current_health:number;max_health:number;attack:number;defense:number;quantity:number}>("SELECT id,current_health,max_health,attack,defense,quantity FROM invasion_waves WHERE id=$1 AND invasion_id=$2 FOR UPDATE",[waveId,invasionId]);if(!w.rows[0])throw new Error("INVASION_WAVE_NOT_FOUND");const damage=Math.max(1,Math.floor(Number(p.rows[0].contribution)/100));const next=Math.max(0,w.rows[0].current_health-damage);await c.query("UPDATE invasion_waves SET current_health=$2,status=$3,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[waveId,next,next===0?"defeated":"active"]);await c.query("UPDATE invasion_participants SET actions=actions+1,contribution=contribution+$3,updated_at=CURRENT_TIMESTAMP WHERE invasion_id=$1 AND user_id=$2",[invasionId,userId,damage]);
   }else if(action==="reinforce"){await c.query("UPDATE invasion_participants SET actions=actions+1,contribution=contribution+GREATEST(contribution/10,1),updated_at=CURRENT_TIMESTAMP WHERE invasion_id=$1 AND user_id=$2",[invasionId,userId]);}
   else {await c.query("UPDATE invasion_participants SET actions=actions+1,contribution=GREATEST(contribution/2,0),army_id=NULL,updated_at=CURRENT_TIMESTAMP WHERE invasion_id=$1 AND user_id=$2",[invasionId,userId]);}
   const s=await c.query<{territory_id:string;source_type:InvasionSource;target_base_id:string|null;phase:InvasionPhase;threat_score:number;outcome:string|null;phase_ends_at:Date}>("SELECT territory_id,source_type,target_base_id,phase,threat_score,outcome,phase_ends_at FROM invasions WHERE id=$1",[invasionId]);await c.query("COMMIT");return {id:invasionId,territoryId:s.rows[0].territory_id,sourceType:s.rows[0].source_type,targetBaseId:s.rows[0].target_base_id,phase:s.rows[0].phase,threatScore:s.rows[0].threat_score,outcome:s.rows[0].outcome,phaseEndsAt:s.rows[0].phase_ends_at.toISOString()};
  }catch(e){await c.query("ROLLBACK");throw e}finally{c.release()}
 }
 async tick():Promise<number>{
  const c=await this.db.connect();let advanced=0;try{
   const due=await c.query<{id:string;phase:InvasionPhase;phase_started_at:Date;phase_ends_at:Date;threat_score:number;territory_id:string;target_base_id:string|null}>("SELECT id,phase,phase_started_at,phase_ends_at,threat_score,territory_id,target_base_id FROM invasions WHERE phase_ends_at<=CURRENT_TIMESTAMP AND phase NOT IN ('COMPLETE','COOLDOWN') ORDER BY phase_ends_at,id FOR UPDATE SKIP LOCKED");
   for(const inv of due.rows){await this.advance(c,inv);advanced++}
   await this.schedule(c);return advanced;
  }finally{c.release()}
 }
 private async schedule(c:PoolClient){
  const due=await c.query<{territory_id:string}>("SELECT territory_id FROM invasion_schedules WHERE enabled=true AND next_run_at<=CURRENT_TIMESTAMP ORDER BY next_run_at,territory_id FOR UPDATE SKIP LOCKED");
  for(const row of due.rows){
   const active=await this.activeForTerritory(c,row.territory_id);if(active){await c.query("UPDATE invasion_schedules SET next_run_at=CURRENT_TIMESTAMP+INTERVAL '300 seconds' WHERE territory_id=$1",[row.territory_id]);continue}
   const ctx=await c.query<{territory_strength:number;threat_level:number;victories:number;target_base_defense:string;active_players:string;level:number;guild_level:number}>("SELECT COALESCE(t.control_points,0) territory_strength,COALESCE(it.threat_level,0) threat_level,COALESCE(it.victories,0) victories,COALESCE((SELECT SUM(bd.level*CASE WHEN bd.structure_type LIKE '%tower' OR bd.structure_type='wall' OR bd.structure_type='gate' THEN 100 ELSE 40 END) FROM base_defensive_structures bd JOIN player_bases pb ON pb.id=bd.base_id WHERE pb.x BETWEEN t.min_x AND t.max_x AND pb.y BETWEEN t.min_y AND t.max_y AND bd.active),0)::text target_base_defense,COALESCE((SELECT COUNT(*) FROM player_profiles pp WHERE pp.x BETWEEN t.min_x AND t.max_x AND pp.y BETWEEN t.min_y AND t.max_y),0)::text active_players,COALESCE((SELECT MAX(level) FROM player_profiles pp WHERE pp.x BETWEEN t.min_x AND t.max_x AND pp.y BETWEEN t.min_y AND t.max_y),1) level,1 guild_level FROM territories t LEFT JOIN invasion_threats it ON it.territory_id=t.id WHERE t.id=$1",[row.territory_id]);
   const x=ctx.rows[0];if(!x)continue;const threat=calculateThreatScore({playerLevel:x.level,guildLevel:x.guild_level,territoryStrength:x.territory_strength,previousVictories:x.victories,activePlayers:Number(x.active_players),baseDefense:Number(x.target_base_defense),regionalThreat:x.threat_level});const source:InvasionSource=INVASION_SOURCES[threat%INVASION_SOURCES.length];await this.create(null,row.territory_id,source,threat);
  }
 }
 private async advance(c:PoolClient,inv:{id:string;phase:InvasionPhase;phase_started_at:Date;phase_ends_at:Date;threat_score:number;territory_id:string;target_base_id:string|null}){
  if(inv.phase==="ARRIVAL")await this.materializeWaves(c,inv.id,inv.threat_score);
  if(inv.phase==="BATTLE" )await this.resolveIfBattleEnded(c,inv);
  const next=nextPhase(inv.phase);if(next==="COMPLETE"){await c.query("UPDATE invasions SET phase='COMPLETE',resolved_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[inv.id]);return}
  const now=new Date(),end=nextPhaseAt(next,now);await c.query("UPDATE invasions SET phase=$2,phase_started_at=$3,phase_ends_at=$4,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[inv.id,next,now,end]);
  if(next==="COOLDOWN")await this.applyResolution(c,inv.id,inv.territory_id,inv.target_base_id);
  if(next==="REWARD")await this.issueRewards(c,inv.id,inv.threat_score);
 }
 private async materializeWaves(c:PoolClient,invasionId:string,threat:number){
  const exists=await c.query("SELECT 1 FROM invasion_waves WHERE invasion_id=$1 LIMIT 1",[invasionId]);if(exists.rows[0])return;
  for(const [i,w] of buildWavePlan(threat).entries()){const qty=w.quantity,health=qty*w.health;await c.query("INSERT INTO invasion_waves(invasion_id,wave_number,unit_type,category,quantity,max_health,current_health,attack,defense,status) VALUES($1,$2,$3,$4,$5,$6,$6,$7,$8,'queued')",[invasionId,i+1,w.unitType,w.category,qty,health,w.attack,w.defense])}
  await c.query("UPDATE invasion_waves SET status='active' WHERE invasion_id=$1 AND wave_number=1",[invasionId]);
 }
 private async resolveIfBattleEnded(c:PoolClient,inv:{id:string;threat_score:number}){
  const remaining=await c.query<{power:string}>("SELECT COALESCE(SUM(current_health*(attack+defense)/GREATEST(max_health,1)),0)::bigint power FROM invasion_waves WHERE invasion_id=$1 AND status<>'defeated'",[inv.id]);
  const defended=await c.query<{power:string}>("SELECT COALESCE(SUM(contribution),0)::text power FROM invasion_participants WHERE invasion_id=$1",[inv.id]);
  if(BigInt(defended.rows[0]?.power??"0")>=BigInt(remaining.rows[0]?.power??"0"))await c.query("UPDATE invasion_waves SET status='defeated',current_health=0 WHERE invasion_id=$1 AND status<>'defeated'",[inv.id]);
 }
 private async applyResolution(c:PoolClient,invasionId:string,territoryId:string,baseId:string|null){
  const w=await c.query<{power:string}>("SELECT COALESCE(SUM(current_health*(attack+defense)/GREATEST(max_health,1)),0)::bigint power FROM invasion_waves WHERE invasion_id=$1 AND status<>'defeated'",[invasionId]);
  const outcome=BigInt(w.rows[0]?.power??"0")===0n?"victory":"defeat";const severity=outcome==="victory"?0:Math.min(100,Math.max(10,Number(w.rows[0]?.power??0)/1000));
  await c.query("UPDATE invasions SET outcome=$2 WHERE id=$1",[invasionId,outcome]);await c.query("INSERT INTO invasion_consequences(invasion_id,territory_id,base_id,consequence_type,severity,payload) VALUES($1,$2,$3,$4,$5,$6::jsonb)",[invasionId,territoryId,baseId,outcome==="victory"?"defense_success":"territory_damage",severity,JSON.stringify({remainingEnemyPower:w.rows[0]?.power??"0"})]);
  await c.query("UPDATE invasion_threats SET threat_level=GREATEST(0,LEAST(100000,threat_level+CASE WHEN $2='victory' THEN 250 ELSE 1000 END)),victories=victories+CASE WHEN $2='victory' THEN 1 ELSE 0 END,defeats=defeats+CASE WHEN $2='defeat' THEN 1 ELSE 0 END,updated_at=CURRENT_TIMESTAMP WHERE territory_id=$1",[territoryId,outcome]);
  if(outcome==="defeat"){if(baseId)await c.query("UPDATE base_defensive_structures SET health=GREATEST(0,health-$2),active=CASE WHEN health-$2<=0 THEN false ELSE active END WHERE base_id=$1 AND active=true",[baseId,Math.max(10,severity*10)]);await c.query("UPDATE territories SET control_points=GREATEST(0,control_points-$2),updated_at=CURRENT_TIMESTAMP WHERE id=$1",[territoryId,Math.max(1,Math.floor(severity/5))]);}
 }
 private async issueRewards(c:PoolClient,invasionId:string,threat:number){
  const inv=await c.query<{outcome:string|null}>("SELECT outcome FROM invasions WHERE id=$1 FOR UPDATE",[invasionId]);if(!inv.rows[0])return;const participants=await c.query<{user_id:string;contribution:string}>("SELECT user_id,contribution FROM invasion_participants WHERE invasion_id=$1 ORDER BY contribution DESC",[invasionId]);if(!participants.rows.length)return;const win=inv.rows[0].outcome==="victory";for(const p of participants){const badges=BigInt(Math.max(10,Math.floor(threat/100)*(win?2:1)));const gold=BigInt(Math.max(100,Math.floor(threat*5/participants.length)));await c.query("INSERT INTO invasion_rewards(invasion_id,user_id,gold,triumph_badges,loot) VALUES($1,$2,$3,$4,$5::jsonb) ON CONFLICT DO NOTHING",[invasionId,p.user_id,gold,badges,JSON.stringify({treasure_maps:win?Math.max(1,Math.floor(threat/5000)):0,rare_treasure:win})]);await c.query("UPDATE player_profiles SET gold=gold+$2,triumph_badges=triumph_badges+$3,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[p.user_id,gold,badges]);}
 }
 async list(territoryId:string|null=null):Promise<InvasionSummary[]>{
  const q=territoryId?await this.db.query<{id:string;territory_id:string;source_type:InvasionSource;target_base_id:string|null;phase:InvasionPhase;threat_score:number;outcome:string|null;phase_ends_at:Date}>("SELECT id,territory_id,source_type,target_base_id,phase,threat_score,outcome,phase_ends_at FROM invasions WHERE territory_id=$1 ORDER BY started_at DESC",[territoryId]):await this.db.query<{id:string;territory_id:string;source_type:InvasionSource;target_base_id:string|null;phase:InvasionPhase;threat_score:number;outcome:string|null;phase_ends_at:Date}>("SELECT id,territory_id,source_type,target_base_id,phase,threat_score,outcome,phase_ends_at FROM invasions ORDER BY started_at DESC LIMIT 100");
  return q.rows.map(x=>({id:x.id,territoryId:x.territory_id,sourceType:x.source_type,targetBaseId:x.target_base_id,phase:x.phase,threatScore:x.threat_score,outcome:x.outcome,phaseEndsAt:x.phase_ends_at.toISOString()}));
 }
 async waves(invasionId:string){return (await this.db.query("SELECT id,wave_number,unit_type,category,quantity,max_health,current_health,attack,defense,status FROM invasion_waves WHERE invasion_id=$1 ORDER BY wave_number",[invasionId])).rows}
}