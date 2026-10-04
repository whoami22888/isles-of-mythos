import type { Pool, PoolClient } from "pg";
import { addGoldDoubloons, applyInventoryDelta, cloneInventory, parseGoldDoubloons, subtractGoldDoubloons, type Inventory } from "./economy.js";

const MAX_QTY=1_000_000;
const MAX_DURATION_MS=7*24*60*60*1000;
const DEFAULT_FEE_BPS=500;

function itemId(value:string):string{
  if(typeof value!=="string"||value.length<1||value.length>128||!/^[a-z0-9]+(?:[._-][a-z0-9]+)*$/.test(value)) throw new Error("INVALID_AUCTION_ITEM");
  return value;
}
function positiveInt(value:number,code:string):number{
  if(!Number.isSafeInteger(value)||value<1||value>MAX_QTY) throw new Error(code);
  return value;
}
async function tx<T>(db:Pool,fn:(c:PoolClient)=>Promise<T>):Promise<T>{
  const c=await db.connect();try{await c.query("BEGIN");const v=await fn(c);await c.query("COMMIT");return v}catch(e){await c.query("ROLLBACK");throw e}finally{c.release();}
}
async function lockUsers(c:PoolClient,ids:string[]):Promise<Map<string,{user_id:string;gold:string;inventory:Inventory}>>{
  const unique=[...new Set(ids)].sort();
  const r=await c.query<{user_id:string;gold:string;inventory:Inventory}>("SELECT user_id,gold,inventory FROM player_profiles WHERE user_id=ANY($1::uuid[]) ORDER BY user_id FOR UPDATE",[unique]);
  if(r.rows.length!==unique.length) throw new Error("PLAYER_NOT_FOUND");
  return new Map(r.rows.map(x=>[x.user_id,x]));
}
function fee(gross:bigint,bps:number):bigint{return (gross*BigInt(bps)+9999n)/10000n;}

export interface AuctionSummary{id:string;sellerUserId:string;itemId:string;quantity:number;remainingQuantity:number;startPrice:string;buyNowPrice:string|null;currentBid:string;highestBidderUserId:string|null;status:string;expiresAt:string;}

export class AuctionStore{
  constructor(private readonly db:Pool){}

  private async settleExpired(c:PoolClient,limit=50):Promise<number>{
    const rows=await c.query<{id:string}>("SELECT id FROM auction_listings WHERE status='active' AND expires_at<=CURRENT_TIMESTAMP ORDER BY expires_at,id LIMIT $1 FOR UPDATE SKIP LOCKED",[limit]);
    let count=0;for(const row of rows.rows){await this.settleLocked(c,row.id);count++;}return count;
  }

