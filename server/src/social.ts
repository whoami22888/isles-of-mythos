import type { Pool, PoolClient } from "pg";

const CHAT_CHANNELS = ["local","region","party","guild","trade","global","system","whisper"] as const;
export type ChatChannel = typeof CHAT_CHANNELS[number];
const MAX_CHAT = 512;
const PARTY_LIMIT = 16;

function sortedPair(a:string,b:string):[string,string]{
  if(a===b) throw new Error("INVALID_SOCIAL_TARGET");
  return a < b ? [a,b] : [b,a];
}
function cleanText(value:string,max:number):string{
  const text=value.trim();
  if(!text || text.length>max) throw new Error("INVALID_MESSAGE");
  return text;
}
function channel(value:string):ChatChannel{
  if((CHAT_CHANNELS as readonly string[]).includes(value)) return value as ChatChannel;
  throw new Error("INVALID_CHAT_CHANNEL");
}
async function transaction<T>(db:Pool,fn:(c:PoolClient)=>Promise<T>):Promise<T>{
  const c=await db.connect();
  try{await c.query("BEGIN");const value=await fn(c);await c.query("COMMIT");return value;}
  catch(e){await c.query("ROLLBACK");throw e}
  finally{c.release();}
}

export interface FriendRecord{userId:string;status:"pending"|"accepted";requestedBy:string;createdAt:string;}
export interface PartyInvitation{id:string;party_id:string;inviter_user_id:string;created_at:Date;}
export interface PartyMember{userId:string;role:"leader"|"member";joinedAt:string;}
export interface PartyState{id:string;leaderUserId:string;members:PartyMember[];}
export interface ChatMessage{id:string;senderUserId:string;recipientUserId:string|null;guildId:string|null;partyId:string|null;channel:ChatChannel;regionId:number|null;body:string;createdAt:string;}

export class SocialStore{
  constructor(private readonly db:Pool){}

  async friends(userId:string):Promise<FriendRecord[]>{
    const r=await this.db.query<{user_id:string;status:"pending"|"accepted";requested_by:string;created_at:Date}>(
      "SELECT CASE WHEN user_a=$1 THEN user_b ELSE user_a END user_id,status,requested_by,created_at FROM social_friendships WHERE user_a=$1 OR user_b=$1 ORDER BY created_at DESC",[userId]);
    return r.rows.map(x=>({userId:x.user_id,status:x.status,requestedBy:x.requested_by,createdAt:x.created_at.toISOString()}));
  }

  async addFriend(userId:string,targetUserId:string):Promise<void>{
    const [a,b]=sortedPair(userId,targetUserId);
    await transaction(this.db,async c=>{
      const users=await c.query("SELECT id FROM users WHERE id=ANY($1::uuid[]) FOR KEY SHARE",[[userId,targetUserId]]);
      if(users.rowCount!==2) throw new Error("PLAYER_NOT_FOUND");
      const blocked=await c.query("SELECT 1 FROM social_blocks WHERE (blocker_user_id=$1 AND blocked_user_id=$2) OR (blocker_user_id=$2 AND blocked_user_id=$1)",[userId,targetUserId]);
      if(blocked.rowCount) throw new Error("SOCIAL_BLOCKED");
      const existing=await c.query<{status:string;requested_by:string}>("SELECT status,requested_by FROM social_friendships WHERE user_a=$1 AND user_b=$2 FOR UPDATE",[a,b]);
      if(existing.rows[0]){
        if(existing.rows[0].status==="accepted") throw new Error("ALREADY_FRIENDS");
        if(existing.rows[0].requested_by!==userId) {
          await c.query("UPDATE social_friendships SET status='accepted',updated_at=CURRENT_TIMESTAMP WHERE user_a=$1 AND user_b=$2",[a,b]);
          return;
        }
        throw new Error("FRIEND_REQUEST_EXISTS");
      }
      await c.query("INSERT INTO social_friendships(user_a,user_b,status,requested_by) VALUES($1,$2,'pending',$3)",[a,b,userId]);
    });
  }

  async removeFriend(userId:string,targetUserId:string):Promise<void>{
    const [a,b]=sortedPair(userId,targetUserId);
    await this.db.query("DELETE FROM social_friendships WHERE user_a=$1 AND user_b=$2",[a,b]);
  }

