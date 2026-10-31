import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { BaseStore } from "./base.js";
import { PlayerStore } from "./player.js";
import { ShipStore } from "./ship.js";
import { NavalStore } from "./naval.js";

// Finding D (comparative): crew power must grow with more/better crew but with diminishing returns and a hard
// ceiling, so a full roster of identical specialists cannot multiply one stat without bound.

async function register(app: FastifyInstance, tag: string): Promise<string> {
  const unique = tag + "_" + Date.now().toString(36).slice(-7) + "_" + Math.random().toString(36).slice(2, 5);
  const r = await app.inject({ method: "POST", url: "/auth/register", payload: { username: unique, email: unique + "@example.com", password: "Correct-Horse-Battery-9" } });
  expect(r.statusCode).toBe(201);
  return (JSON.parse(r.body) as { user: { id: string } }).user.id;
}

describe("crew bonuses have diminishing returns and hard caps (Finding D)", () => {
  const db: Pool = createDbPool();
  let app: FastifyInstance;
  let a: string, b: string, aShip: string, bShip: string;
  const naval = new NavalStore(db);
  beforeAll(async () => {
    app = await buildApp({ db });
    a = await register(app, "cba"); b = await register(app, "cbb");
    const mk = async (userId: string, x: number): Promise<string> => {
      await new PlayerStore(db).loadOrCreate(userId);
      const base = await new BaseStore(db).create(userId, "Base", 0, 0);
      await db.query("INSERT INTO base_storage(base_id,resource_key,quantity) VALUES($1,'wood',5000),($1,'steel',5000) ON CONFLICT (base_id,resource_key) DO UPDATE SET quantity=EXCLUDED.quantity", [base.id]);
      await db.query("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'shipyard',1,1,0,true)", [base.id]);
      const ship = await new ShipStore(db).create(userId, "Galleon", "galleon");
      await db.query("UPDATE player_ships SET x=$2,y=0,heading=0 WHERE id=$1", [ship.id, x]);
      return ship.id;
    };
    aShip = await mk(a, 0); bShip = await mk(b, 20);
  });
  afterAll(async () => { await app.close(); await db.end(); });
  beforeEach(async () => {
    await db.query("DELETE FROM naval_combat_events WHERE attacker_ship_id=ANY($1::uuid[])", [[aShip, bShip]]);
    await db.query("DELETE FROM ship_crew WHERE ship_id=ANY($1::uuid[])", [[aShip, bShip]]);
    await db.query("UPDATE player_ships SET hull=max_hull,fuel=max_fuel,status='active',fire_until=NULL,retreat_until=NULL,heading=0,armor=0 WHERE id=ANY($1::uuid[])", [[aShip, bShip]]);
    await db.query("INSERT INTO ship_inventory(ship_id,item_id,quantity) VALUES($1,'cannonball',500),($1,'repair_lumber',50) ON CONFLICT(ship_id,item_id) DO UPDATE SET quantity=EXCLUDED.quantity", [aShip]);
  });
  const crew = (shipId: string, userId: string, role: string, n: number, skill = 100, morale = 100): Promise<unknown> =>
    db.query("INSERT INTO ship_crew(ship_id,creature_id,owner_user_id,npc_type,role,skill,morale) SELECT $1,NULL,$2,'pirate',$3,$4,$5 FROM generate_series(1,$6)", [shipId, userId, role, skill, morale, n]);
  const cannonDamage = async (gunners: number): Promise<number> => {
    await db.query("DELETE FROM ship_crew WHERE ship_id=$1", [aShip]);
    await db.query("DELETE FROM naval_combat_events WHERE attacker_ship_id=$1", [aShip]);
    await db.query("UPDATE player_ships SET hull=max_hull WHERE id=$1", [bShip]);
    if (gunners > 0) await crew(aShip, a, "gunner", gunners);
    await naval.fireCannon(a, aShip, bShip);
    return Number((await db.query<{ damage: number }>("SELECT damage FROM naval_combat_events WHERE attacker_ship_id=$1", [aShip])).rows[0].damage);
  };

  it("cannon: a lone top gunner is unchanged, more gunners help with diminishing returns, and damage is capped", async () => {
    const d0 = await cannonDamage(0), d1 = await cannonDamage(1), d2 = await cannonDamage(2), d4 = await cannonDamage(4);
    const d12 = await cannonDamage(12), d25 = await cannonDamage(25);
    expect(d1 - d0).toBe(10);                       // one gunner at skill 100 keeps its +10 (no nerf for a lone specialist)
    expect(d2).toBeGreaterThan(d1);                 // a second gunner still helps
    expect(d2 - d1).toBeLessThan(d1 - d0);          // ...but less than the first
    expect(d4 - d2).toBeLessThan(d2 - d1 + 1);      // and the trend keeps shrinking
    expect(d25).toBe(d12);                          // roster size beyond the cap adds nothing
    expect(d25 - d0).toBeLessThanOrEqual(20);       // hard ceiling: at most +20 cannon damage from gunners
  });

  it("boarding: attack power cannot scale without bound with crew count", async () => {
    await db.query("UPDATE player_ships SET x=10,y=0 WHERE id=$1", [bShip]);
    const damageWith = async (n: number): Promise<number> => {
      await db.query("DELETE FROM ship_crew WHERE ship_id=$1", [aShip]);
      await db.query("DELETE FROM naval_combat_events WHERE attacker_ship_id=$1", [aShip]);
      await db.query("UPDATE player_ships SET hull=max_hull WHERE id=$1", [bShip]);
      await crew(aShip, a, "boarding_specialist", n);
      return (await naval.boardShip(a, aShip, bShip)).damage;
    };
    const one = await damageWith(1), two = await damageWith(2), twentyFive = await damageWith(25);
    expect(one).toBeLessThanOrEqual(110);
    expect(two).toBeGreaterThan(one);
    expect(two - one).toBeLessThan(one);            // second boarder adds less than the first
    expect(twentyFive).toBeLessThanOrEqual(220);    // ceiling: twice the best single contributor
  });

  it("repair: many engineers cannot instantly restore a wrecked hull", async () => {
    await crew(aShip, a, "engineer", 25);
    await db.query("UPDATE player_ships SET hull=1 WHERE id=$1", [aShip]);
    const ship = await naval.repairShip(a, aShip);
    expect(ship.hull).toBeGreaterThan(21);          // engineers help
    expect(ship.hull).toBeLessThanOrEqual(1 + 20 + 150); // ...but the bonus is capped
  });

  it("repair: fractional stacked bonuses are rounded down so odd engineer skills still repair (Codex P1)", async () => {
    await db.query("INSERT INTO ship_crew(ship_id,creature_id,owner_user_id,npc_type,role,skill,morale) VALUES($1,NULL,$2,'pirate','engineer',51,100),($1,NULL,$2,'pirate','engineer',51,100)", [aShip, a]);
    await db.query("UPDATE player_ships SET hull=1 WHERE id=$1", [aShip]);
    const ship = await naval.repairShip(a, aShip);   // 51 + 25.5 = 76.5 stacked => floor => 20 + 76
    expect(ship.hull).toBe(1 + 20 + 76);
    expect(Number.isInteger(ship.hull)).toBe(true);
  });

  it("fire fighting: many medics cannot extinguish any fire instantly", async () => {
    await crew(aShip, a, "medic", 25);
    await db.query("UPDATE player_ships SET fire_until=NOW()+INTERVAL '600 seconds' WHERE id=$1", [aShip]);
    await naval.fightFire(a, aShip);
    const left = Number((await db.query<{ s: string }>("SELECT EXTRACT(EPOCH FROM (fire_until-NOW()))::text s FROM player_ships WHERE id=$1", [aShip])).rows[0].s);
    expect(left).toBeGreaterThan(600 - 5 - 150 - 5);  // reduction ≤ 5 + 150 s (+ small clock slack)
  });
});
