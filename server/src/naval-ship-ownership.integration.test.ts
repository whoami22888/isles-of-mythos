import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { BaseStore } from "./base.js";
import { PlayerStore } from "./player.js";
import { ShipStore } from "./ship.js";
import { NavalStore } from "./naval.js";

// Finding C: fireCannon/boardShip selected the attacker ship by id only, so any player could command another
// player's ship by passing its id. Every ship command must require that the authenticated actor owns the ship.

async function register(app: FastifyInstance, tag: string): Promise<string> {
  const unique = tag + "_" + Date.now().toString(36).slice(-7) + "_" + Math.random().toString(36).slice(2, 5);
  const r = await app.inject({ method: "POST", url: "/auth/register", payload: { username: unique, email: unique + "@example.com", password: "Correct-Horse-Battery-9" } });
  expect(r.statusCode).toBe(201);
  return (JSON.parse(r.body) as { user: { id: string } }).user.id;
}

async function galleon(db: Pool, userId: string, x: number): Promise<string> {
  await new PlayerStore(db).loadOrCreate(userId);
  const base = await new BaseStore(db).create(userId, "Own Base", 0, 0);
  await db.query("INSERT INTO base_storage(base_id,resource_key,quantity) VALUES($1,'wood',5000),($1,'steel',5000) ON CONFLICT (base_id,resource_key) DO UPDATE SET quantity=EXCLUDED.quantity", [base.id]);
  await db.query("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'shipyard',1,1,0,true)", [base.id]);
  const ship = await new ShipStore(db).create(userId, "Galleon", "galleon");
  await db.query("UPDATE player_ships SET x=$2,y=0,heading=0 WHERE id=$1", [ship.id, x]);
  return ship.id;
}

const snapshot = async (db: Pool, shipIds: string[]): Promise<unknown> =>
  (await db.query("SELECT s.id,s.hull,s.fuel,s.x,s.y,s.status,s.fire_until,s.retreat_until,(SELECT COALESCE(sum(quantity),0)::text FROM ship_inventory i WHERE i.ship_id=s.id) ammo,(SELECT count(*)::text FROM ship_crew c WHERE c.ship_id=s.id) crew FROM player_ships s WHERE s.id=ANY($1::uuid[]) ORDER BY s.id", [shipIds])).rows;
const events = async (db: Pool, shipIds: string[]): Promise<number> =>
  Number((await db.query<{ n: string }>("SELECT count(*)::text n FROM naval_combat_events WHERE attacker_ship_id=ANY($1::uuid[]) OR defender_ship_id=ANY($1::uuid[])", [shipIds])).rows[0].n);