  async block(userId:string,targetUserId:string):Promise<void>{
    if(userId===targetUserId) throw new Error("INVALID_SOCIAL_TARGET");
    await transaction(this.db,async c=>{
      await c.query("INSERT INTO social_blocks(blocker_user_id,blocked_user_id) VALUES($1,$2) ON CONFLICT DO NOTHING",[userId,targetUserId]);
      const [a,b]=sortedPair(userId,targetUserId);
      await c.query("DELETE FROM social_friendships WHERE user_a=$1 AND user_b=$2",[a,b]);
    });
  }

  async unblock(userId:string,targetUserId:string):Promise<void>{
    await this.db.query("DELETE FROM social_blocks WHERE blocker_user_id=$1 AND blocked_user_id=$2",[userId,targetUserId]);
  }

  async blocked(userId:string):Promise<string[]>{
    const r=await this.db.query<{blocked_user_id:string}>("SELECT blocked_user_id FROM social_blocks WHERE blocker_user_id=$1 ORDER BY created_at DESC",[userId]);
    return r.rows.map(x=>x.blocked_user_id);
  }

  async report(userId:string,targetUserId:string,reason:string,details:string):Promise<string>{
    if(userId===targetUserId) throw new Error("INVALID_SOCIAL_TARGET");
    const safeReason=cleanText(reason,32);
    const safeDetails=details.trim().slice(0,512);
    const r=await this.db.query<{id:string}>("INSERT INTO social_reports(reporter_user_id,target_user_id,reason,details) VALUES($1,$2,$3,$4) RETURNING id",[userId,targetUserId,safeReason,safeDetails]);
    return r.rows[0].id;
  }

  async sendChat(userId:string,input:{channel:string;body:string;recipientUserId?:string|null;guildId?:string|null;partyId?:string|null;regionId?:number|null}):Promise<ChatMessage>{
    const ch=channel(input.channel);
    const body=cleanText(input.body,MAX_CHAT);
    const recipient=input.recipientUserId??null;
    const guildId=input.guildId??null;
    const partyId=input.partyId??null;
    const regionId=input.regionId??null;
    return transaction(this.db,async c=>{
      const blocked=recipient?await c.query("SELECT 1 FROM social_blocks WHERE (blocker_user_id=$1 AND blocked_user_id=$2) OR (blocker_user_id=$2 AND blocked_user_id=$1)",[userId,recipient]):{rowCount:0};
      if(blocked.rowCount) throw new Error("SOCIAL_BLOCKED");
      if(ch==="whisper" && !recipient) throw new Error("INVALID_CHAT_TARGET");
      if((ch==="party" || ch==="guild") && !partyId && !guildId) throw new Error("INVALID_CHAT_CONTEXT");
      if(ch==="party"){
        const m=await c.query("SELECT 1 FROM party_members WHERE party_id=$1 AND user_id=$2",[partyId,userId]);
        if(!m.rowCount) throw new Error("PARTY_MEMBERSHIP_REQUIRED");
      }
      if(ch==="guild"){
        const m=await c.query("SELECT 1 FROM guild_members WHERE guild_id=$1 AND user_id=$2",[guildId,userId]);
        if(!m.rowCount) throw new Error("GUILD_MEMBERSHIP_REQUIRED");
      }
      const rate=await c.query<{count:number}>("SELECT COUNT(*)::int count FROM chat_messages WHERE sender_user_id=$1 AND created_at>CURRENT_TIMESTAMP-INTERVAL '10 seconds'",[userId]);
      if(Number(rate.rows[0]?.count??0)>=8) throw new Error("CHAT_RATE_LIMITED");
      const r=await c.query<{id:string;created_at:Date}>(
        "INSERT INTO chat_messages(sender_user_id,recipient_user_id,guild_id,party_id,channel,region_id,body) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id,created_at",
        [userId,recipient,guildId,partyId,ch,regionId,body]);
      return {id:r.rows[0].id,senderUserId:userId,recipientUserId:recipient,guildId,partyId,channel:ch,regionId,body,createdAt:r.rows[0].created_at.toISOString()};
    });
  }

