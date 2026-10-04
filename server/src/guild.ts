import type {Pool,PoolClient} from 'pg';
import {applyInventoryDelta,cloneInventory,parseGoldDoubloons,subtractGoldDoubloons,addGoldDoubloons} from './economy.js';

export const GUILD_RANKS=['master','officer','veteran','member','recruit'] as const;
export type GuildRank=typeof GUILD_RANKS[number];
export const GUILD_PERMISSIONS=['manage_members','bank_deposit','bank_withdraw','quest_manage','quest_contribute','infrastructure_manage','configure_permissions'] as const;
export type GuildPermission=typeof GUILD_PERMISSIONS[number];
export const GUILD_INFRASTRUCTURE=['guild_hall','treasury','barracks','shipyard','research_centre','creature_sanctuary','war_room','defensive_walls'] as const;
export type GuildInfrastructure=typeof GUILD_INFRASTRUCTURE[number];

const QUESTS=[
  {key:'wood',title:'Timber Convoy',item:'wood',target:1000n,xp:250n,gold:100n,badges:1n},
  {key:'steel',title:'Steel Supply Run',item:'steel',target:500n,xp:350n,gold:150n,badges:1n},
  {key:'food',title:'Provision the Fleet',item:'food',target:750n,xp:200n,gold:90n,badges:1n},
] as const;

export interface GuildMember{userId:string;rank:GuildRank;joinedAt:string;}
export interface GuildInfrastructureState{structureType:GuildInfrastructure;level:number;}
export interface GuildQuest{id:string;operationKey:string;title:string;requirementItem:string;targetQuantity:string;progressQuantity:string;rewardXp:string;rewardGold:string;rewardBadges:string;status:'active'|'completed'|'expired';expiresAt:string;}
export interface GuildState{id:string;name:string;tag:string;leaderUserId:string;level:number;experience:string;treasury:string;myRank:GuildRank;members:GuildMember[];infrastructure:GuildInfrastructureState[];quests:GuildQuest[];}

function toRank(v:string):GuildRank{if((GUILD_RANKS as readonly string[]).includes(v))return v as GuildRank;throw new Error('INVALID_GUILD_RANK');}
function toPermission(v:string):GuildPermission{if((GUILD_PERMISSIONS as readonly string[]).includes(v))return v as GuildPermission;throw new Error('INVALID_GUILD_PERMISSION');}
function toInfrastructure(v:string):GuildInfrastructure{if((GUILD_INFRASTRUCTURE as readonly string[]).includes(v))return v as GuildInfrastructure;throw new Error('INVALID_GUILD_INFRASTRUCTURE');}
function guildLevel(x:bigint):number{const n=x/1000n+1n;return n>100n?100:Number(n);}
function guildName(v:string):string{const x=v.trim();if(x.length<3||x.length>64)throw new Error('INVALID_GUILD_NAME');return x;}
function guildTag(v:string):string{const x=v.trim().toUpperCase();if(!/^[A-Z0-9]{2,8}$/.test(x))throw new Error('INVALID_GUILD_TAG');return x;}

