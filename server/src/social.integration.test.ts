import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { SocialStore } from "./social.js";

async function users(){
  const db=createDbPool();const app=await buildApp({db});
  const create=async(prefix:string)=>{
    const id=randomUUID().replace(/-/g,"").slice(0,20);
    const r=await app.inject({method:"POST",url:"/auth/register",payload:{username:prefix+"_"+id,email:prefix+"_"+id+"@example.com",password:"Correct-Horse-Battery-9"}});
    expect(r.statusCode).toBe(201);return (JSON.parse(r.body) as {user:{id:string}}).user.id;
  };
  return {db,app,a:await create("sociala"),b:await create("socialb"),c:await create("socialc")};
}

describe("Gate 14 social authority",()=>{
  it("creates, accepts and removes friend relationships and enforces blocks",async()=>{
    const {db,app,a,b}=await users();const social=new SocialStore(db);
    try{
      await social.addFriend(a,b);
      expect((await social.friends(a))[0]).toMatchObject({userId:b,status:"pending",requestedBy:a});
      await social.addFriend(b,a);
      expect((await social.friends(a))[0]).toMatchObject({userId:b,status:"accepted"});
      await social.block(a,b);
      expect(await social.friends(a)).toEqual([]);
      await expect(social.addFriend(a,b)).rejects.toThrow("SOCIAL_BLOCKED");
      await social.unblock(a,b);
      await social.addFriend(a,b);
      expect((await social.friends(a))[0].status).toBe("pending");
    }finally{await app.close();await db.end();}
  });

  it("persists chat and enforces party/guild authorization plus server-side rate limits",async()=>{
    const {db,app,a,b}=await users();const social=new SocialStore(db);
    try{
      const msg=await social.sendChat(a,{channel:"global",body:"hello"});
      expect(msg).toMatchObject({senderUserId:a,channel:"global",body:"hello"});
      expect((await social.chatHistory(a,{channel:"global"})).some(x=>x.id===msg.id)).toBe(true);
      await expect(social.sendChat(a,{channel:"party",body:"no party"})).rejects.toThrow("INVALID_CHAT_CONTEXT");
      for(let i=0;i<7;i++) await social.sendChat(a,{channel:"global",body:"rate"});
      await expect(social.sendChat(a,{channel:"global",body:"blocked"})).rejects.toThrow("CHAT_RATE_LIMITED");
      await social.block(b,a);
      await expect(social.sendChat(a,{channel:"whisper",body:"blocked",recipientUserId:b})).rejects.toThrow("SOCIAL_BLOCKED");
    }finally{await app.close();await db.end();}
  });

  it("creates parties with authoritative single-membership and leader succession",async()=>{
    const {db,app,a,b,c}=await users();const social=new SocialStore(db);
    try{
      const party=await social.createParty(a);expect(party.leaderUserId).toBe(a);
      await social.inviteToParty(a,b);const joined=await social.acceptPartyInvite(b,(await social.partyInvitations(b))[0].id);
      expect(joined.members.map(x=>x.userId).sort()).toEqual([a,b].sort());
      await social.inviteToParty(a,c);const joined2=await social.acceptPartyInvite(c,(await social.partyInvitations(c))[0].id);
      expect(joined2.members).toHaveLength(3);
      await social.leaveParty(a);
      expect((await social.partyForUser(b))?.leaderUserId).toBe(b);
      expect((await social.partyForUser(c))?.leaderUserId).toBe(b);
      await expect(social.createParty(b)).rejects.toThrow("ALREADY_IN_PARTY");
    }finally{await app.close();await db.end();}
  });

  it("keeps report records authoritative and bounded",async()=>{
    const {db,app,a,b}=await users();const social=new SocialStore(db);
    try{
      const id=await social.report(a,b,"harassment","test report");
      const row=await db.query("SELECT reporter_user_id,target_user_id,reason,details,status FROM social_reports WHERE id=$1",[id]);
      expect(row.rows[0]).toMatchObject({reporter_user_id:a,target_user_id:b,reason:"harassment",details:"test report",status:"open"});
    }finally{await app.close();await db.end();}
  });
});