  async chatHistory(userId:string,input:{channel:string;recipientUserId?:string|null;guildId?:string|null;partyId?:string|null;regionId?:number|null;limit?:number}):Promise<ChatMessage[]>{
    const ch=channel(input.channel);const limit=Math.min(100,Math.max(1,input.limit??50));
    if(ch==="whisper" && !input.recipientUserId) throw new Error("INVALID_CHAT_TARGET");
    if(ch==="party"){
      if(!input.partyId) throw new Error("INVALID_CHAT_CONTEXT");
      const member=await this.db.query("SELECT 1 FROM party_members WHERE party_id=$1 AND user_id=$2",[input.partyId,userId]);
      if(!member.rowCount) throw new Error("PARTY_MEMBERSHIP_REQUIRED");
    }
    if(ch==="guild"){
      if(!input.guildId) throw new Error("INVALID_CHAT_CONTEXT");
      const member=await this.db.query("SELECT 1 FROM guild_members WHERE guild_id=$1 AND user_id=$2",[input.guildId,userId]);
      if(!member.rowCount) throw new Error("GUILD_MEMBERSHIP_REQUIRED");
    }
    const r=await this.db.query<{id:string;sender_user_id:string;recipient_user_id:string|null;guild_id:string|null;party_id:string|null;channel:ChatChannel;region_id:number|null;body:string;created_at:Date}>(
      ch==="whisper"
        ?"SELECT id::text,sender_user_id,recipient_user_id,guild_id,party_id,channel,region_id,body,created_at FROM chat_messages WHERE channel='whisper' AND ((sender_user_id=$1 AND recipient_user_id=$2) OR (sender_user_id=$2 AND recipient_user_id=$1)) ORDER BY id DESC LIMIT $3"
        :"SELECT id::text,sender_user_id,recipient_user_id,guild_id,party_id,channel,region_id,body,created_at FROM chat_messages WHERE channel=$1 AND ($2::uuid IS NULL OR guild_id=$2) AND ($3::uuid IS NULL OR party_id=$3) AND ($4::int IS NULL OR region_id=$4) ORDER BY id DESC LIMIT $5",
      ch==="whisper"
        ?[userId,input.recipientUserId??"",limit]
        : [ch,input.guildId??null,input.partyId??null,input.regionId??null,limit]);
    return r.rows.reverse().map(x=>({id:x.id,senderUserId:x.sender_user_id,recipientUserId:x.recipient_user_id,guildId:x.guild_id,partyId:x.party_id,channel:x.channel,regionId:x.region_id,body:x.body,createdAt:x.created_at.toISOString()}));
  }

  async createParty(userId:string):Promise<PartyState>{
    return transaction(this.db,async c=>{
      const existing=await c.query("SELECT party_id FROM party_members WHERE user_id=$1",[userId]);
      if(existing.rowCount) throw new Error("ALREADY_IN_PARTY");
      const p=await c.query<{id:string}>("INSERT INTO parties(leader_user_id) VALUES($1) RETURNING id",[userId]);
      await c.query("INSERT INTO party_members(party_id,user_id,role) VALUES($1,$2,'leader')",[p.rows[0].id,userId]);
      return this.partyWithClient(c,p.rows[0].id);
    });
  }

  private async partyWithClient(c:PoolClient,partyId:string):Promise<PartyState>{
    const p=await c.query<{id:string;leader_user_id:string}>("SELECT id,leader_user_id FROM parties WHERE id=$1",[partyId]);
    if(!p.rows[0]) throw new Error("PARTY_NOT_FOUND");
    const m=await c.query<{user_id:string;role:"leader"|"member";joined_at:Date}>("SELECT user_id,role,joined_at FROM party_members WHERE party_id=$1 ORDER BY joined_at,user_id",[partyId]);
    return {id:p.rows[0].id,leaderUserId:p.rows[0].leader_user_id,members:m.rows.map(x=>({userId:x.user_id,role:x.role,joinedAt:x.joined_at.toISOString()}))};
  }


  async inviteToParty(userId:string,targetUserId:string):Promise<string>{
    return transaction(this.db,async c=>{
      const p=await c.query<{party_id:string}>("SELECT party_id FROM party_members WHERE user_id=$1",[userId]);
      if(!p.rows[0]) throw new Error("PARTY_NOT_FOUND");
      const members=await c.query("SELECT 1 FROM party_members WHERE party_id=$1 FOR UPDATE",[p.rows[0].party_id]);
      if(members.rowCount!>=PARTY_LIMIT) throw new Error("PARTY_FULL");
      const target=await c.query("SELECT 1 FROM users WHERE id=$1",[targetUserId]);
      if(!target.rowCount) throw new Error("PLAYER_NOT_FOUND");
      const already=await c.query("SELECT 1 FROM party_members WHERE user_id=$1",[targetUserId]);
      if(already.rowCount) throw new Error("TARGET_IN_PARTY");
      const r=await c.query<{id:string}>("INSERT INTO party_invitations(party_id,inviter_user_id,invitee_user_id) VALUES($1,$2,$3) RETURNING id",[p.rows[0].party_id,userId,targetUserId]);
      return r.rows[0].id;
    });
  }

