import {describe,expect,it} from "vitest";
import type {FastifyInstance} from "fastify";
import type {Pool} from "pg";
import {buildApp} from "./app.js";
import {createDbPool} from "./db.js";
import {BaseStore} from "./base.js";
import {ShipStore} from "./ship.js";
import {NavalStore} from "./naval.js";
import {parseClientMessage} from "./protocol.js";
import {FleetStore} from "./fleet.js";
import {ShipInventoryStore} from "./ship-inventory.js";

async function register(app:FastifyInstance,tag:string):Promise<string>{
  const unique=tag+"_"+Date.now().toString(36).slice(-7)+"_"+Math.random().toString(36).slice(2,5);
  const response=await app.inject({method:"POST",url:"/auth/register",payload:{username:unique,email:unique+"@example.com",password:"Correct-Horse-Battery-9"}});
  expect(response.statusCode).toBe(201);
  return (JSON.parse(response.body) as {user:{id:string}}).user.id;
}
async function fixture(db:Pool,userId:string){
  const bases=new BaseStore(db);const base=await bases.create(userId,"Naval Base",0,0);
  await db.query("INSERT INTO base_storage(base_id,resource_key,quantity) VALUES($1,'wood',5000),($1,'steel',5000) ON CONFLICT (base_id,resource_key) DO UPDATE SET quantity=EXCLUDED.quantity",[base.id]);
  await db.query("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'shipyard',1,1,0,true)",[base.id]);
}
describe("Gate 9 naval mechanics",()=>{
  it("validates new naval protocol actions",()=>{
    expect(parseClientMessage(JSON.stringify({type:"board_ship",requestId:"b",shipId:"1",targetShipId:"2"}))?.type).toBe("board_ship");
    expect(parseClientMessage(JSON.stringify({type:"assign_ship_npc_crew",requestId:"c",shipId:"1",npcType:"pirate",role:"boarding_specialist",skill:80,morale:100}))?.type).toBe("assign_ship_npc_crew");
    expect(parseClientMessage(JSON.stringify({type:"repair_ship",requestId:"r",shipId:"1"}))?.type).toBe("repair_ship");
    expect(parseClientMessage(JSON.stringify({type:"create_fleet",requestId:"f",name:"Fleet",shipId:"1"}))?.type).toBe("create_fleet");
    expect(parseClientMessage(JSON.stringify({type:"ship_cargo",requestId:"c",shipId:"1",itemId:"cannonball",quantity:1}))?.type).toBe("ship_cargo");
  });
  it("implements NPC crew, cannon arcs, fire, boarding, repair and retreat transactionally",async()=>{
    const app=await buildApp();const db=createDbPool();
    try{
      const a=await register(app,"na"),b=await register(app,"nb");await fixture(db,a);await fixture(db,b);
      const ships=new ShipStore(db),naval=new NavalStore(db),fleets=new FleetStore(db),inventory=new ShipInventoryStore(db);
      const attacker=await ships.create(a,"War Galleon","galleon");
      const defender=await ships.create(b,"Target Raft","raft");
      await db.query("UPDATE player_ships SET x=0,y=0,heading=0 WHERE id=$1",[attacker.id]);
      await db.query("UPDATE player_ships SET x=20,y=0 WHERE id=$1",[defender.id]);
      expect((await naval.assignNpcCrew(a,attacker.id,"pirate","boarding_specialist",90,100)).npcType).toBe("pirate");
      expect((await naval.assignNpcCrew(a,attacker.id,"npc_specialist","engineer",80,100)).role).toBe("engineer");
      expect((await naval.assignNpcCrew(a,attacker.id,"mermaid","medic",80,100)).npcType).toBe("mermaid");
      expect((await naval.assignNpcCrew(a,attacker.id,"dragon","gunner",80,100)).npcType).toBe("dragon");
      const shot=await naval.fireCannon(a,attacker.id,defender.id);
      expect(shot.damage).toBeGreaterThan(0);expect(shot.fireStarted).toBe(true);
      const fireStopped=await naval.fightFire(b,defender.id);
      expect(fireStopped).toBeDefined();
      await db.query("UPDATE player_ships SET x=0,y=0,heading=0 WHERE id=$1",[attacker.id]);
      await db.query("UPDATE player_ships SET x=20,y=0 WHERE id=$1",[defender.id]);
      const board=await naval.boardShip(a,attacker.id,defender.id);
      expect(board.damage).toBeGreaterThan(0);
      await db.query("INSERT INTO ship_inventory(ship_id,item_id,quantity) VALUES($1,'repair_lumber',5) ON CONFLICT(ship_id,item_id) DO UPDATE SET quantity=5",[attacker.id]);
      await db.query("UPDATE player_ships SET hull=hull-50 WHERE id=$1",[attacker.id]);
      const repaired=await naval.repairShip(a,attacker.id);expect(repaired.hull).toBeGreaterThan(attacker.hull-50);
      const retreat=await naval.retreatShip(a,attacker.id);expect(retreat.retreatUntil).not.toBeNull();
      const cargo=await inventory.mutate(a,attacker.id,"repair_lumber",2);expect(cargo.find(x=>x.itemId==="repair_lumber")?.quantity).toBe(7);
      const fleet=await fleets.create(a,"Sea Wolves",attacker.id);expect(fleet.shipIds).toContain(attacker.id);
      const second=await ships.create(a,"Escort","sloop");const expanded=await fleets.addShip(a,fleet.id,second.id);expect(expanded.shipIds).toContain(second.id);
      const reduced=await fleets.removeShip(a,fleet.id,second.id);expect(reduced.shipIds).not.toContain(second.id);
      await expect(naval.fireCannon(a,attacker.id,defender.id)).rejects.toThrow("SHIP_RETREATING");
    }finally{await db.end();await app.close();}
  });
});
