import { CREATURE_STATS } from "./combat.js";
import type { Pool } from "pg";

const CREW_TYPES = ["pirate", "mermaid", "dragon", "npc_specialist"] as const;
const CREW_ROLES = ["captain", "navigator", "gunner", "engineer", "medic", "scout", "boarding_specialist"] as const;
type CrewType = typeof CREW_TYPES[number];
type CrewRole = typeof CREW_ROLES[number];

interface Row {
  id:string; owner_user_id:string; name:string; ship_class:string; hull:number; max_hull:number;
  armor:number; speed:number; turn_rate:number; cargo_capacity:number; crew_capacity:number;
  cannon_count:number; sail_power:number; fuel:number; max_fuel:number; x:number; y:number;
  heading:number; status:"active"|"destroyed"|"docked"; fire_until:Date|null; fire_damage:number;
  retreat_until:Date|null;
}
const select = "id,owner_user_id,name,ship_class,hull,max_hull,armor,speed,turn_rate,cargo_capacity,crew_capacity,cannon_count,sail_power,fuel,max_fuel,x,y,heading,status,fire_until,fire_damage,retreat_until";
const mapShip = (r:Row) => ({
  id:r.id, ownerUserId:r.owner_user_id, name:r.name, shipClass:r.ship_class, hull:r.hull, maxHull:r.max_hull,
  armor:r.armor, speed:r.speed, turnRate:r.turn_rate, cargoCapacity:r.cargo_capacity, crewCapacity:r.crew_capacity,
  cannonCount:r.cannon_count, sailPower:r.sail_power, fuel:r.fuel, maxFuel:r.max_fuel, x:r.x, y:r.y, heading:r.heading,
  status:r.status, fireUntil:r.fire_until?.toISOString() ?? null, fireDamage:r.fire_damage,
  retreatUntil:r.retreat_until?.toISOString() ?? null
});

export class NavalStore {
  constructor(private readonly db:Pool) {}

  async assignNpcCrew(userId:string,shipId:string,npcType:CrewType,role:CrewRole,skill:number,morale:number) {
    if(!CREW_TYPES.includes(npcType) || !CREW_ROLES.includes(role) || !Number.isSafeInteger(skill) || skill<1 || skill>100 || !Number.isSafeInteger(morale) || morale<0 || morale>100) throw new Error("INVALID_CREW_ASSIGNMENT");
    const c=await this.db.connect();
    try {
      await c.query("BEGIN");
      const ship=await c.query<{crew_capacity:number}>("SELECT crew_capacity FROM player_ships WHERE id=$1 AND owner_user_id=$2 FOR UPDATE",[shipId,userId]);
      if(!ship.rows[0]) throw new Error("SHIP_NOT_FOUND");
      const count=await c.query<{count:string}>("SELECT COUNT(*)::text count FROM ship_crew WHERE ship_id=$1",[shipId]);
      if(Number(count.rows[0]?.count??0)>=ship.rows[0].crew_capacity) throw new Error("SHIP_CREW_CAPACITY_REACHED");
      const row=await c.query<{id:string}>("INSERT INTO ship_crew(ship_id,creature_id,owner_user_id,npc_type,role,skill,morale) VALUES($1,NULL,$2,$3,$4,$5,$6) RETURNING id",[shipId,userId,npcType,role,skill,morale]);
      await c.query("COMMIT");
      return {id:row.rows[0].id,shipId,creatureId:null,npcType,role,skill,morale};
    } catch(e){await c.query("ROLLBACK");throw e} finally{c.release()}
  }