  async partyInvitations(userId:string):Promise<PartyInvitation[]>{
    const r=await this.db.query<{id:string;party_id:string;inviter_user_id:string;created_at:Date}>("SELECT id,party_id,inviter_user_id,created_at FROM party_invitations WHERE invitee_user_id=$1 AND status='pending' ORDER BY created_at DESC",[userId]);
    return r.rows;
  }

  async acceptPartyInvite(userId:string,invitationId:string):Promise<PartyState>{
    return transaction(this.db,async c=>{
      const inv=await c.query<{party_id:string;inviter_user_id:string}>("SELECT party_id,inviter_user_id FROM party_invitations WHERE id=$1 AND invitee_user_id=$2 AND status='pending' FOR UPDATE",[invitationId,userId]);
      if(!inv.rows[0]) throw new Error("PARTY_INVITATION_NOT_FOUND");
      const already=await c.query("SELECT 1 FROM party_members WHERE user_id=$1",[userId]);
      if(already.rowCount) throw new Error("ALREADY_IN_PARTY");
      const members=await c.query("SELECT user_id FROM party_members WHERE party_id=$1 FOR UPDATE",[inv.rows[0].party_id]);
      if(members.rowCount!>=PARTY_LIMIT) throw new Error("PARTY_FULL");
      await c.query("INSERT INTO party_members(party_id,user_id,role) VALUES($1,$2,'member')",[inv.rows[0].party_id,userId]);
      await c.query("UPDATE party_invitations SET status='accepted',responded_at=CURRENT_TIMESTAMP WHERE id=$1",[invitationId]);
      return this.partyWithClient(c,inv.rows[0].party_id);
    });
  }

  async leaveParty(userId:string):Promise<void>{
    await transaction(this.db,async c=>{
      const p=await c.query<{party_id:string;role:string}>("SELECT party_id,role FROM party_members WHERE user_id=$1 FOR UPDATE",[userId]);
      if(!p.rows[0]) throw new Error("PARTY_NOT_FOUND");
      const party=await c.query<{leader_user_id:string}>("SELECT leader_user_id FROM parties WHERE id=$1 FOR UPDATE",[p.rows[0].party_id]);
      await c.query("DELETE FROM party_members WHERE party_id=$1 AND user_id=$2",[p.rows[0].party_id,userId]);
      if(party.rows[0]?.leader_user_id===userId){
        const next=await c.query<{user_id:string}>("SELECT user_id FROM party_members WHERE party_id=$1 ORDER BY joined_at,user_id LIMIT 1",[p.rows[0].party_id]);
        if(next.rows[0]){
          await c.query("UPDATE parties SET leader_user_id=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[p.rows[0].party_id,next.rows[0].user_id]);
          await c.query("UPDATE party_members SET role='member' WHERE party_id=$1",[p.rows[0].party_id]);
          await c.query("UPDATE party_members SET role='leader' WHERE party_id=$1 AND user_id=$2",[p.rows[0].party_id,next.rows[0].user_id]);
        }else await c.query("DELETE FROM parties WHERE id=$1",[p.rows[0].party_id]);
      }
    });
  }

  async kickFromParty(userId:string,targetUserId:string):Promise<void>{
    await transaction(this.db,async c=>{
      const p=await c.query<{party_id:string}>("SELECT party_id FROM party_members WHERE user_id=$1 AND role='leader' FOR UPDATE",[userId]);
      if(!p.rows[0]) throw new Error("PARTY_LEADER_REQUIRED");
      if(userId===targetUserId) throw new Error("INVALID_PARTY_TARGET");
      const r=await c.query("DELETE FROM party_members WHERE party_id=$1 AND user_id=$2",[p.rows[0].party_id,targetUserId]);
      if(!r.rowCount) throw new Error("PARTY_MEMBER_NOT_FOUND");
      await c.query("UPDATE parties SET updated_at=CURRENT_TIMESTAMP WHERE id=$1",[p.rows[0].party_id]);
    });
  }

  async partyForUser(userId:string):Promise<PartyState|null>{
    const r=await this.db.query<{party_id:string}>("SELECT party_id FROM party_members WHERE user_id=$1",[userId]);
    if(!r.rows[0]) return null;
    const c=await this.db.connect();
    try{return await this.partyWithClient(c,r.rows[0].party_id)}finally{c.release();}
  }
}
