import type { Pool } from "pg";

export interface Fleet {
  id:string;
  ownerUserId:string;
  name:string;
  commanderShipId:string|null;
  shipIds:string[];
}

export class FleetStore {
  constructor(private readonly db:Pool) {}

  async create(userId:string,name:string,shipId:string):Promise<Fleet>{
    const c=await this.db.connect();
    try{
      await c.query("BEGIN");
      const ship=await c.query<{id:string}>("SELECT id FROM player_ships WHERE id=$1 AND owner_user_id=$2 FOR UPDATE",[shipId,userId]);
      if(!ship.rows[0]) throw new Error("SHIP_NOT_FOUND");
      const existing=await c.query<{fleet_id:string}>("SELECT fleet_id FROM ship_fleet_members WHERE ship_id=$1 FOR UPDATE",[shipId]);
      if(existing.rows[0]) throw new Error("SHIP_ALREADY_IN_FLEET");
      const fleet=await c.query<{id:string}>("INSERT INTO ship_fleets(owner_user_id,name,commander_ship_id) VALUES($1,$2,$3) RETURNING id",[userId,name.trim().slice(0,64)||"Fleet",shipId]);
      await c.query("INSERT INTO ship_fleet_members(fleet_id,ship_id) VALUES($1,$2)",[fleet.rows[0].id,shipId]);
      await c.query("COMMIT");
      return {id:fleet.rows[0].id,ownerUserId:userId,name:name.trim().slice(0,64)||"Fleet",commanderShipId:shipId,shipIds:[shipId]};
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release()}
  }

  async list(userId:string):Promise<Fleet[]>{
    const r=await this.db.query<{id:string;owner_user_id:string;name:string;commander_ship_id:string|null;ship_ids:string[]}>(
      "SELECT f.id,f.owner_user_id,f.name,f.commander_ship_id,COALESCE(array_agg(m.ship_id ORDER BY m.created_at) FILTER (WHERE m.ship_id IS NOT NULL),'{}')::text[] AS ship_ids FROM ship_fleets f LEFT JOIN ship_fleet_members m ON m.fleet_id=f.id WHERE f.owner_user_id=$1 GROUP BY f.id ORDER BY f.created_at,f.id",
      [userId]);
    return r.rows.map(x=>({id:x.id,ownerUserId:x.owner_user_id,name:x.name,commanderShipId:x.commander_ship_id,shipIds:x.ship_ids}));
  }

  async addShip(userId:string,fleetId:string,shipId:string):Promise<Fleet>{
    const c=await this.db.connect();
    try{
      await c.query("BEGIN");
      const fleet=await c.query<{id:string;name:string;commander_ship_id:string|null}>("SELECT id,name,commander_ship_id FROM ship_fleets WHERE id=$1 AND owner_user_id=$2 FOR UPDATE",[fleetId,userId]);
      if(!fleet.rows[0]) throw new Error("FLEET_NOT_FOUND");
      const ship=await c.query<{id:string}>("SELECT id FROM player_ships WHERE id=$1 AND owner_user_id=$2 FOR UPDATE",[shipId,userId]);
      if(!ship.rows[0]) throw new Error("SHIP_NOT_FOUND");
      const existing=await c.query<{fleet_id:string}>("SELECT fleet_id FROM ship_fleet_members WHERE ship_id=$1 FOR UPDATE",[shipId]);
      if(existing.rows[0]) throw new Error("SHIP_ALREADY_IN_FLEET");
      await c.query("INSERT INTO ship_fleet_members(fleet_id,ship_id) VALUES($1,$2)",[fleetId,shipId]);
      const members=await c.query<{ship_id:string}>("SELECT ship_id FROM ship_fleet_members WHERE fleet_id=$1 ORDER BY created_at",[fleetId]);
      await c.query("COMMIT");
      return {id:fleetId,ownerUserId:userId,name:fleet.rows[0].name,commanderShipId:fleet.rows[0].commander_ship_id,shipIds:members.rows.map(x=>x.ship_id)};
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release()}
  }

  async removeShip(userId:string,fleetId:string,shipId:string):Promise<Fleet>{
    const c=await this.db.connect();
    try{
      await c.query("BEGIN");
      const fleet=await c.query<{id:string;name:string;commander_ship_id:string|null}>("SELECT id,name,commander_ship_id FROM ship_fleets WHERE id=$1 AND owner_user_id=$2 FOR UPDATE",[fleetId,userId]);
      if(!fleet.rows[0]) throw new Error("FLEET_NOT_FOUND");
      if(fleet.rows[0].commander_ship_id===shipId) throw new Error("FLEET_COMMANDER_REQUIRED");
      const removed=await c.query("DELETE FROM ship_fleet_members WHERE fleet_id=$1 AND ship_id=$2",[fleetId,shipId]);
      if(removed.rowCount===0) throw new Error("SHIP_NOT_IN_FLEET");
      const members=await c.query<{ship_id:string}>("SELECT ship_id FROM ship_fleet_members WHERE fleet_id=$1 ORDER BY created_at",[fleetId]);
      await c.query("COMMIT");
      return {id:fleetId,ownerUserId:userId,name:fleet.rows[0].name,commanderShipId:fleet.rows[0].commander_ship_id,shipIds:members.rows.map(x=>x.ship_id)};
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release()}
  }
}
