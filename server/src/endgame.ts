import type { Pool, PoolClient } from "pg";
import { addGoldDoubloons, addTriumphBadges, applyInventoryDelta, cloneInventory } from "./economy.js";

export const ENDGAME_PHASES = ["mobilization","assault","resolution"] as const;
export type EndgamePhase = typeof ENDGAME_PHASES[number];
export const MYTHIC_TIERS = ["mythic","ancient","celestial"] as const;
export type MythicTier = typeof MYTHIC_TIERS[number];

function ensureLevel(level:number,minimum:number){if(!Number.isSafeInteger(level)||level<minimum)throw new Error("ENDGAME_LEVEL_REQUIRED");}
function bigintScore(v:string|number|bigint){const n=BigInt(v);if(n<0n)throw new Error("ENDGAME_INVALID_SCORE");return n;}
function sideOf(row:{attacker_realm_id:string;defender_realm_id:string},realmId:string):"attacker"|"defender"|null{return row.attacker_realm_id===realmId?"attacker":row.defender_realm_id===realmId?"defender":null;}

export interface RealmWarSummary {id:string;attackerRealmId:string;defenderRealmId:string;targetTerritoryId:string;status:string;phase:EndgamePhase;attackerScore:string;defenderScore:string;winnerRealmId:string|null;endsAt:string;}
export interface GuildBattleSummary {id:string;attackerGuildId:string;defenderGuildId:string;targetTerritoryId:string;status:string;phase:EndgamePhase;attackerScore:string;defenderScore:string;winnerGuildId:string|null;endsAt:string;}
export interface EndgameCreatureSummary {id:string;species:string;rarity:string;level:number;element:string;health:number;maxHealth:number;attack:number;defense:number;x:number;y:number;status:string;mythicContentKey:string;}
export interface MythicContentSummary {contentKey:string;title:string;tier:MythicTier;unlockLevel:number;description:string;reward:Record<string,string>;active:boolean;}

export function calculateRealmWarScore(armyPower:bigint, guildLevel:number):bigint {
  if(armyPower<0n||!Number.isSafeInteger(guildLevel)||guildLevel<1)throw new Error("ENDGAME_INVALID_SCORE");
  return armyPower * BigInt(Math.max(1,Math.min(100,guildLevel)));
}
export function calculateGuildBattleScore(armyPower:bigint, guildLevel:number):bigint {
  if(armyPower<0n||!Number.isSafeInteger(guildLevel)||guildLevel<1)throw new Error("ENDGAME_INVALID_SCORE");
  return armyPower * BigInt(Math.max(1,Math.min(100,guildLevel)));
}
export function calculateHighLevelCreatureDamage(playerLevel:number, creatureLevel:number):number {
  ensureLevel(playerLevel,50);
  if(!Number.isSafeInteger(creatureLevel)||creatureLevel<50)throw new Error("ENDGAME_INVALID_CREATURE");
  return Math.max(25,Math.floor(playerLevel*8+Math.max(0,playerLevel-creatureLevel)*2));
}

async function guildMembership(c:PoolClient,userId:string,guildId:string,leadership=false){
  const r=await c.query<{rank:string}>("SELECT rank FROM guild_members WHERE guild_id=$1 AND user_id=$2 FOR UPDATE",[guildId,userId]);
  if(!r.rows[0])throw new Error("GUILD_MEMBERSHIP_REQUIRED");
  if(leadership&&!["master","officer"].includes(r.rows[0].rank))throw new Error("GUILD_PERMISSION_DENIED");
  return r.rows[0].rank;
}
async function guildLevel(c:PoolClient,guildId:string){const r=await c.query<{level:number}>("SELECT level FROM guilds WHERE id=$1 FOR UPDATE",[guildId]);if(!r.rows[0])throw new Error("GUILD_NOT_FOUND");return r.rows[0].level;}
async function armyPower(c:PoolClient,armyId:string,userId:string){
  const owner=await c.query("SELECT id FROM armies WHERE id=$1 AND owner_user_id=$2 FOR UPDATE",[armyId,userId]);
  if(!owner.rows[0])throw new Error("ARMY_NOT_FOUND");
  const r=await c.query<{power:string}>("SELECT COALESCE(SUM((attack+defense)*quantity),0)::text power FROM army_units WHERE army_id=$1",[armyId]);
  return BigInt(r.rows[0]?.power??"0");
}