async function member(c:PoolClient,guildId:string,userId:string){
  const r=await c.query<{rank:string;joined_at:Date}>("SELECT rank,joined_at FROM guild_members WHERE guild_id=$1 AND user_id=$2 FOR UPDATE",[guildId,userId]);
  return r.rows[0]??null;
}
async function requirePermission(c:PoolClient,guildId:string,userId:string,p:GuildPermission){
  const m=await member(c,guildId,userId);if(!m)throw new Error('GUILD_MEMBERSHIP_REQUIRED');
  const r=toRank(m.rank);if(r==='master')return m;
  const q=await c.query<{enabled:boolean}>("SELECT enabled FROM guild_permissions WHERE guild_id=$1 AND rank=$2 AND permission=$3",[guildId,r,p]);
  if(!q.rows[0]?.enabled)throw new Error('GUILD_PERMISSION_DENIED');return m;
}
async function ensureDailyQuests(c:PoolClient,guildId:string){
  const day=new Date().toISOString().slice(0,10);
  for(const q of QUESTS)await c.query(
    "INSERT INTO guild_quests(guild_id,operation_key,title,requirement_item,target_quantity,reward_xp,reward_gold,reward_badges,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,CURRENT_TIMESTAMP+INTERVAL '1 day') ON CONFLICT(guild_id,operation_key) DO NOTHING",
    [guildId,day+':'+q.key,q.title,q.item,q.target.toString(),q.xp.toString(),q.gold.toString(),q.badges.toString()]);
}
async function completeQuest(c:PoolClient,guildId:string,userId:string,questId:string){
  const q=await c.query<{reward_xp:string;reward_gold:string;reward_badges:string}>("SELECT reward_xp,reward_gold,reward_badges FROM guild_quests WHERE id=$1 AND guild_id=$2 AND status='active' FOR UPDATE",[questId,guildId]);
  if(!q.rows[0])throw new Error('GUILD_QUEST_NOT_FOUND');
  const xp=BigInt(q.rows[0].reward_xp),gold=BigInt(q.rows[0].reward_gold),badges=BigInt(q.rows[0].reward_badges);
  const g=await c.query<{experience:string;treasury:string}>("SELECT experience,treasury FROM guilds WHERE id=$1 FOR UPDATE",[guildId]);
  if(!g.rows[0])throw new Error('GUILD_NOT_FOUND');
  const experience=BigInt(g.rows[0].experience)+xp;
  const treasury=addGoldDoubloons(BigInt(g.rows[0].treasury),gold);
  await c.query("UPDATE guilds SET experience=$2,level=$3,treasury=$4,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[guildId,experience.toString(),guildLevel(experience),treasury.toString()]);
  await c.query("UPDATE player_profiles SET xp=xp+$2,triumph_badges=triumph_badges+$3,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[userId,xp.toString(),badges.toString()]);
  await c.query("UPDATE guild_quests SET status='completed',completed_at=CURRENT_TIMESTAMP WHERE id=$1",[questId]);
}
export class GuildStore{
  constructor(private readonly db:Pool){}
  async create(userId:string,name:string,tag:string):Promise<GuildState>{
    const c=await this.db.connect();try{await c.query('BEGIN');const n=guildName(name),t=guildTag(tag);
      if((await c.query("SELECT guild_id FROM guild_members WHERE user_id=$1 FOR UPDATE",[userId])).rows[0])throw new Error('ALREADY_IN_GUILD');
      const b=await c.query<{id:string}>("SELECT id FROM player_bases WHERE owner_user_id=$1 FOR UPDATE",[userId]);if(!b.rows[0])throw new Error('BASE_NOT_FOUND');
      if(!(await c.query("SELECT id FROM base_buildings WHERE base_id=$1 AND type='guild_hall' AND active=true LIMIT 1",[b.rows[0].id])).rows[0])throw new Error('GUILD_HALL_REQUIRED');
      const g=await c.query<{id:string}>("INSERT INTO guilds(name,tag,leader_user_id) VALUES($1,$2,$3) RETURNING id",[n,t,userId]);const id=g.rows[0].id;
      await c.query("INSERT INTO guild_members(guild_id,user_id,rank) VALUES($1,$2,'master')",[id,userId]);
      const defaults:Record<GuildRank,readonly GuildPermission[]>={
        master:GUILD_PERMISSIONS,officer:['manage_members','bank_deposit','bank_withdraw','quest_manage','quest_contribute','infrastructure_manage'],
        veteran:['bank_deposit','quest_contribute'],member:['bank_deposit','quest_contribute'],recruit:['bank_deposit']};
      for(const r of GUILD_RANKS)for(const p of defaults[r])await c.query("INSERT INTO guild_permissions(guild_id,rank,permission,enabled) VALUES($1,$2,$3,true)",[id,r,p]);
      await c.query("INSERT INTO guild_infrastructure(guild_id,structure_type,level) VALUES($1,'guild_hall',1)",[id]);await ensureDailyQuests(c,id);await c.query('COMMIT');return this.get(userId);
    }catch(e){await c.query('ROLLBACK');if(typeof e==='object'&&e!==null&&'code' in e&&(e as {code?:unknown}).code==='23505')throw new Error('GUILD_NAME_OR_TAG_EXISTS');throw e}finally{c.release()}
  }
  async get(userId:string):Promise<GuildState>{
    const c=await this.db.connect();try{await c.query('BEGIN');const m=await c.query<{guild_id:string}>("SELECT guild_id FROM guild_members WHERE user_id=$1 FOR UPDATE",[userId]);if(!m.rows[0])throw new Error('GUILD_NOT_FOUND');await ensureDailyQuests(c,m.rows[0].guild_id);await c.query('COMMIT');return this.load(userId,m.rows[0].guild_id)}catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}
  }
  private async load(userId:string,guildId:string):Promise<GuildState>{
    const [g,m,i,q]=await Promise.all([
      this.db.query<{id:string;name:string;tag:string;leader_user_id:string;level:number;experience:string;treasury:string}>("SELECT id,name,tag,leader_user_id,level,experience,treasury FROM guilds WHERE id=$1",[guildId]),
      this.db.query<{user_id:string;rank:string;joined_at:Date}>("SELECT user_id,rank,joined_at FROM guild_members WHERE guild_id=$1 ORDER BY joined_at,user_id",[guildId]),
      this.db.query<{structure_type:string;level:number}>("SELECT structure_type,level FROM guild_infrastructure WHERE guild_id=$1 ORDER BY structure_type",[guildId]),
      this.db.query<{id:string;operation_key:string;title:string;requirement_item:string;target_quantity:string;progress_quantity:string;reward_xp:string;reward_gold:string;reward_badges:string;status:'active'|'completed'|'expired';expires_at:Date}>("SELECT id,operation_key,title,requirement_item,target_quantity,progress_quantity,reward_xp,reward_gold,reward_badges,status,expires_at FROM guild_quests WHERE guild_id=$1 ORDER BY starts_at DESC,operation_key",[guildId])
    ]);
    const row=g.rows[0],mine=m.rows.find(x=>x.user_id===userId);if(!row||!mine)throw new Error('GUILD_NOT_FOUND');
    return {id:row.id,name:row.name,tag:row.tag,leaderUserId:row.leader_user_id,level:row.level,experience:row.experience,treasury:row.treasury,myRank:toRank(mine.rank),
      members:m.rows.map(x=>({userId:x.user_id,rank:toRank(x.rank),joinedAt:x.joined_at.toISOString()})),
      infrastructure:i.rows.map(x=>({structureType:toInfrastructure(x.structure_type),level:x.level})),
      quests:q.rows.map(x=>({id:x.id,operationKey:x.operation_key,title:x.title,requirementItem:x.requirement_item,targetQuantity:x.target_quantity,progressQuantity:x.progress_quantity,rewardXp:x.reward_xp,rewardGold:x.reward_gold,rewardBadges:x.reward_badges,status:x.status,expiresAt:x.expires_at.toISOString()}))};
  }
  async invite(userId:string,guildId:string,targetUserId:string):Promise<void>{
    const c=await this.db.connect();try{await c.query('BEGIN');await requirePermission(c,guildId,userId,'manage_members');if(userId===targetUserId)throw new Error('INVALID_GUILD_INVITEE');
      if((await c.query("SELECT guild_id FROM guild_members WHERE user_id=$1",[targetUserId])).rows[0])throw new Error('TARGET_ALREADY_IN_GUILD');
      if(!(await c.query("SELECT id FROM users WHERE id=$1",[targetUserId])).rows[0])throw new Error('PLAYER_NOT_FOUND');
      await c.query("UPDATE guild_invitations SET status='declined',responded_at=CURRENT_TIMESTAMP WHERE guild_id=$1 AND invitee_user_id=$2 AND status='pending'",[guildId,targetUserId]);
      await c.query("INSERT INTO guild_invitations(guild_id,inviter_user_id,invitee_user_id) VALUES($1,$2,$3)",[guildId,userId,targetUserId]);await c.query('COMMIT');
    }catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}
  }
  async acceptInvite(userId:string,invitationId:string):Promise<GuildState>{
    const c=await this.db.connect();try{await c.query('BEGIN');const inv=await c.query<{guild_id:string}>("SELECT guild_id FROM guild_invitations WHERE id=$1 AND invitee_user_id=$2 AND status='pending' FOR UPDATE",[invitationId,userId]);if(!inv.rows[0])throw new Error('GUILD_INVITATION_NOT_FOUND');
      if((await c.query("SELECT guild_id FROM guild_members WHERE user_id=$1 FOR UPDATE",[userId])).rows[0])throw new Error('ALREADY_IN_GUILD');
      await c.query("INSERT INTO guild_members(guild_id,user_id,rank) VALUES($1,$2,'recruit')",[inv.rows[0].guild_id,userId]);
      await c.query("UPDATE guild_invitations SET status='accepted',responded_at=CURRENT_TIMESTAMP WHERE id=$1",[invitationId]);await c.query('COMMIT');return this.get(userId);
    }catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}
  }
  async declineInvite(userId:string,invitationId:string):Promise<void>{
    const c=await this.db.connect();try{await c.query('BEGIN');const r=await c.query("UPDATE guild_invitations SET status='declined',responded_at=CURRENT_TIMESTAMP WHERE id=$1 AND invitee_user_id=$2 AND status='pending'",[invitationId,userId]);if(r.rowCount===0)throw new Error('GUILD_INVITATION_NOT_FOUND');await c.query('COMMIT')}catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}
  }
  async leave(userId:string,guildId:string):Promise<void>{
    const c=await this.db.connect();try{await c.query('BEGIN');const m=await member(c,guildId,userId);if(!m)throw new Error('GUILD_MEMBERSHIP_REQUIRED');if(toRank(m.rank)==='master')throw new Error('GUILD_MASTER_CANNOT_LEAVE');await c.query("DELETE FROM guild_members WHERE guild_id=$1 AND user_id=$2",[guildId,userId]);await c.query('COMMIT')}catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}
  }
  async removeMember(userId:string,guildId:string,targetUserId:string):Promise<void>{
    const c=await this.db.connect();try{await c.query('BEGIN');await requirePermission(c,guildId,userId,'manage_members');if(userId===targetUserId)throw new Error('INVALID_GUILD_MEMBER');const t=await member(c,guildId,targetUserId);if(!t)throw new Error('GUILD_MEMBER_NOT_FOUND');if(toRank(t.rank)==='master')throw new Error('GUILD_MASTER_PROTECTED');await c.query("DELETE FROM guild_members WHERE guild_id=$1 AND user_id=$2",[guildId,targetUserId]);await c.query('COMMIT')}catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}
  }
  async setRank(userId:string,guildId:string,targetUserId:string,newRank:string):Promise<void>{
    const c=await this.db.connect();try{await c.query('BEGIN');await requirePermission(c,guildId,userId,'manage_members');const r=toRank(newRank);if(r==='master')throw new Error('GUILD_MASTER_PROTECTED');const t=await member(c,guildId,targetUserId);if(!t)throw new Error('GUILD_MEMBER_NOT_FOUND');if(toRank(t.rank)==='master')throw new Error('GUILD_MASTER_PROTECTED');await c.query("UPDATE guild_members SET rank=$3 WHERE guild_id=$1 AND user_id=$2",[guildId,targetUserId,r]);await c.query('COMMIT')}catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}
  }
  async setPermission(userId:string,guildId:string,targetRank:string,p:string,enabled:boolean):Promise<void>{
    const c=await this.db.connect();try{await c.query('BEGIN');await requirePermission(c,guildId,userId,'configure_permissions');const r=toRank(targetRank),perm=toPermission(p);await c.query("INSERT INTO guild_permissions(guild_id,rank,permission,enabled) VALUES($1,$2,$3,$4) ON CONFLICT(guild_id,rank,permission) DO UPDATE SET enabled=EXCLUDED.enabled",[guildId,r,perm,enabled]);await c.query('COMMIT')}catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}
  }
  async bank(userId:string,guildId:string){
    const c=await this.db.connect();try{await c.query('BEGIN');if(!await member(c,guildId,userId))throw new Error('GUILD_MEMBERSHIP_REQUIRED');const g=await c.query<{treasury:string}>("SELECT treasury FROM guilds WHERE id=$1 FOR UPDATE",[guildId]);if(!g.rows[0])throw new Error('GUILD_NOT_FOUND');
      const items=await c.query<{item_id:string;quantity:string}>("SELECT item_id,quantity FROM guild_bank_items WHERE guild_id=$1 ORDER BY item_id",[guildId]);const tx=await c.query("SELECT action_type,item_id,quantity,gold_before,gold_after,created_at FROM guild_bank_transactions WHERE guild_id=$1 ORDER BY created_at DESC LIMIT 50",[guildId]);await c.query('COMMIT');
      return {treasury:g.rows[0].treasury,items:items.rows.map(x=>({itemId:x.item_id,quantity:x.quantity})),transactions:tx.rows};
    }catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}
  }
  async bankDeposit(userId:string,guildId:string,itemId:string,quantity:number,gold:string):Promise<void>{
    if(quantity<0||!Number.isSafeInteger(quantity)||quantity>1_000_000)throw new Error('INVALID_GUILD_BANK_QUANTITY');const gld=parseGoldDoubloons(gold);if(quantity===0&&gld===0n)throw new Error('INVALID_GUILD_BANK_DEPOSIT');
    const c=await this.db.connect();try{await c.query('BEGIN');await requirePermission(c,guildId,userId,'bank_deposit');const p=await c.query<{gold:string;inventory:Record<string,number>}>("SELECT gold,inventory FROM player_profiles WHERE user_id=$1 FOR UPDATE",[userId]);if(!p.rows[0])throw new Error('PLAYER_NOT_FOUND');
      let inv=cloneInventory(p.rows[0].inventory);if(quantity>0)inv=applyInventoryDelta(inv,itemId,-quantity);const playerGold=subtractGoldDoubloons(BigInt(p.rows[0].gold),gld);
      const gr=await c.query<{treasury:string}>("SELECT treasury FROM guilds WHERE id=$1 FOR UPDATE",[guildId]);if(!gr.rows[0])throw new Error('GUILD_NOT_FOUND');const guildGold=addGoldDoubloons(BigInt(gr.rows[0].treasury),gld);
      if(quantity>0)await c.query("INSERT INTO guild_bank_items(guild_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(guild_id,item_id) DO UPDATE SET quantity=guild_bank_items.quantity+EXCLUDED.quantity,updated_at=CURRENT_TIMESTAMP",[guildId,itemId,quantity]);
      await c.query("UPDATE player_profiles SET gold=$2,inventory=$3::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[userId,playerGold.toString(),JSON.stringify(inv)]);await c.query("UPDATE guilds SET treasury=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[guildId,guildGold.toString()]);
      await this.progressDeposits(c,guildId,userId,itemId,quantity);await c.query("INSERT INTO guild_bank_transactions(guild_id,user_id,action_type,item_id,quantity,gold_before,gold_after,metadata) VALUES($1,$2,'deposit',$3,$4,$5,$6,$7::jsonb)",[guildId,userId,itemId||null,quantity,p.rows[0].gold,playerGold.toString(),JSON.stringify({gold:gld.toString()})]);await c.query('COMMIT');
    }catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}
  }
  async bankWithdraw(userId:string,guildId:string,itemId:string,quantity:number,gold:string):Promise<void>{
    if(quantity<0||!Number.isSafeInteger(quantity)||quantity>1_000_000)throw new Error('INVALID_GUILD_BANK_QUANTITY');const gld=parseGoldDoubloons(gold);if(quantity===0&&gld===0n)throw new Error('INVALID_GUILD_BANK_WITHDRAW');
    const c=await this.db.connect();try{await c.query('BEGIN');await requirePermission(c,guildId,userId,'bank_withdraw');const gr=await c.query<{treasury:string}>("SELECT treasury FROM guilds WHERE id=$1 FOR UPDATE",[guildId]);if(!gr.rows[0])throw new Error('GUILD_NOT_FOUND');const guildGold=subtractGoldDoubloons(BigInt(gr.rows[0].treasury),gld);
      if(quantity>0){const item=await c.query<{quantity:string}>("SELECT quantity FROM guild_bank_items WHERE guild_id=$1 AND item_id=$2 FOR UPDATE",[guildId,itemId]);if(BigInt(item.rows[0]?.quantity??'0')<BigInt(quantity))throw new Error('INSUFFICIENT_GUILD_BANK');}
      const p=await c.query<{gold:string;inventory:Record<string,number>}>("SELECT gold,inventory FROM player_profiles WHERE user_id=$1 FOR UPDATE",[userId]);if(!p.rows[0])throw new Error('PLAYER_NOT_FOUND');let inv=cloneInventory(p.rows[0].inventory);if(quantity>0)inv=applyInventoryDelta(inv,itemId,quantity);const playerGold=addGoldDoubloons(BigInt(p.rows[0].gold),gld);
      if(quantity>0)await c.query("UPDATE guild_bank_items SET quantity=quantity-$3,updated_at=CURRENT_TIMESTAMP WHERE guild_id=$1 AND item_id=$2",[guildId,itemId,quantity]);await c.query("UPDATE guilds SET treasury=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[guildId,guildGold.toString()]);await c.query("UPDATE player_profiles SET gold=$2,inventory=$3::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[userId,playerGold.toString(),JSON.stringify(inv)]);
      await c.query("INSERT INTO guild_bank_transactions(guild_id,user_id,action_type,item_id,quantity,gold_before,gold_after,metadata) VALUES($1,$2,'withdraw',$3,$4,$5,$6,$7::jsonb)",[guildId,userId,itemId||null,quantity,gr.rows[0].treasury,guildGold.toString(),JSON.stringify({gold:gld.toString()})]);await c.query('COMMIT');
    }catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}
  }
  private async progressDeposits(c:PoolClient,guildId:string,userId:string,itemId:string,quantity:number){
    if(quantity<=0)return;const qs=await c.query<{id:string;progress_quantity:string;target_quantity:string}>("SELECT id,progress_quantity,target_quantity FROM guild_quests WHERE guild_id=$1 AND requirement_item=$2 AND status='active' AND expires_at>CURRENT_TIMESTAMP FOR UPDATE",[guildId,itemId]);
    for(const q of qs.rows){const progress=BigInt(q.progress_quantity)+BigInt(quantity);const next=progress>BigInt(q.target_quantity)?BigInt(q.target_quantity):progress;await c.query("UPDATE guild_quests SET progress_quantity=$2 WHERE id=$1",[q.id,next.toString()]);if(next>=BigInt(q.target_quantity))await completeQuest(c,guildId,userId,q.id);}
  }
  async buildInfrastructure(userId:string,guildId:string,structureType:string):Promise<void>{
    const s=toInfrastructure(structureType),c=await this.db.connect();try{await c.query('BEGIN');await requirePermission(c,guildId,userId,'infrastructure_manage');const g=await c.query<{treasury:string}>("SELECT treasury FROM guilds WHERE id=$1 FOR UPDATE",[guildId]);if(!g.rows[0])throw new Error('GUILD_NOT_FOUND');
      const current=await c.query<{level:number}>("SELECT level FROM guild_infrastructure WHERE guild_id=$1 AND structure_type=$2 FOR UPDATE",[guildId,s]);const level=(current.rows[0]?.level??0)+1;if(level>7)throw new Error('GUILD_INFRASTRUCTURE_MAX');const cost=BigInt(level*500);const treasury=subtractGoldDoubloons(BigInt(g.rows[0].treasury),cost);
      await c.query("INSERT INTO guild_infrastructure(guild_id,structure_type,level) VALUES($1,$2,$3) ON CONFLICT(guild_id,structure_type) DO UPDATE SET level=EXCLUDED.level,updated_at=CURRENT_TIMESTAMP",[guildId,s,level]);await c.query("UPDATE guilds SET treasury=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[guildId,treasury.toString()]);
      await c.query("INSERT INTO guild_bank_transactions(guild_id,user_id,action_type,quantity,gold_before,gold_after,metadata) VALUES($1,$2,'infrastructure',0,$3,$4,$5::jsonb)",[guildId,userId,g.rows[0].treasury,treasury.toString(),JSON.stringify({structure:s,level,cost:cost.toString()})]);await c.query('COMMIT');
    }catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}
  }
}
