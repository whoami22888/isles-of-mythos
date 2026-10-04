import type {Pool} from "pg";

export class ShipInventoryStore {
  constructor(private readonly db:Pool) {}
  async mutate(userId:string,shipId:string,itemId:string,delta:number){
    if(!itemId || !Number.isSafeInteger(delta) || delta===0 || Math.abs(delta)>1_000_000) throw new Error("INVALID_SHIP_CARGO");
    const c=await this.db.connect();
    try{
      await c.query("BEGIN");
      const ship=await c.query<{cargo_capacity:number}>("SELECT cargo_capacity FROM player_ships WHERE id=$1 AND owner_user_id=$2 FOR UPDATE",[shipId,userId]);
      if(!ship.rows[0]) throw new Error("SHIP_NOT_FOUND");
      const locked=await c.query<{item_id:string;quantity:string}>("SELECT item_id,quantity FROM ship_inventory WHERE ship_id=$1 FOR UPDATE",[shipId]);
      const current=locked.find(x=>x.item_id===itemId);
      const next=Number(current?.quantity??0)+delta;
      if(next<0) throw new Error("INSUFFICIENT_SHIP_CARGO");
      const totalNext=locked.reduce((sum,row)=>sum+Number(row.quantity),0)+delta;
      if(!Number.isSafeInteger(totalNext) || totalNext>ship.rows[0].cargo_capacity) throw new Error("SHIP_CARGO_CAPACITY_EXCEEDED");
      await c.query("INSERT INTO ship_inventory(ship_id,item_id,quantity) VALUES($1,$2,$3) ON CONFLICT(ship_id,item_id) DO UPDATE SET quantity=EXCLUDED.quantity,updated_at=CURRENT_TIMESTAMP",[shipId,itemId,next]);
      await c.query("COMMIT");
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release()}
    const rows=await this.db.query<{item_id:string;quantity:string}>("SELECT i.item_id,i.quantity FROM ship_inventory i JOIN player_ships s ON s.id=i.ship_id WHERE i.ship_id=$1 AND s.owner_user_id=$2 ORDER BY i.item_id",[shipId,userId]);
    return rows.rows.map(x=>({itemId:x.item_id,quantity:Number(x.quantity)}));
  }
}