export class EndgameStore {
  constructor(private readonly db:Pool){}

  async realmWars():Promise<RealmWarSummary[]>{
    const r=await this.db.query<any>("SELECT id,attacker_realm_id,defender_realm_id,target_territory_id,status,phase,attacker_score,defender_score,winner_realm_id,ends_at FROM realm_wars ORDER BY ends_at,id");
    return r.rows.map(x=>({id:x.id,attackerRealmId:x.attacker_realm_id,defenderRealmId:x.defender_realm_id,targetTerritoryId:x.target_territory_id,status:x.status,phase:x.phase,attackerScore:String(x.attacker_score),defenderScore:String(x.defender_score),winnerRealmId:x.winner_realm_id,endsAt:x.ends_at.toISOString()}));
  }

  async createRealmWar(userId:string,attackerRealmId:string,defenderRealmId:string,targetTerritoryId:string):Promise<RealmWarSummary>{
    const c=await this.db.connect();try{await c.query("BEGIN");await c.query("SELECT pg_advisory_xact_lock(hashtext($1))",[targetTerritoryId]);
      if(attackerRealmId===defenderRealmId)throw new Error("ENDGAME_INVALID_REALM_SIDES");
      const guild=await c.query<{guild_id:string}>("SELECT guild_id FROM guild_members WHERE user_id=$1 AND rank IN ('master','officer') ORDER BY guild_id LIMIT 1 FOR UPDATE",[userId]);
      if(!guild.rows[0])throw new Error("GUILD_PERMISSION_DENIED");
      await c.query("SELECT id FROM realms WHERE id IN ($1,$2) ORDER BY id FOR UPDATE",[attackerRealmId,defenderRealmId]);
      const territory=await c.query<{id:string;realm_owner_id:string|null}>("SELECT id,realm_owner_id FROM territories WHERE id=$1 FOR UPDATE",[targetTerritoryId]);
      if(!territory.rows[0])throw new Error("TERRITORY_NOT_FOUND");
      if(territory.rows[0].realm_owner_id!==defenderRealmId)throw new Error("ENDGAME_TARGET_NOT_DEFENDER_TERRITORY");
      const active=await c.query("SELECT id FROM realm_wars WHERE target_territory_id=$1 AND status='active' FOR UPDATE",[targetTerritoryId]);if(active.rows[0])throw new Error("ENDGAME_WAR_ALREADY_ACTIVE");
      const r=await c.query<{id:string;ends_at:Date}>("INSERT INTO realm_wars(attacker_realm_id,defender_realm_id,target_territory_id,ends_at,state) VALUES($1,$2,$3,CURRENT_TIMESTAMP+INTERVAL '30 minutes',$4::jsonb) RETURNING id,ends_at",[attackerRealmId,defenderRealmId,targetTerritoryId,JSON.stringify({phase:"mobilization"})]);
      await c.query("INSERT INTO realm_war_participants(war_id,guild_id,realm_id) VALUES($1,$2,$3)",[r.rows[0].id,guild.rows[0].guild_id,attackerRealmId]);
      await c.query("COMMIT");return (await this.realmWars()).find(x=>x.id===r.rows[0].id)!;
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release();}
  }

