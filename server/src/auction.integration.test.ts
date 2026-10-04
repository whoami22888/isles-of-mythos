import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { AuctionStore } from "./auction.js";
import { PlayerStore } from "./player.js";
import type { Pool } from "pg";

async function users(){
  const db=createDbPool();const app=await buildApp({db});
  const create=async(prefix:string)=>{
    const id=randomUUID().replace(/-/g,"").slice(0,20);
    const r=await app.inject({method:"POST",url:"/auth/register",payload:{username:prefix+"_"+id,email:prefix+"_"+id+"@example.com",password:"Correct-Horse-Battery-9"}});
    expect(r.statusCode).toBe(201);const user=(JSON.parse(r.body) as {user:{id:string}}).user.id;await new PlayerStore(db).loadOrCreate(user);return user;
  };
  return {db,app,seller:await create("auctions"),buyer:await create("auctionb"),other:await create("auctionc")};
}
async function setEconomy(db:Pool,userId:string,gold:string,inventory:Record<string,number>){
  await db.query("UPDATE player_profiles SET gold=$2,inventory=$3::jsonb WHERE user_id=$1",[userId,gold,JSON.stringify(inventory)]);
}

describe("Gate 14 auction authority",()=>{
  it("escrows listing inventory and atomically completes buy-now with seller fee",async()=>{
    const {db,app,seller,buyer}=await users();const auction=new AuctionStore(db);
    try{
      await setEconomy(db,seller,"0",{"resource.wood":10});await setEconomy(db,buyer,"1000",{});
      const listing=await auction.create(seller,{itemId:"resource.wood",quantity:4,startPrice:"100",buyNowPrice:"250",durationMs:60000});
      expect(listing.status).toBe("active");
      expect((await db.query("SELECT inventory FROM player_profiles WHERE user_id=$1",[seller])).rows[0].inventory).toEqual({"resource.wood":6});
      const sold=await auction.buyNow(buyer,listing.id);
      expect(sold.status).toBe("sold");
      const rows=await db.query("SELECT user_id,gold,inventory FROM player_profiles WHERE user_id=ANY($1::uuid[]) ORDER BY user_id",[[seller,buyer]]);
      const byUser=new Map(rows.rows.map((x:{user_id:string;gold:string;inventory:Record<string,number>})=>[x.user_id,x]));
      expect(byUser.get(seller)).toMatchObject({gold:"237"});
      expect(byUser.get(buyer)).toMatchObject({gold:"750",inventory:{"resource.wood":4}});
      expect((await auction.history(seller)).some((x:any)=>x.transaction_type==="buy_now")).toBe(true);
    }finally{await app.close();await db.end();}
  });

  it("refunds the previous bidder and never duplicates gold during a replacement bid",async()=>{
    const {db,app,seller,buyer,other}=await users();const auction=new AuctionStore(db);
    try{
      await setEconomy(db,seller,"0",{"resource.wood":5});await setEconomy(db,buyer,"500",{});await setEconomy(db,other,"700",{});
      const listing=await auction.create(seller,{itemId:"resource.wood",quantity:2,startPrice:"100",buyNowPrice:null,durationMs:60000});
      await auction.bid(buyer,listing.id,"150");await auction.bid(other,listing.id,"200");
      const rows=await db.query("SELECT user_id,gold FROM player_profiles WHERE user_id=ANY($1::uuid[]) ORDER BY user_id",[[buyer,other]]);
      const byUser=new Map(rows.rows.map((x:{user_id:string;gold:string})=>[x.user_id,x.gold]));
      expect(byUser.get(buyer)).toBe("500");
      expect(byUser.get(other)).toBe("500");
      expect((await db.query("SELECT status,amount FROM auction_bids WHERE listing_id=$1 ORDER BY created_at",[listing.id])).rows).toEqual([
        {status:"refunded",amount:"150"},{status:"held",amount:"200"}
      ]);
    }finally{await app.close();await db.end();}
  });

  it("settles an expired winning bid into item ownership and seller proceeds",async()=>{
    const {db,app,seller,buyer}=await users();const auction=new AuctionStore(db);
    try{
      await setEconomy(db,seller,"0",{"resource.wood":3});await setEconomy(db,buyer,"500",{});
      const listing=await auction.create(seller,{itemId:"resource.wood",quantity:3,startPrice:"100",buyNowPrice:null,durationMs:60000});
      await auction.bid(buyer,listing.id,"200");
      await db.query("UPDATE auction_listings SET expires_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[listing.id]);
      const settled=await auction.tick();expect(settled).toBeGreaterThanOrEqual(1);
      const rows=await db.query("SELECT user_id,gold,inventory FROM player_profiles WHERE user_id=ANY($1::uuid[]) ORDER BY user_id",[[seller,buyer]]);
      const byUser=new Map(rows.rows.map((x:any)=>[x.user_id,x]));
      expect(byUser.get(seller)).toMatchObject({gold:"190"});
      expect(byUser.get(buyer)).toMatchObject({gold:"300",inventory:{"resource.wood":3}});
      expect((await db.query("SELECT status,remaining_quantity FROM auction_listings WHERE id=$1",[listing.id])).rows[0]).toEqual({status:"sold",remaining_quantity:0});
    }finally{await app.close();await db.end();}
  });

  it("rejects cancellation after a bid and preserves escrow",async()=>{
    const {db,app,seller,buyer}=await users();const auction=new AuctionStore(db);
    try{
      await setEconomy(db,seller,"0",{"resource.wood":1});await setEconomy(db,buyer,"500",{});
      const listing=await auction.create(seller,{itemId:"resource.wood",quantity:1,startPrice:"100",buyNowPrice:null,durationMs:60000});
      await auction.bid(buyer,listing.id,"100");
      await expect(auction.cancel(seller,listing.id)).rejects.toThrow("AUCTION_HAS_BID");
      expect((await db.query("SELECT inventory FROM player_profiles WHERE user_id=$1",[seller])).rows[0].inventory).toEqual({});
    }finally{await app.close();await db.end();}
  });
});
