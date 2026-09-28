import type { Pool } from "pg";
import { CREATURE_STATS, type CombatTarget, type DamageType } from "./combat.js";

export const MAX_CREATURE_PARTY = 3;
export const CAPTURE_ORB_ITEM = "capture.orb";
export const CREATURE_FEED_ITEM = "creature.feed";
export const CAPTURE_HEALTH_RATIO = 0.25;
export const TAME_PROGRESS_PER_FEED = 25;
export type CreatureAiMode = "follow" | "assist" | "stay";

export interface OwnedCreature {
  id: string; ownerUserId: string; species: string; nickname: string | null;
  level: number; xp: number; health: number; maxHealth: number; attack: number; defense: number;
  element: DamageType; abilityIds: string[]; tameProgress: number; partySlot: number | null;
  aiMode: CreatureAiMode; x: number; y: number;
}
interface CreatureRow {
  id: string; owner_user_id: string; species: string; nickname: string | null; level: number; xp: string;
  health: number; max_health: number; attack: number; defense: number; element: DamageType;
  ability_ids: string[]; tame_progress: number; party_slot: number | null; ai_mode: CreatureAiMode; x: number; y: number;
}
function rowToCreature(r: CreatureRow): OwnedCreature {
  return { id:r.id, ownerUserId:r.owner_user_id, species:r.species, nickname:r.nickname, level:r.level, xp:Number(r.xp),
    health:r.health, maxHealth:r.max_health, attack:r.attack, defense:r.defense, element:r.element,
    abilityIds:r.ability_ids ?? [], tameProgress:r.tame_progress, partySlot:r.party_slot, aiMode:r.ai_mode, x:r.x, y:r.y };
}
function statsFor(species:string, level:number) {
  const s=CREATURE_STATS[species]; if(!s) throw new Error("UNKNOWN_CREATURE_SPECIES");
  const l=Math.max(1,Math.min(100,Math.floor(level)));
  return {level:l,maxHealth:s.health+(l-1)*10,attack:s.attack+(l-1)*2,defense:s.defense+(l-1),
    element:s.element,abilityIds:s.ability?[s.ability.id]:[]};
}
export class CreatureStore {
  private readonly active=new Map<string,OwnedCreature[]>();
  private readonly dirty=new Set<string>();
  private readonly revisions=new Map<string,number>();
  constructor(private readonly db:Pool){}
  async load(userId:string):Promise<OwnedCreature[]> {
    const cached=this.active.get(userId); if(cached) return cached;
    const r=await this.db.query<CreatureRow>("SELECT id,owner_user_id,species,nickname,level,xp,health,max_health,attack,defense,element,ability_ids,tame_progress,party_slot,ai_mode,x,y FROM player_creatures WHERE owner_user_id=$1 ORDER BY COALESCE(party_slot,999),created_at,id",[userId]);
    const creatures=r.rows.map(rowToCreature); this.active.set(userId,creatures); this.revisions.set(userId,0); return creatures;
  }
  get(userId:string):OwnedCreature[]{return this.active.get(userId)??[];}
  getCreature(userId:string,id:string){return this.get(userId).find(c=>c.id===id);}
  markDirty(userId:string){if(!this.active.has(userId))return;this.dirty.add(userId);this.revisions.set(userId,(this.revisions.get(userId)??0)+1);}
  async capture(userId:string,target:CombatTarget):Promise<OwnedCreature>{
    const client=await this.db.connect();
    try{
      await client.query("BEGIN");
      const invR=await client.query<{inventory:Record<string,number>}>("SELECT inventory FROM player_profiles WHERE user_id=$1 FOR UPDATE",[userId]);
      const inv=invR.rows[0]?.inventory??{}; const orbs=Number(inv[CAPTURE_ORB_ITEM]??0);
      if(!Number.isSafeInteger(orbs)||orbs<1)throw new Error("NO_CAPTURE_ORB");
      const duplicate=await client.query("SELECT 1 FROM player_creatures WHERE wild_source_id=$1 LIMIT 1",[target.id]);
      if(duplicate.rowCount)throw new Error("CREATURE_ALREADY_CAPTURED");
      const s=statsFor(target.species,target.level); const next={...inv,[CAPTURE_ORB_ITEM]:orbs-1};
      const inserted=await client.query<CreatureRow>(
        "INSERT INTO player_creatures(owner_user_id,wild_source_id,species,level,xp,health,max_health,attack,defense,element,ability_ids,tame_progress,party_slot,ai_mode,x,y) VALUES($1,$2,$3,$4,0,$5,$5,$6,$7,$8,$9::jsonb,0,NULL,'follow',$10,$11) RETURNING id,owner_user_id,species,nickname,level,xp,health,max_health,attack,defense,element,ability_ids,tame_progress,party_slot,ai_mode,x,y",
        [userId,target.id,target.species,s.level,s.maxHealth,s.attack,s.defense,s.element,JSON.stringify(s.abilityIds),target.x,target.y]);
      await client.query("UPDATE player_profiles SET inventory=$2::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[userId,JSON.stringify(next)]);
      await client.query("COMMIT");
      const c=rowToCreature(inserted.rows[0]); const list=this.active.get(userId)??[]; list.push(c); this.active.set(userId,list); this.markDirty(userId); return c;
    }catch(error){
      await client.query("ROLLBACK");
      if (typeof error === "object" && error !== null && "code" in error && (error as { code?: unknown }).code === "23505") throw new Error("CREATURE_ALREADY_CAPTURED", { cause: error });
      throw error;
    }finally{client.release();}
  }
  async tame(userId:string,id:string):Promise<{creature:OwnedCreature;consumed:boolean}>{
    const c=this.getCreature(userId,id); if(!c)throw new Error("CREATURE_NOT_FOUND"); if(c.tameProgress>=100)return {creature:c,consumed:false};
    const client=await this.db.connect();
    try{
      await client.query("BEGIN");
      const r=await client.query<{inventory:Record<string,number>}>("SELECT inventory FROM player_profiles WHERE user_id=$1 FOR UPDATE",[userId]);
      const inv=r.rows[0]?.inventory??{}; const feed=Number(inv[CREATURE_FEED_ITEM]??0);
      if(!Number.isSafeInteger(feed)||feed<1)throw new Error("NO_CREATURE_FEED");
      const progress=Math.min(100,c.tameProgress+TAME_PROGRESS_PER_FEED); const next={...inv,[CREATURE_FEED_ITEM]:feed-1};
      await client.query("UPDATE player_creatures SET tame_progress=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND owner_user_id=$3",[id,progress,userId]);
      await client.query("UPDATE player_profiles SET inventory=$2::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[userId,JSON.stringify(next)]);
      await client.query("COMMIT"); c.tameProgress=progress; this.markDirty(userId); return {creature:c,consumed:true};
    }catch(e){await client.query("ROLLBACK");throw e;}finally{client.release();}
  }
  async setPartySlot(userId:string,id:string,slot:number|null):Promise<OwnedCreature>{
    const c=this.getCreature(userId,id); if(!c)throw new Error("CREATURE_NOT_FOUND");
    if(c.tameProgress<100)throw new Error("CREATURE_NOT_TAMED");
    if(slot!==null&&(!Number.isInteger(slot)||slot<0||slot>=MAX_CREATURE_PARTY))throw new Error("INVALID_PARTY_SLOT");
    const client=await this.db.connect();
    try{
      await client.query("BEGIN");
      if(slot!==null)await client.query("UPDATE player_creatures SET party_slot=NULL WHERE owner_user_id=$1 AND party_slot=$2",[userId,slot]);
      await client.query("UPDATE player_creatures SET party_slot=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND owner_user_id=$3",[id,slot,userId]);
      await client.query("COMMIT");
      for(const e of this.get(userId))if(e.id!==id&&e.partySlot===slot)e.partySlot=null;
      c.partySlot=slot; this.markDirty(userId); return c;
    }catch(e){await client.query("ROLLBACK");throw e;}finally{client.release();}
  }
  setAiMode(userId:string,id:string,mode:CreatureAiMode):OwnedCreature{
    const c=this.getCreature(userId,id); if(!c)throw new Error("CREATURE_NOT_FOUND"); if(c.tameProgress<100)throw new Error("CREATURE_NOT_TAMED");
    c.aiMode=mode; this.markDirty(userId); return c;
  }
  tickAi(userId:string,player:{x:number;y:number}):boolean{
    let changed=false;
    for(const c of this.get(userId)){
      if(c.partySlot===null||c.tameProgress<100||c.aiMode==="stay")continue;
      const d=Math.hypot(player.x-c.x,player.y-c.y);
      if(d>3){const step=Math.min(d-2,0.375);c.x+=(player.x-c.x)/d*step;c.y+=(player.y-c.y)/d*step;changed=true;}
    }
    if(changed)this.markDirty(userId); return changed;
  }
  async persist(userId:string){
    if(!this.active.has(userId))return; const revision=this.revisions.get(userId)??0; const client=await this.db.connect();
    try{await client.query("BEGIN");
      for(const c of this.get(userId))await client.query("UPDATE player_creatures SET health=$2,xp=$3,level=$4,max_health=$5,attack=$6,defense=$7,tame_progress=$8,party_slot=$9,ai_mode=$10,x=$11,y=$12,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND owner_user_id=$13",[c.id,c.health,c.xp,c.level,c.maxHealth,c.attack,c.defense,c.tameProgress,c.partySlot,c.aiMode,c.x,c.y,userId]);
      await client.query("COMMIT"); if((this.revisions.get(userId)??0)===revision)this.dirty.delete(userId);
    }catch(e){await client.query("ROLLBACK");throw e;}finally{client.release();}
  }
  async unload(userId:string){await this.persist(userId);this.active.delete(userId);this.dirty.delete(userId);this.revisions.delete(userId);}
  async persistDirty(){for(const id of [...this.dirty])await this.persist(id);}
  async persistAll(){for(const id of this.active.keys())await this.persist(id);}
}