  async joinRealmWar(userId:string,warId:string,guildId:string,realmId:string):Promise<void>{
    const c=await this.db.connect();try{await c.query("BEGIN");await guildMembership(c,userId,guildId,true);
      const war=await c.query<{attacker_realm_id:string;defender_realm_id:string;status:string}>("SELECT attacker_realm_id,defender_realm_id,status FROM realm_wars WHERE id=$1 FOR UPDATE",[warId]);if(!war.rows[0])throw new Error("ENDGAME_WAR_NOT_FOUND");if(war.rows[0].status!=="active")throw new Error("ENDGAME_WAR_NOT_ACTIVE");
      const existing=await c.query("SELECT 1 FROM realm_war_participants WHERE war_id=$1 AND guild_id=$2",[warId,guildId]);if(existing.rows[0])throw new Error("ENDGAME_ALREADY_PARTICIPATING");
      if(realmId!==war.rows[0].attacker_realm_id&&realmId!==war.rows[0].defender_realm_id)throw new Error("ENDGAME_INVALID_REALM_SIDE");
      await c.query("INSERT INTO realm_war_participants(war_id,guild_id,realm_id) VALUES($1,$2,$3)",[warId,guildId,realmId]);await c.query("COMMIT");
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release();}
  }

  async realmWarAction(userId:string,warId:string,guildId:string,armyId:string):Promise<RealmWarSummary>{
    const c=await this.db.connect();try{await c.query("BEGIN");
      const war=await c.query<{id:string;attacker_realm_id:string;defender_realm_id:string;status:string;phase:EndgamePhase}>("SELECT id,attacker_realm_id,defender_realm_id,status,phase FROM realm_wars WHERE id=$1 FOR UPDATE",[warId]);if(!war.rows[0])throw new Error("ENDGAME_WAR_NOT_FOUND");if(war.rows[0].status!=="active")throw new Error("ENDGAME_WAR_NOT_ACTIVE");
      const p=await c.query<{realm_id:string}>("SELECT realm_id FROM realm_war_participants WHERE war_id=$1 AND guild_id=$2 FOR UPDATE",[warId,guildId]);if(!p.rows[0])throw new Error("ENDGAME_GUILD_NOT_PARTICIPANT");
      await guildMembership(c,userId,guildId,false);const power=await armyPower(c,armyId,userId);const gl=await guildLevel(c,guildId);const score=calculateRealmWarScore(power,gl);
      if(power===0n)throw new Error("ENDGAME_NO_ARMY_POWER");
      const side=sideOf(war.rows[0],p.rows[0].realm_id);if(!side)throw new Error("ENDGAME_INVALID_REALM_SIDE");
      if(side==="attacker")await c.query("UPDATE realm_wars SET attacker_score=attacker_score+$2,phase='assault',updated_at=CURRENT_TIMESTAMP WHERE id=$1",[warId,score.toString()]);
      else await c.query("UPDATE realm_wars SET defender_score=defender_score+$2,phase='assault',updated_at=CURRENT_TIMESTAMP WHERE id=$1",[warId,score.toString()]);
      await c.query("UPDATE realm_war_participants SET contribution=contribution+$3,actions=actions+1,updated_at=CURRENT_TIMESTAMP WHERE war_id=$1 AND guild_id=$2",[warId,guildId,score.toString()]);
      await c.query("COMMIT");return (await this.realmWars()).find(x=>x.id===warId)!;
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release();}
  }

  async guildBattles():Promise<GuildBattleSummary[]>{
    const r=await this.db.query<any>("SELECT id,attacker_guild_id,defender_guild_id,target_territory_id,status,phase,attacker_score,defender_score,winner_guild_id,ends_at FROM guild_battles ORDER BY ends_at,id");
    return r.rows.map(x=>({id:x.id,attackerGuildId:x.attacker_guild_id,defenderGuildId:x.defender_guild_id,targetTerritoryId:x.target_territory_id,status:x.status,phase:x.phase,attackerScore:String(x.attacker_score),defenderScore:String(x.defender_score),winnerGuildId:x.winner_guild_id,endsAt:x.ends_at.toISOString()}));
  }

