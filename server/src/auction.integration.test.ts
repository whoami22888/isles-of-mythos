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
      const listing=await auction.create(seller,"create-1",{itemId:"resource.wood",quantity:4,startPrice:"100",buyNowPrice:"250",durationMs:60000});
      expect(listing.listing.status).toBe("active");
      expect(listing.transactionId).toMatch(/^[0-9a-f-]{36}$/i);
      expect((await auction.list({category:"resource",rarity:"common",minLevel:1,maxLevel:1,minPrice:"100",maxPrice:"100"})).some(x=>x.id===listing.listing.id)).toBe(true);
      expect((await db.query<{inventory:Record<string,number>}>("SELECT inventory FROM player_profiles WHERE user_id=$1",[seller])).rows[0].inventory).toEqual({"resource.wood":6});
      const sold=await auction.buyNow(buyer,"buy-1",listing.listing.id);
      expect(sold.listing.status).toBe("sold");
      expect(sold.transactionId).toBeTruthy();
      const rows=await db.query<{user_id:string;gold:string;inventory:Record<string,number>}>("SELECT user_id,gold,inventory FROM player_profiles WHERE user_id=ANY($1::uuid[]) ORDER BY user_id",[[seller,buyer]]);
      const byUser=new Map(rows.rows.map((x)=>[x.user_id,x]));
      expect(byUser.get(seller)).toMatchObject({gold:"237"});
      expect(byUser.get(buyer)).toMatchObject({gold:"750",inventory:{"resource.wood":4}});
      expect((await auction.history(seller)).some((x)=>x.transaction_type==="buy_now")).toBe(true);
    }finally{await app.close();await db.end();}
  });

  it("refunds the previous bidder and never duplicates gold during a replacement bid",async()=>{
    const {db,app,seller,buyer,other}=await users();const auction=new AuctionStore(db);
    try{
      await setEconomy(db,seller,"0",{"resource.wood":5});await setEconomy(db,buyer,"500",{});await setEconomy(db,other,"700",{});
      const listing=await auction.create(seller,"create-1",{itemId:"resource.wood",quantity:2,startPrice:"100",buyNowPrice:null,durationMs:60000});
      await auction.bid(buyer,"bid-1",listing.listing.id,"150");await auction.bid(other,"bid-2",listing.listing.id,"200");
      const rows=await db.query<{user_id:string;gold:string}>("SELECT user_id,gold FROM player_profiles WHERE user_id=ANY($1::uuid[]) ORDER BY user_id",[[buyer,other]]);
      const byUser=new Map(rows.rows.map((x)=>[x.user_id,x.gold]));
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
      await auction.bid(buyer,"bid-expire",listing.listing.id,"200");
      await db.query("UPDATE auction_listings SET expires_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[listing.id]);
      const settled=await auction.tick();expect(settled).toBeGreaterThanOrEqual(1);
      const rows=await db.query<{user_id:string;gold:string;inventory:Record<string,number>}>("SELECT user_id,gold,inventory FROM player_profiles WHERE user_id=ANY($1::uuid[]) ORDER BY user_id",[[seller,buyer]]);
      const byUser=new Map(rows.rows.map((x)=>[x.user_id,x]));
      expect(byUser.get(seller)).toMatchObject({gold:"190"});
      expect(byUser.get(buyer)).toMatchObject({gold:"300",inventory:{"resource.wood":3}});
      expect((await db.query("SELECT status,remaining_quantity FROM auction_listings WHERE id=$1",[listing.id])).rows[0]).toEqual({status:"sold",remaining_quantity:0});
    }finally{await app.close();await db.end();}
  });

  it("serializes concurrent bids without allowing two winners or duplicated currency",async()=>{
    const {db,app,seller,buyer,other}=await users();const auction=new AuctionStore(db);
    try{
      await setEconomy(db,seller,"0",{"resource.wood":2});await setEconomy(db,buyer,"500",{});await setEconomy(db,other,"500",{});
      const listing=await auction.create(seller,{itemId:"resource.wood",quantity:2,startPrice:"100",buyNowPrice:null,durationMs:60000});
      const results=await Promise.allSettled([auction.bid(buyer,"concurrent-1",listing.listing.id,"150"),auction.bid(other,"concurrent-2",listing.listing.id,"200")]);
      expect(results.some(x=>x.status==="fulfilled")).toBe(true);
      const row=await db.query<{current_bid:string;highest_bidder_user_id:string|null}>("SELECT current_bid,highest_bidder_user_id FROM auction_listings WHERE id=$1",[listing.id]);
      expect(row.rows[0]).toMatchObject({current_bid:"200"});
      expect(row.rows[0].highest_bidder_user_id).toBeTruthy();
      const held=await db.query<{count:number}>("SELECT COUNT(*)::int count FROM auction_bids WHERE listing_id=$1 AND status='held'",[listing.id]);
      expect(held.rows[0].count).toBe(1);
      const balances=await db.query<{gold:string}>("SELECT gold FROM player_profiles WHERE user_id=ANY($1::uuid[])",[[buyer,other]]);
      expect(balances.rows.reduce((sum,x)=>sum+BigInt(x.gold),0n)).toBe(800n);
    }finally{await app.close();await db.end();}
  });

  it("rejects cancellation after a bid and preserves escrow",async()=>{
    const {db,app,seller,buyer}=await users();const auction=new AuctionStore(db);
    try{
      await setEconomy(db,seller,"0",{"resource.wood":1});await setEconomy(db,buyer,"500",{});
      const listing=await auction.create(seller,{itemId:"resource.wood",quantity:1,startPrice:"100",buyNowPrice:null,durationMs:60000});
      await auction.bid(buyer,"bid-cancel",listing.listing.id,"100");
      await expect(auction.cancel(seller,"cancel-1",listing.listing.id)).rejects.toThrow("AUCTION_HAS_BID");
      expect((await db.query<{inventory:Record<string,number>}>("SELECT inventory FROM player_profiles WHERE user_id=$1",[seller])).rows[0].inventory).toEqual({"resource.wood":0});
    }finally{await app.close();await db.end();}
  });
});