  private async settleLocked(c:PoolClient,id:string):Promise<void>{
    const l=await c.query<{id:string;seller_user_id:string;item_id:string;quantity:number;remaining_quantity:number;current_bid:string;highest_bidder_user_id:string|null;seller_fee_bps:number;status:string}>("SELECT id,seller_user_id,item_id,quantity,remaining_quantity,current_bid,highest_bidder_user_id,seller_fee_bps,status FROM auction_listings WHERE id=$1 FOR UPDATE",[id]);
    const listing=l.rows[0];if(!listing||listing.status!=="active")return;
    if(listing.highest_bidder_user_id && BigInt(listing.current_bid)>0n){
      const users=await lockUsers(c,[listing.seller_user_id,listing.highest_bidder_user_id]);
      const seller=users.get(listing.seller_user_id)!;const buyer=users.get(listing.highest_bidder_user_id)!;
      const gross=parseGoldDoubloons(listing.current_bid);const sellerFee=fee(gross,listing.seller_fee_bps);const net=gross-sellerFee;
      let buyerInv=cloneInventory(buyer.inventory);buyerInv=applyInventoryDelta(buyerInv,listing.item_id,listing.remaining_quantity);
      const sellerGold=addGoldDoubloons(parseGoldDoubloons(seller.gold),net);
      await c.query("UPDATE player_profiles SET inventory=$2::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[buyer.user_id,JSON.stringify(buyerInv)]);
      await c.query("UPDATE player_profiles SET gold=$2,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[seller.user_id,sellerGold.toString()]);
      await c.query("UPDATE auction_bids SET status=CASE WHEN bidder_user_id=$2 THEN 'won' ELSE 'refunded' END,settled_at=CURRENT_TIMESTAMP WHERE listing_id=$1 AND status='held'",[id,buyer.user_id]);
      await c.query("INSERT INTO auction_transactions(listing_id,buyer_user_id,seller_user_id,item_id,quantity,gross_gold,seller_fee,net_gold,transaction_type) VALUES($1,$2,$3,$4,$5,$6,$7,$8,'bid_settlement')",[id,buyer.user_id,seller.user_id,listing.item_id,listing.remaining_quantity,gross.toString(),sellerFee.toString(),net.toString()]);
    }else{
      const users=await lockUsers(c,[listing.seller_user_id]);const seller=users.get(listing.seller_user_id)!;
      let inv=cloneInventory(seller.inventory);inv=applyInventoryDelta(inv,listing.item_id,listing.remaining_quantity);
      await c.query("UPDATE player_profiles SET inventory=$2::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[seller.user_id,JSON.stringify(inv)]);
      await c.query("INSERT INTO auction_transactions(listing_id,buyer_user_id,seller_user_id,item_id,quantity,gross_gold,seller_fee,net_gold,transaction_type) VALUES($1,NULL,$2,$3,$4,0,0,0,'expiry_return')",[id,seller.user_id,listing.item_id,listing.remaining_quantity]);
      await c.query("UPDATE auction_bids SET status='refunded',settled_at=CURRENT_TIMESTAMP WHERE listing_id=$1 AND status='held'",[id]);
    }
    await c.query("UPDATE auction_listings SET status=CASE WHEN highest_bidder_user_id IS NULL THEN 'expired' ELSE 'sold' END,remaining_quantity=0,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[id]);
  }

  async tick():Promise<number>{return tx(this.db,c=>this.settleExpired(c,100));}

  async create(sellerUserId:string,input:{itemId:string;quantity:number;startPrice:string;buyNowPrice?:string|null;durationMs:number}):Promise<AuctionSummary>{
    const item=itemId(input.itemId);const quantity=positiveInt(input.quantity,"INVALID_AUCTION_QUANTITY");
    const start=parseGoldDoubloons(input.startPrice);if(start<=0n)throw new Error("INVALID_AUCTION_PRICE");
    const buy=input.buyNowPrice==null?null:parseGoldDoubloons(input.buyNowPrice);
    if(buy!==null && buy<start)throw new Error("INVALID_AUCTION_PRICE");
    if(!Number.isSafeInteger(input.durationMs)||input.durationMs<60_000||input.durationMs>MAX_DURATION_MS)throw new Error("INVALID_AUCTION_DURATION");
    return tx(this.db,async c=>{
      await this.settleExpired(c,20);const users=await lockUsers(c,[sellerUserId]);const seller=users.get(sellerUserId)!;
      let inv=cloneInventory(seller.inventory);inv=applyInventoryDelta(inv,item,-quantity);
      const r=await c.query<{id:string;expires_at:Date}>("INSERT INTO auction_listings(seller_user_id,item_id,quantity,remaining_quantity,start_price,buy_now_price,seller_fee_bps,expires_at) VALUES($1,$2,$3,$3,$4,$5,$6,CURRENT_TIMESTAMP+($7::bigint*INTERVAL '1 millisecond')) RETURNING id,expires_at",[sellerUserId,item,quantity,start.toString(),buy?.toString()??null,DEFAULT_FEE_BPS,input.durationMs]);
      await c.query("UPDATE player_profiles SET inventory=$2::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[sellerUserId,JSON.stringify(inv)]);
      return {id:r.rows[0].id,sellerUserId,itemId:item,quantity,remainingQuantity:quantity,startPrice:start.toString(),buyNowPrice:buy?.toString()??null,currentBid:"0",highestBidderUserId:null,status:"active",expiresAt:r.rows[0].expires_at.toISOString()};
    });
  }

  async list(filters:{itemId?:string|null;minPrice?:string|null;maxPrice?:string|null;limit?:number}={}):Promise<AuctionSummary[]>{
    await this.tick();const limit=Math.min(100,Math.max(1,filters.limit??50));const clauses=["status='active'","expires_at>CURRENT_TIMESTAMP"];const params:unknown[]=[];let n=1;
    if(filters.itemId){clauses.push("item_id=$"+n++);params.push(itemId(filters.itemId));}
    if(filters.minPrice){clauses.push("start_price >= $"+n++);params.push(parseGoldDoubloons(filters.minPrice).toString());}
    if(filters.maxPrice){clauses.push("start_price <= $"+n++);params.push(parseGoldDoubloons(filters.maxPrice).toString());}
    params.push(limit);
    const sql="SELECT id,seller_user_id,item_id,quantity,remaining_quantity,start_price,buy_now_price,current_bid,highest_bidder_user_id,status,expires_at FROM auction_listings WHERE "+clauses.join(" AND ")+" ORDER BY expires_at,id LIMIT $"+n;
    const r=await this.db.query<{id:string;seller_user_id:string;item_id:string;quantity:number;remaining_quantity:number;start_price:string;buy_now_price:string|null;current_bid:string;highest_bidder_user_id:string|null;status:string;expires_at:Date}>(sql,params);
    return r.rows.map(x=>({id:x.id,sellerUserId:x.seller_user_id,itemId:x.item_id,quantity:x.quantity,remainingQuantity:x.remaining_quantity,startPrice:x.start_price,buyNowPrice:x.buy_now_price,currentBid:x.current_bid,highestBidderUserId:x.highest_bidder_user_id,status:x.status,expiresAt:x.expires_at.toISOString()}));
  }

  async bid(bidderUserId:string,listingId:string,amount:string):Promise<AuctionSummary>{
    const bid=parseGoldDoubloons(amount);if(bid<=0n)throw new Error("INVALID_AUCTION_BID");
    return tx(this.db,async c=>{
      await this.settleExpired(c,20);
      const l=await c.query<{id:string;seller_user_id:string;item_id:string;remaining_quantity:number;start_price:string;buy_now_price:string|null;current_bid:string;highest_bidder_user_id:string|null;seller_fee_bps:number;status:string;expires_at:Date}>("SELECT id,seller_user_id,item_id,remaining_quantity,start_price,buy_now_price,current_bid,highest_bidder_user_id,seller_fee_bps,status,expires_at FROM auction_listings WHERE id=$1 FOR UPDATE",[listingId]);
      const listing=l.rows[0];if(!listing)throw new Error("AUCTION_NOT_FOUND");if(listing.status!=="active"||new Date(listing.expires_at).getTime()<=Date.now())throw new Error("AUCTION_NOT_ACTIVE");
      if(listing.seller_user_id===bidderUserId)throw new Error("AUCTION_SELF_BID");
      const current=BigInt(listing.current_bid);const minimum=current>0n?current+1n:BigInt(listing.start_price);if(bid<minimum)throw new Error("AUCTION_BID_TOO_LOW");
      const users=await lockUsers(c,[bidderUserId,...(listing.highest_bidder_user_id?[listing.highest_bidder_user_id]:[])]);const bidder=users.get(bidderUserId)!;
      const bidderGold=subtractGoldDoubloons(parseGoldDoubloons(bidder.gold),bid);
      await c.query("UPDATE player_profiles SET gold=$2,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[bidderUserId,bidderGold.toString()]);
      if(listing.highest_bidder_user_id){const previous=users.get(listing.highest_bidder_user_id)!;const refunded=addGoldDoubloons(parseGoldDoubloons(previous.gold),current);await c.query("UPDATE player_profiles SET gold=$2,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[previous.user_id,refunded.toString()]);await c.query("UPDATE auction_bids SET status='refunded',settled_at=CURRENT_TIMESTAMP WHERE listing_id=$1 AND bidder_user_id=$2 AND status='held'",[listingId,previous.user_id]);}
      await c.query("INSERT INTO auction_bids(listing_id,bidder_user_id,amount,status) VALUES($1,$2,$3,'held')",[listingId,bidderUserId,bid.toString()]);
      await c.query("UPDATE auction_listings SET current_bid=$2,highest_bidder_user_id=$3,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[listingId,bid.toString(),bidderUserId]);
      return this.summaryLocked(c,listingId);
    });
  }

  async buyNow(buyerUserId:string,listingId:string):Promise<AuctionSummary>{
    return tx(this.db,async c=>{
      await this.settleExpired(c,20);
      const l=await c.query<{id:string;seller_user_id:string;item_id:string;remaining_quantity:number;buy_now_price:string|null;current_bid:string;highest_bidder_user_id:string|null;seller_fee_bps:number;status:string;expires_at:Date}>("SELECT id,seller_user_id,item_id,remaining_quantity,buy_now_price,current_bid,highest_bidder_user_id,seller_fee_bps,status,expires_at FROM auction_listings WHERE id=$1 FOR UPDATE",[listingId]);
      const listing=l.rows[0];if(!listing)throw new Error("AUCTION_NOT_FOUND");if(listing.status!=="active")throw new Error("AUCTION_NOT_ACTIVE");if(!listing.buy_now_price)throw new Error("AUCTION_NO_BUY_NOW");
      if(listing.seller_user_id===buyerUserId)throw new Error("AUCTION_SELF_BUY");const price=parseGoldDoubloons(listing.buy_now_price);
      const users=await lockUsers(c,[buyerUserId,listing.seller_user_id,...(listing.highest_bidder_user_id?[listing.highest_bidder_user_id]:[])]);const buyer=users.get(buyerUserId)!;const seller=users.get(listing.seller_user_id)!;
      const buyerGold=subtractGoldDoubloons(parseGoldDoubloons(buyer.gold),price);let buyerInv=cloneInventory(buyer.inventory);buyerInv=applyInventoryDelta(buyerInv,listing.item_id,listing.remaining_quantity);
      const sellerFee=fee(price,listing.seller_fee_bps);const sellerGold=addGoldDoubloons(parseGoldDoubloons(seller.gold),price-sellerFee);
      await c.query("UPDATE player_profiles SET gold=$2,inventory=$3::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[buyerUserId,buyerGold.toString(),JSON.stringify(buyerInv)]);
      await c.query("UPDATE player_profiles SET gold=$2,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[seller.user_id,sellerGold.toString()]);
      if(listing.highest_bidder_user_id){const held=users.get(listing.highest_bidder_user_id)!;const refundBase=held.user_id===buyerUserId?buyerGold:parseGoldDoubloons(held.gold);const refund=addGoldDoubloons(refundBase,BigInt(listing.current_bid));await c.query("UPDATE player_profiles SET gold=$2,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[held.user_id,refund.toString()]);await c.query("UPDATE auction_bids SET status='refunded',settled_at=CURRENT_TIMESTAMP WHERE listing_id=$1 AND status='held'",[listingId]);}
      await c.query("INSERT INTO auction_transactions(listing_id,buyer_user_id,seller_user_id,item_id,quantity,gross_gold,seller_fee,net_gold,transaction_type) VALUES($1,$2,$3,$4,$5,$6,$7,$8,'buy_now')",[listingId,buyerUserId,seller.user_id,listing.item_id,listing.remaining_quantity,price.toString(),sellerFee.toString(),(price-sellerFee).toString()]);
      await c.query("UPDATE auction_listings SET status='sold',remaining_quantity=0,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[listingId]);return this.summaryLocked(c,listingId);
    });
  }

  async cancel(sellerUserId:string,listingId:string):Promise<void>{
    await tx(this.db,async c=>{
      const l=await c.query<{seller_user_id:string;item_id:string;remaining_quantity:number;status:string}>("SELECT seller_user_id,item_id,remaining_quantity,status FROM auction_listings WHERE id=$1 FOR UPDATE",[listingId]);const listing=l.rows[0];
      if(!listing)throw new Error("AUCTION_NOT_FOUND");if(listing.seller_user_id!==sellerUserId)throw new Error("AUCTION_OWNER_REQUIRED");if(listing.status!=="active")throw new Error("AUCTION_NOT_ACTIVE");
      if((await c.query("SELECT 1 FROM auction_bids WHERE listing_id=$1 AND status='held'",[listingId])).rowCount)throw new Error("AUCTION_HAS_BID");
      const users=await lockUsers(c,[sellerUserId]);const seller=users.get(sellerUserId)!;let inv=cloneInventory(seller.inventory);inv=applyInventoryDelta(inv,listing.item_id,listing.remaining_quantity);
      await c.query("UPDATE player_profiles SET inventory=$2::jsonb,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",[sellerUserId,JSON.stringify(inv)]);
      await c.query("INSERT INTO auction_transactions(listing_id,buyer_user_id,seller_user_id,item_id,quantity,gross_gold,seller_fee,net_gold,transaction_type) VALUES($1,NULL,$2,$3,$4,0,0,0,'cancel_return')",[listingId,sellerUserId,listing.item_id,listing.remaining_quantity]);
      await c.query("UPDATE auction_listings SET status='cancelled',remaining_quantity=0,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[listingId]);
    });
  }

  async history(userId:string):Promise<unknown[]>{
    return (await this.db.query("SELECT id,listing_id,buyer_user_id,seller_user_id,item_id,quantity,gross_gold,seller_fee,net_gold,transaction_type,created_at FROM auction_transactions WHERE seller_user_id=$1 OR buyer_user_id=$1 ORDER BY created_at DESC LIMIT 100",[userId])).rows;
  }

  private async summaryLocked(c:PoolClient,id:string):Promise<AuctionSummary>{
    const r=await c.query<{id:string;seller_user_id:string;item_id:string;quantity:number;remaining_quantity:number;start_price:string;buy_now_price:string|null;current_bid:string;highest_bidder_user_id:string|null;status:string;expires_at:Date}>("SELECT id,seller_user_id,item_id,quantity,remaining_quantity,start_price,buy_now_price,current_bid,highest_bidder_user_id,status,expires_at FROM auction_listings WHERE id=$1",[id]);const x=r.rows[0];
    if(!x)throw new Error("AUCTION_NOT_FOUND");return {id:x.id,sellerUserId:x.seller_user_id,itemId:x.item_id,quantity:x.quantity,remainingQuantity:x.remaining_quantity,startPrice:x.start_price,buyNowPrice:x.buy_now_price,currentBid:x.current_bid,highestBidderUserId:x.highest_bidder_user_id,status:x.status,expiresAt:x.expires_at.toISOString()};
  }
}