  async createGuildBattle(userId:string,attackerGuildId:string,defenderGuildId:string,targetTerritoryId:string):Promise<GuildBattleSummary>{
    const c=await this.db.connect();try{await c.query("BEGIN");await c.query("SELECT pg_advisory_xact_lock(hashtext($1))",[targetTerritoryId]);
      if(attackerGuildId===defenderGuildId)throw new Error("ENDGAME_INVALID_GUILD_SIDES");
      await guildMembership(c,userId,attackerGuildId,true);
      if(!(await c.query("SELECT id FROM territories WHERE id=$1 FOR UPDATE",[targetTerritoryId])).rows[0])throw new Error("TERRITORY_NOT_FOUND");
      const active=await c.query("SELECT id FROM guild_battles WHERE target_territory_id=$1 AND status='active' FOR UPDATE",[targetTerritoryId]);if(active.rows[0])throw new Error("ENDGAME_GUILD_BATTLE_ALREADY_ACTIVE");
      const r=await c.query<{id:string;ends_at:Date}>("INSERT INTO guild_battles(attacker_guild_id,defender_guild_id,target_territory_id,ends_at,state) VALUES($1,$2,$3,CURRENT_TIMESTAMP+INTERVAL '20 minutes',$4::jsonb) RETURNING id,ends_at",[attackerGuildId,defenderGuildId,targetTerritoryId,JSON.stringify({phase:"deployment"})]);
      await c.query("COMMIT");return (await this.guildBattles()).find(x=>x.id===r.rows[0].id)!;
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release();}
  }

  async joinGuildBattle(userId:string,battleId:string,armyId:string):Promise<void>{
    const c=await this.db.connect();try{await c.query("BEGIN");
      const b=await c.query<{attacker_guild_id:string;defender_guild_id:string;status:string}>("SELECT attacker_guild_id,defender_guild_id,status FROM guild_battles WHERE id=$1 FOR UPDATE",[battleId]);if(!b.rows[0])throw new Error("ENDGAME_GUILD_BATTLE_NOT_FOUND");if(b.rows[0].status!=="active")throw new Error("ENDGAME_GUILD_BATTLE_NOT_ACTIVE");
      const a=await c.query<{owner_user_id:string}>("SELECT owner_user_id FROM armies WHERE id=$1 FOR UPDATE",[armyId]);if(!a.rows[0]||a.rows[0].owner_user_id!==userId)throw new Error("ARMY_NOT_OWNED");
      const gm=await c.query<{guild_id:string}>("SELECT guild_id FROM guild_members WHERE user_id=$1 AND guild_id IN ($2,$3) ORDER BY guild_id LIMIT 1 FOR UPDATE",[userId,b.rows[0].attacker_guild_id,b.rows[0].defender_guild_id]);if(!gm.rows[0])throw new Error("GUILD_MEMBERSHIP_REQUIRED");
      const side=gm.rows[0].guild_id===b.rows[0].attacker_guild_id?"attacker":"defender";
      await c.query("INSERT INTO guild_battle_armies(battle_id,army_id,guild_id,side) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING",[battleId,armyId,gm.rows[0].guild_id,side]);
      await c.query("COMMIT");
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release();}
  }

  async guildBattleAction(userId:string,battleId:string,armyId:string):Promise<GuildBattleSummary>{
    const c=await this.db.connect();try{await c.query("BEGIN");
      const b=await c.query<{attacker_guild_id:string;defender_guild_id:string;status:string}>("SELECT attacker_guild_id,defender_guild_id,status FROM guild_battles WHERE id=$1 FOR UPDATE",[battleId]);if(!b.rows[0])throw new Error("ENDGAME_GUILD_BATTLE_NOT_FOUND");if(b.rows[0].status!=="active")throw new Error("ENDGAME_GUILD_BATTLE_NOT_ACTIVE");
      const a=await c.query<{guild_id:string;contribution:string}>("SELECT guild_id,contribution FROM guild_battle_armies WHERE battle_id=$1 AND army_id=$2 FOR UPDATE",[battleId,armyId]);if(!a.rows[0])throw new Error("ENDGAME_ARMY_NOT_DEPLOYED");
      if(!(await c.query("SELECT 1 FROM guild_members WHERE guild_id=$1 AND user_id=$2",[a.rows[0].guild_id,userId])).rows[0])throw new Error("GUILD_MEMBERSHIP_REQUIRED");
      const power=await armyPower(c,armyId,userId);const gl=await guildLevel(c,a.rows[0].guild_id);const score=calculateGuildBattleScore(power,gl);
      const side=a.rows[0].guild_id===b.rows[0].attacker_guild_id?"attacker":"defender";
      await c.query(side==="attacker"?"UPDATE guild_battles SET attacker_score=attacker_score+$2,phase='engagement',updated_at=CURRENT_TIMESTAMP WHERE id=$1":"UPDATE guild_battles SET defender_score=defender_score+$2,phase='engagement',updated_at=CURRENT_TIMESTAMP WHERE id=$1",[battleId,score.toString()]);
      await c.query("UPDATE guild_battle_armies SET contribution=contribution+$3,actions=actions+1,updated_at=CURRENT_TIMESTAMP WHERE battle_id=$1 AND army_id=$2",[battleId,armyId,score.toString()]);
      await c.query("COMMIT");return (await this.guildBattles()).find(x=>x.id===battleId)!;
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release();}
  }

