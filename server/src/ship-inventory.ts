import type {Pool} from "pg";

export class ShipInventoryStore {
  constructor(private readonly db:Pool) {}
  async mutate(userId:string,shipId:string,itemId:string,delta:number,requestId:string,fingerprint:string):Promise<{items:Array<{itemId:string;quantity:number}>;transactionId:string}>{
    if(!itemId || !Number.isSafeInteger(delta) || delta===0 || Math.abs(delta)>1_000_000) throw new Error("INVALID_SHIP_CARGO");
    if(!requestId||requestId.length>128) throw new Error("INVALID_REQUEST_ID");
    const c=await this.db.connect();
    try{
      await c.query("BEGIN");
      const requestKey=userId+":"+requestId;
      const inserted=await c.query<{transaction_id:string}>("INSERT INTO ship_cargo_requests(request_key,user_id,fingerprint,response) VALUES($1,$2,$3,'{}'::jsonb) ON CONFLICT(request_key) DO NOTHING RETURNING transaction_id",[requestKey,userId,fingerprint]);
      let transactionId:string;
      if(!inserted.rows[0]){
        const existing=await c.query<{fingerprint:string;transaction_id:string;response:{transactionId?:string;items?:Array<{itemId:string;quantity:number}>}}>("SELECT fingerprint,transaction_id,response FROM ship_cargo_requests WHERE request_key=$1 FOR UPDATE",[requestKey]);
        if(!existing.rows[0]) throw new Error("SHIP_CARGO_REQUEST_NOT_FOUND");
        if(existing.rows[0].fingerprint!==fingerprint) throw new Error("SHIP_CARGO_REQUEST_CONFLICT");
        if(!existing.rows[0].response.transactionId) throw new Error("SHIP_CARGO_REQUEST_INCOMPLETE");
        const responseRows=await c.query<{item_id:string;quantity:string}>("SELECT i.item_id,i.quantity FROM ship_inventory i WHERE i.ship_id=$1 ORDER BY i.item_id",[shipId]);
      const responseItems=responseRows.rows.map(x=>({itemId:x.item_id,quantity:Number(x.quantity)}));
      await c.query("UPDATE ship_cargo_requests SET response=$2::jsonb WHERE request_key=$1",[requestKey,JSON.stringify({transactionId,items:responseItems})]);
      await c.query("COMMIT");
        return {items:existing.rows[0].response.items??[],transactionId:existing.rows[0].transaction_id};
      }
      transactionId=inserted.rows[0].transaction_id;
      const ship=await c.query<{cargo_capacity:number}>("SELECT cargo_capacity FROM player_ships WHERE id=$1 AND owner_user_id=$2 FOR UPDATE",[shipId,userId]);
      if(!ship.rows[0]) throw new Error("SHIP_NOT_FOUND");
      const locked=await c.query<{item_id:string;quantity:string}>("SELECT item_id,quantity FROM ship_inventory WHERE ship_id=$1 FOR UPDATE",[shipId]);
      const current=locked.rows.find(x=>x.item_id===itemId);
      const next=Number(current?.quantity??0)+delta;
      if(next<0) throw new Error("INSUFFICIENT_SHIP_CARGO");
      const totalNext=locked.rows.reduce((sum,row)=>sum+Number(row.quantity),0)+delta;
      if(!Number.isSafeInteger(totalNext) || totalNext>ship.rows[0].cargo_capacity) throw new Error("SHIP_CARGO_CAPACITY_EXCEEDED");
      await c.query("INSERT INTO ship_inventory(ship_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(ship_id,item_id) DO UPDATE SET quantity=EXCLUDED.quantity,updated_at=CURRENT_TIMESTAMP",[shipId,itemId,next]);
      await c.query("COMMIT");
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release()}
    return {items:responseItems,transactionId};
  }
}