describe("naval ship commands require ownership of the commanded ship (Finding C)", () => {
  const db = createDbPool();
  let app: FastifyInstance;
  beforeAll(async () => { app = await buildApp({ db }); });
  afterAll(async () => { await app.close(); await db.end(); });

  // Registration is rate limited, so one trio is shared and the ships are reset to a known state before each test.
  type Trio = { owner: string; victim: string; thief: string; ownerShip: string; victimShip: string; thiefShip: string };
  let t: Trio;
  beforeAll(async () => {
    const owner = await register(app, "own"), victim = await register(app, "vic"), thief = await register(app, "thf");
    t = { owner, victim, thief, ownerShip: await galleon(db, owner, 0), victimShip: await galleon(db, victim, 20), thiefShip: await galleon(db, thief, 500) };
  });
  beforeEach(async () => {
    const ids = [t.ownerShip, t.victimShip, t.thiefShip];
    await db.query("DELETE FROM naval_combat_events WHERE attacker_ship_id=ANY($1::uuid[]) OR defender_ship_id=ANY($1::uuid[])", [ids]);
    await db.query("DELETE FROM ship_crew WHERE ship_id=ANY($1::uuid[])", [ids]);
    await db.query("UPDATE player_ships SET hull=max_hull,fuel=max_fuel,status='active',fire_until=NULL,retreat_until=NULL,heading=0 WHERE id=ANY($1::uuid[])", [ids]);
    await db.query("UPDATE player_ships SET x=0,y=0 WHERE id=$1", [t.ownerShip]);
    await db.query("UPDATE player_ships SET x=20,y=0 WHERE id=$1", [t.victimShip]);
    await db.query("UPDATE player_ships SET x=500,y=0 WHERE id=$1", [t.thiefShip]);
    await db.query("INSERT INTO ship_inventory(ship_id,item_id,quantity) VALUES($1,'cannonball',50) ON CONFLICT(ship_id,item_id) DO UPDATE SET quantity=50", [t.ownerShip]);
  });
  const addBoarder = (shipId: string, userId: string): Promise<unknown> =>
    db.query("INSERT INTO ship_crew(ship_id,creature_id,owner_user_id,npc_type,role,skill,morale) VALUES($1,NULL,$2,'pirate','boarding_specialist',30,100)", [shipId, userId]);

  it("a player cannot fire another player's ship at a third player's ship", async () => {
    const before = await snapshot(db, [t.ownerShip, t.victimShip]);
    await expect(new NavalStore(db).fireCannon(t.thief, t.ownerShip, t.victimShip)).rejects.toThrow("SHIP_NOT_FOUND");
    expect(await snapshot(db, [t.ownerShip, t.victimShip])).toEqual(before);
    expect(await events(db, [t.ownerShip, t.victimShip])).toBe(0);
  });

  it("a player cannot board with another player's ship, even when that ship has a boarding crew", async () => {
    await addBoarder(t.ownerShip, t.owner);
    const before = await snapshot(db, [t.ownerShip, t.victimShip]);
    await expect(new NavalStore(db).boardShip(t.thief, t.ownerShip, t.victimShip)).rejects.toThrow("SHIP_NOT_FOUND");
    expect(await snapshot(db, [t.ownerShip, t.victimShip])).toEqual(before);
    expect(await events(db, [t.ownerShip, t.victimShip])).toBe(0);
  });

  it("the ownership check does not reveal whether the ship exists (same error as an unknown ship)", async () => {
    const naval = new NavalStore(db);
    const unknown = "00000000-0000-4000-8000-000000000000";
    await expect(naval.fireCannon(t.thief, unknown, t.victimShip)).rejects.toThrow("SHIP_NOT_FOUND");
    await expect(naval.fireCannon(t.thief, t.ownerShip, t.victimShip)).rejects.toThrow("SHIP_NOT_FOUND");
  });

  it("the real owner can still fire and board", async () => {
    const naval = new NavalStore(db);
    const shot = await naval.fireCannon(t.owner, t.ownerShip, t.victimShip);
    expect(shot.damage).toBeGreaterThan(0);
    await addBoarder(t.ownerShip, t.owner);
    const boarded = await naval.boardShip(t.owner, t.ownerShip, t.victimShip);
    expect(boarded.damage).toBeGreaterThan(0);
    expect(await events(db, [t.ownerShip, t.victimShip])).toBe(2);
  });

  it("every other ship command is rejected for a non-owner and changes nothing", async () => {
    const naval = new NavalStore(db), ships = new ShipStore(db);
    const before = await snapshot(db, [t.ownerShip]);
    // A non-owner reading a ship's inventory gets an empty list, never the contents.
    expect(await ships.inventory(t.thief, t.ownerShip)).toEqual([]);
    const attempts: Array<[string, () => Promise<unknown>]> = [
      ["sail", () => ships.sail(t.thief, t.ownerShip, 1, 0)],
      ["repair", () => naval.repairShip(t.thief, t.ownerShip)],
      ["retreat", () => naval.retreatShip(t.thief, t.ownerShip)],
      ["fightFire", () => naval.fightFire(t.thief, t.ownerShip)],
    ];
    for (const [name, attempt] of attempts) {
      const outcome = await attempt().then(() => "resolved", (e: Error) => e.message);
      expect(outcome, name).not.toBe("resolved");
    }
    expect(await snapshot(db, [t.ownerShip])).toEqual(before);
  });
});