  async creatures():Promise<EndgameCreatureSummary[]>{
    const r=await this.db.query<any>("SELECT e.id,t.species,t.rarity,t.level,t.element,e.health,t.max_health,t.attack,t.defense,e.x,e.y,e.status,t.mythic_content_key FROM endgame_creatures e JOIN endgame_creature_templates t ON t.id=e.template_id WHERE e.status='wild' ORDER BY t.level DESC,t.species,e.id");
    return r.rows.map(x=>({id:x.id,species:x.species,rarity:x.rarity,level:x.level,element:x.element,health:x.health,maxHealth:x.max_health,attack:x.attack,defense:x.defense,x:x.x,y:x.y,status:x.status,mythicContentKey:x.mythic_content_key}));
  }

  async mythic():Promise<MythicContentSummary[]>{
    const r=await this.db.query<any>("SELECT content_key,title,tier,unlock_level,description,reward,active FROM mythic_content WHERE active=true ORDER BY unlock_level,content_key");
    return r.rows.map(x=>({contentKey:x.content_key,title:x.title,tier:x.tier,unlockLevel:x.unlock_level,description:x.description,reward:x.reward,active:x.active}));
  }

  async spawnCreaturesIfNeeded():Promise<number>{
    const c=await this.db.connect();try{await c.query("BEGIN");await c.query("SELECT pg_advisory_xact_lock(16016)");
      const count=await c.query<{count:string}>("SELECT COUNT(*)::text count FROM endgame_creatures WHERE status='wild'");
      if(Number(count.rows[0]?.count??0)>=4){await c.query("COMMIT");return 0;}
      const templates=await c.query<{id:string;level:number;max_health:number}>( "SELECT id,level,max_health FROM endgame_creature_templates ORDER BY level DESC");
      let created=0;for(const t of templates.rows.slice(0,4)){const existing=await c.query("SELECT 1 FROM endgame_creatures WHERE template_id=$1 AND status='wild' LIMIT 1",[t.id]);if(existing.rows[0])continue;await c.query("INSERT INTO endgame_creatures(template_id,x,y,health) VALUES($1,$2,$3,$4)",[t.id,Math.floor(Math.random()*1000)-500,Math.floor(Math.random()*1000)-500,t.max_health]);created++;}
      await c.query("COMMIT");return created;
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release();}
  }