  async fireCannon(userId:string,shipId:string,targetShipId:string) {
    const c=await this.db.connect();
    try {
      await c.query("BEGIN");
      const rows=await c.query<Row>("SELECT "+select+" FROM player_ships WHERE id=ANY($1::uuid[]) ORDER BY id FOR UPDATE",[[shipId,targetShipId]]);
      const attacker=rows.rows.find(x=>x.id===shipId), target=rows.rows.find(x=>x.id===targetShipId);
      if(!attacker) throw new Error("SHIP_NOT_FOUND");
      if(!target || target.owner_user_id===userId) throw new Error("INVALID_NAVAL_TARGET");
      if(attacker.status!=="active") throw new Error("SHIP_NOT_ACTIVE");
      if(target.status!=="active") throw new Error("TARGET_SHIP_NOT_ACTIVE");
      const now=Date.now();
      if(attacker.retreat_until && attacker.retreat_until.getTime()>now) throw new Error("SHIP_RETREATING");
      if(target.retreat_until && target.retreat_until.getTime()>now) throw new Error("TARGET_SHIP_RETREATING");
      const crew=await c.query<{role:string;skill:number;morale:number;species:string|null}>("SELECT sc.role,sc.skill,sc.morale,pc.species FROM ship_crew sc LEFT JOIN player_creatures pc ON pc.id=sc.creature_id WHERE sc.ship_id=$1",[shipId]);
      const scoutRange=Math.min(100,crew.rows.filter(x=>x.role==="scout").reduce((s,x)=>s+x.skill*(x.morale/100),0));
      const range=250+scoutRange;
      const distance=Math.hypot(attacker.x-target.x,attacker.y-target.y);
      if(distance>range) throw new Error("NAVAL_TARGET_OUT_OF_RANGE");
      const targetAngle=Math.atan2(target.y-attacker.y,target.x-attacker.x);
      const delta=Math.atan2(Math.sin(targetAngle-attacker.heading),Math.cos(targetAngle-attacker.heading));
      const navigatorBonus=Math.min(Math.PI/12,crew.rows.filter(x=>x.role==="navigator").reduce((s,x)=>s+x.skill*(x.morale/100),0)*Math.PI/1800);
      if(Math.abs(delta)>Math.PI/4+navigatorBonus) throw new Error("CANNON_OUTSIDE_ARC");
      const recent=await c.query<{created_at:Date}>("SELECT created_at FROM naval_combat_events WHERE attacker_ship_id=$1 ORDER BY created_at DESC LIMIT 1",[shipId]);
      if(recent.rows[0] && now-new Date(recent.rows[0].created_at).getTime()<1000) throw new Error("CANNON_COOLDOWN");
      const ammo=await c.query<{quantity:string}>("SELECT quantity FROM ship_inventory WHERE ship_id=$1 AND item_id='cannonball' FOR UPDATE",[shipId]);
      if(Number(ammo.rows[0]?.quantity??0)<1) throw new Error("NO_CANNON_AMMO");
      const gunner=crew.rows.filter(x=>x.role==="gunner");
      const captain=crew.rows.filter(x=>x.role==="captain");
      const bonus=gunner.reduce((sum,x)=>sum+x.skill*(x.morale/100),0);
      const abilityBonus=crew.rows.reduce((sum,x)=>sum+(x.species ? (CREATURE_STATS[x.species]?.ability?.damage ?? 0) : 0),0);
      const commandMultiplier=Math.min(1.2,1+captain.reduce((sum,x)=>sum+x.morale,0)/1000);
      const damage=Math.max(1,Math.round((attacker.cannon_count+Math.floor(bonus/10)+abilityBonus)*commandMultiplier)-target.armor);
      const hull=Math.max(0,target.hull-damage);
      const status=hull===0?"destroyed":target.status;
      const fireStarted=hull>0 && damage>=Math.max(10,Math.floor(target.max_hull/20));
      await c.query("UPDATE ship_inventory SET quantity=quantity-1,updated_at=CURRENT_TIMESTAMP WHERE ship_id=$1 AND item_id='cannonball'",[shipId]);
      const updated=await c.query<Row>("UPDATE player_ships SET hull=$2,status=$3,fire_until=CASE WHEN $4 THEN CURRENT_TIMESTAMP+INTERVAL '5 seconds' ELSE fire_until END,fire_damage=CASE WHEN $4 THEN GREATEST(1,CEIL($5/10.0))::integer ELSE fire_damage END,updated_at=CURRENT_TIMESTAMP WHERE id=$1 RETURNING "+select,[target.id,hull,status,fireStarted,damage]);
      await c.query("INSERT INTO naval_combat_events(attacker_ship_id,defender_ship_id,attacker_user_id,defender_user_id,damage,attacker_hull_after,defender_hull_after,action_type) VALUES($1,$2,$3,$4,$5,$6,$7,'cannon')",[attacker.id,target.id,userId,target.owner_user_id,damage,attacker.hull,hull]);
      await c.query("COMMIT");
      return {attacker:mapShip(attacker),target:mapShip(updated.rows[0]),damage,fireStarted};
    } catch(e){await c.query("ROLLBACK");throw e} finally{c.release()}
  }