  async engageCreature(userId:string,creatureId:string,playerLevel:number):Promise<EndgameCreatureSummary>{
    ensureLevel(playerLevel,50);const c=await this.db.connect();try{await c.query("BEGIN");
      const r=await c.query<any>("SELECT e.id,e.health,e.status,t.species,t.rarity,t.level,t.element,t.max_health,t.attack,t.defense,t.mythic_content_key FROM endgame_creatures e JOIN endgame_creature_templates t ON t.id=e.template_id WHERE e.id=$1 FOR UPDATE",[creatureId]);if(!r.rows[0])throw new Error("ENDGAME_CREATURE_NOT_FOUND");if(r.rows[0].status!=="wild")throw new Error("ENDGAME_CREATURE_DEFEATED");
      const damage=calculateHighLevelCreatureDamage(playerLevel,r.rows[0].level);const next=Math.max(0,r.rows[0].health-damage);await c.query("UPDATE endgame_creatures SET health=$2,status=$3,defeated_by=CASE WHEN $2=0 THEN $4 ELSE defeated_by END,defeated_at=CASE WHEN $2=0 THEN CURRENT_TIMESTAMP ELSE defeated_at END,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[creatureId,next,next===0?"defeated":"wild",userId]);
      if(next===0){const p=await c.query<{gold:string;triumph_badges:string;inventory:Record<string,number>}>("SELECT gold,triumph_badges,inventory FROM player_profiles WHERE user_id=$1 FOR UPDATE",[userId]);if(!p.rows[0])throw new Error("PLAYER_NOT_FOUND");const rewardGold=BigInt(r.rows[0].level)*500n;const rewardBadges=BigInt(Math.max(1,Math.floor(r.rows[0].level/10)));let inv=cloneInventory(p.rows[0].inventory);inv=applyInventoryDelta(inv,"resource.dragon-scales",Math.max(1,Math.floor(r.rows[0].level/20)));const gold=addGoldDoubloons(BigInt(p.rows[0].gold),rewardGold);const badges=addTriumphBadges(BigInt(p.rows[0].triumph_badges),rewardBadges);await c.query("UPDATE player_profiles SET gold=$2,triumph_badges=$3,inventory=$4::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[userId,gold.toString(),badges.toString(),JSON.stringify(inv)]);}
      const row=await c.query<any>("SELECT e.id,t.species,t.rarity,t.level,t.element,e.health,t.max_health,t.attack,t.defense,e.x,e.y,e.status,t.mythic_content_key FROM endgame_creatures e JOIN endgame_creature_templates t ON t.id=e.template_id WHERE e.id=$1",[creatureId]);await c.query("COMMIT");const x=row.rows[0];return {id:x.id,species:x.species,rarity:x.rarity,level:x.level,element:x.element,health:x.health,maxHealth:x.max_health,attack:x.attack,defense:x.defense,x:x.x,y:x.y,status:x.status,mythicContentKey:x.mythic_content_key};
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release();}
  }

  async tick():Promise<number>{
    const c=await this.db.connect();try{await c.query("BEGIN");let changed=0;
      const wars=await c.query<any>("SELECT id,attacker_score,defender_score,ends_at FROM realm_wars WHERE status='active' AND ends_at<=CURRENT_TIMESTAMP FOR UPDATE");for(const w of wars.rows){const winner=BigInt(w.attacker_score)>=BigInt(w.defender_score)?"attacker":"defender";const winnerRealm=winner==="attacker"?(await c.query<{attacker_realm_id:string}>("SELECT attacker_realm_id FROM realm_wars WHERE id=$1",[w.id])).rows[0]?.attacker_realm_id:null;const defenderRealm=(await c.query<{defender_realm_id:string}>("SELECT defender_realm_id FROM realm_wars WHERE id=$1",[w.id])).rows[0]?.defender_realm_id;const wr=winner==="attacker"?winnerRealm:defenderRealm;await c.query("UPDATE realm_wars SET status='resolved',phase='resolution',winner_realm_id=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[w.id,wr]);changed++;}
      const battles=await c.query<any>("SELECT id,attacker_score,defender_score,ends_at FROM guild_battles WHERE status='active' AND ends_at<=CURRENT_TIMESTAMP FOR UPDATE");for(const b of battles.rows){const p=await c.query<{attacker_guild_id:string;defender_guild_id:string}>("SELECT attacker_guild_id,defender_guild_id FROM guild_battles WHERE id=$1",[b.id]);const winner=BigInt(b.attacker_score)>=BigInt(b.defender_score)?p.rows[0].attacker_guild_id:p.rows[0].defender_guild_id;await c.query("UPDATE guild_battles SET status='resolved',phase='resolution',winner_guild_id=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[b.id,winner]);changed++;}
      await c.query("COMMIT");return changed;
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release();}
  }
}