  async boardShip(userId:string,shipId:string,targetShipId:string) {
    const c=await this.db.connect();
    try {
      await c.query("BEGIN");
      const rows=await c.query<Row>("SELECT "+select+" FROM player_ships WHERE id=ANY($1::uuid[]) ORDER BY id FOR UPDATE",[[shipId,targetShipId]]);
      const attacker=rows.rows.find(x=>x.id===shipId),target=rows.rows.find(x=>x.id===targetShipId);
      if(!attacker) throw new Error("SHIP_NOT_FOUND");
      if(!target || target.owner_user_id===userId) throw new Error("INVALID_NAVAL_TARGET");
      if(attacker.status!=="active") throw new Error("SHIP_NOT_ACTIVE");
      if(target.status!=="active") throw new Error("TARGET_SHIP_NOT_ACTIVE");
      if(Math.hypot(attacker.x-target.x,attacker.y-target.y)>30) throw new Error("BOARDING_OUT_OF_RANGE");
      const ac=await c.query<{skill:number;morale:number}>("SELECT skill,morale FROM ship_crew WHERE ship_id=$1 AND role IN ('boarding_specialist','captain')",[shipId]);
      const dc=await c.query<{skill:number;morale:number}>("SELECT skill,morale FROM ship_crew WHERE ship_id=$1",[targetShipId]);
      const attackPower=ac.rows.reduce((s,x)=>s+x.skill+x.morale/10,0);
      if(attackPower<=0) throw new Error("INVALID_CREW_ASSIGNMENT");
      const defendPower=dc.rows.reduce((s,x)=>s+x.skill+x.morale/10,0);
      const damage=Math.max(1,Math.round(attackPower-Math.max(1,defendPower)/2));
      const captured=attackPower>defendPower*1.5;
      const hull=Math.max(1,target.hull-damage);
      await c.query("UPDATE player_ships SET hull=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[target.id,hull]);
      await c.query("INSERT INTO naval_combat_events(attacker_ship_id,defender_ship_id,attacker_user_id,defender_user_id,damage,attacker_hull_after,defender_hull_after,action_type) VALUES($1,$2,$3,$4,$5,$6,$7,'boarding')",[attacker.id,target.id,userId,target.owner_user_id,damage,attacker.hull,hull]);
      await c.query("COMMIT");
      return {attacker:mapShip(attacker),target:mapShip({...target,hull}),damage,captured};
    } catch(e){await c.query("ROLLBACK");throw e} finally{c.release()}
  }

  async repairShip(userId:string,shipId:string) {
    const c=await this.db.connect();
    try {
      await c.query("BEGIN");
      const r=await c.query<Row>("SELECT "+select+" FROM player_ships WHERE id=$1 AND owner_user_id=$2 FOR UPDATE",[shipId,userId]);
      const ship=r.rows[0];
      if(!ship) throw new Error("SHIP_NOT_FOUND");
      if(ship.status==="destroyed") throw new Error("SHIP_NOT_ACTIVE");
      if(ship.hull>=ship.max_hull) throw new Error("SHIP_FULL_HEALTH");
      const kit=await c.query<{quantity:string}>("SELECT quantity FROM ship_inventory WHERE ship_id=$1 AND item_id='repair_lumber' FOR UPDATE",[shipId]);
      if(Number(kit.rows[0]?.quantity??0)<1) throw new Error("NO_REPAIR_LUMBER");
      const engineers=await c.query<{skill:number}>("SELECT skill FROM ship_crew WHERE ship_id=$1 AND role='engineer'",[shipId]);
      const amount=Math.min(ship.max_hull-ship.hull,20+engineers.rows.reduce((s,x)=>s+x.skill,0));
      await c.query("UPDATE ship_inventory SET quantity=quantity-1,updated_at=CURRENT_TIMESTAMP WHERE ship_id=$1 AND item_id='repair_lumber'",[shipId]);
      const updated=await c.query<Row>("UPDATE player_ships SET hull=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1 RETURNING "+select,[shipId,ship.hull+amount]);
      await c.query("COMMIT");
      return mapShip(updated.rows[0]);
    } catch(e){await c.query("ROLLBACK");throw e} finally{c.release()}
  }

  async retreatShip(userId:string,shipId:string) {
    const c=await this.db.connect();
    try {
      await c.query("BEGIN");
      const r=await c.query<Row>("SELECT "+select+" FROM player_ships WHERE id=$1 AND owner_user_id=$2 FOR UPDATE",[shipId,userId]);
      if(!r.rows[0]) throw new Error("SHIP_NOT_FOUND");
      if(r.rows[0].status!=="active") throw new Error("SHIP_NOT_ACTIVE");
      const updated=await c.query<Row>("UPDATE player_ships SET retreat_until=CURRENT_TIMESTAMP+INTERVAL '5 seconds',updated_at=CURRENT_TIMESTAMP WHERE id=$1 RETURNING "+select,[shipId]);
      await c.query("COMMIT");
      return mapShip(updated.rows[0]);
    } catch(e){await c.query("ROLLBACK");throw e} finally{c.release()}
  }

  async fightFire(userId:string,shipId:string) {
    const c=await this.db.connect();
    try {
      await c.query("BEGIN");
      const r=await c.query<Row>("SELECT "+select+" FROM player_ships WHERE id=$1 AND owner_user_id=$2 FOR UPDATE",[shipId,userId]);
      const ship=r.rows[0];
      if(!ship) throw new Error("SHIP_NOT_FOUND");
      if(!ship.fire_until || ship.fire_until.getTime()<=Date.now()) throw new Error("SHIP_NOT_ON_FIRE");
      const medic=await c.query<{skill:number}>("SELECT skill FROM ship_crew WHERE ship_id=$1 AND role='medic'",[shipId]);
      const reduction=5+medic.rows.reduce((s,x)=>s+x.skill,0);
      const until=new Date(Math.max(Date.now(),ship.fire_until.getTime()-reduction*1000));
      const updated=await c.query<Row>("UPDATE player_ships SET fire_until=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1 RETURNING "+select,[shipId,until]);
      await c.query("COMMIT");
      return mapShip(updated.rows[0]);
    } catch(e){await c.query("ROLLBACK");throw e} finally{c.release()}
  }

  async tickFires():Promise<void> {
    const c=await this.db.connect();
    try {
      await c.query("BEGIN");
      const rows=await c.query<Row>("SELECT "+select+" FROM player_ships WHERE fire_until IS NOT NULL AND fire_until>CURRENT_TIMESTAMP FOR UPDATE");
      for(const ship of rows.rows) {
        const hull=Math.max(0,ship.hull-ship.fire_damage);
        await c.query("UPDATE player_ships SET hull=$2,status=CASE WHEN $2=0 THEN 'destroyed' ELSE status END,fire_until=CASE WHEN $2=0 OR fire_until<=CURRENT_TIMESTAMP+INTERVAL '1 second' THEN NULL ELSE fire_until END,updated_at=CURRENT_TIMESTAMP WHERE id=$1",[ship.id,hull]);
      }
      await c.query("COMMIT");
    } catch(e){await c.query("ROLLBACK");throw e} finally{c.release()}
  }
}
