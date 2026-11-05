import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { PlayerStore } from "./player.js";

async function setup() {
  const db = createDbPool();
  const app = await buildApp({ db });
  const unique = randomUUID().replace(/-/g, "").slice(0, 20);
  const res = await app.inject({ method: "POST", url: "/auth/register", payload: { username: `exp_${unique}`, email: `exp_${unique}@example.com`, password: "Correct-Horse-Battery-9" } });
  expect(res.statusCode).toBe(201);
  const body = JSON.parse(res.body) as { user: { id: string }; accessToken: string };
  const userId = body.user.id;
  await new PlayerStore(db).loadOrCreate(userId);
  await db.query("UPDATE player_profiles SET gold=100, inventory='{}'::jsonb WHERE user_id=$1", [userId]);
  const ship = await db.query<{ id: string }>(
    "INSERT INTO player_ships(owner_user_id,name,ship_class,hull,max_hull,armor,speed,turn_rate,cargo_capacity,crew_capacity,cannon_count,sail_power,fuel,max_fuel) VALUES($1,'Tide Runner','sloop',100,100,5,4,1,20,4,2,10,50,50) RETURNING id",
    [userId],
  );
  const shipId = ship.rows[0].id;
  const auth = { authorization: `Bearer ${body.accessToken}` };
  const start = (payload: Record<string, unknown>, headers = auth) => app.inject({ method: "POST", url: "/expeditions/start", headers, payload });
  const collect = (expeditionId: string) => app.inject({ method: "POST", url: "/expeditions/collect", headers: auth, payload: { expeditionId } });
  const profile = async () => (await db.query<{ gold: string; inventory: Record<string, number> }>("SELECT gold, inventory FROM player_profiles WHERE user_id=$1", [userId])).rows[0];
  const shipStatus = async () => (await db.query<{ status: string }>("SELECT status FROM player_ships WHERE id=$1", [shipId])).rows[0].status;
  const arrive = (expeditionId: string) => db.query("UPDATE ship_expeditions SET started_at=now()-interval '1 hour', returns_at=now()-interval '1 second' WHERE id=$1", [expeditionId]);
  const close = async () => { await app.close(); await db.end(); };
  return { db, app, userId, shipId, auth, start, collect, profile, shipStatus, arrive, close };
}

describe("ship expeditions", () => {
  it("starts on a server clock, docks the ship, and refuses early collection", async () => {
    const t = await setup();
    try {
      // A client-supplied duration is not part of the contract and is ignored.
      const res = await t.start({ shipId: t.shipId, routeId: "reef.short", requestId: "exp-start-0001", durationSeconds: 1 });
      expect(res.statusCode).toBe(200);
      const exp = JSON.parse(res.body) as { expeditionId: string; startedAt: string; returnsAt: string; replayed: boolean };
      expect(exp.replayed).toBe(false);
      expect(Date.parse(exp.returnsAt) - Date.parse(exp.startedAt)).toBe(120_000);
      expect(await t.shipStatus()).toBe("docked");
      const early = await t.collect(exp.expeditionId);
      expect(early.statusCode).toBe(409);
      expect(JSON.parse(early.body)).toEqual({ error: "EXPEDITION_IN_PROGRESS" });
      expect(await t.profile()).toEqual({ gold: "100", inventory: {} });
    } finally { await t.close(); }
  });

  it("a docked ship cannot start a second expedition; a replayed start returns the same expedition", async () => {
    const t = await setup();
    try {
      const first = JSON.parse((await t.start({ shipId: t.shipId, routeId: "reef.short", requestId: "exp-start-0002" })).body) as { expeditionId: string };
      const replay = JSON.parse((await t.start({ shipId: t.shipId, routeId: "reef.short", requestId: "exp-start-0002" })).body) as { expeditionId: string; replayed: boolean };
      expect(replay).toMatchObject({ expeditionId: first.expeditionId, replayed: true });
      const second = await t.start({ shipId: t.shipId, routeId: "isles.long", requestId: "exp-start-0003" });
      expect(second.statusCode).toBe(409);
      expect(JSON.parse(second.body)).toEqual({ error: "SHIP_NOT_ACTIVE" });
      const conflict = await t.start({ shipId: t.shipId, routeId: "isles.long", requestId: "exp-start-0002" });
      expect(JSON.parse(conflict.body)).toEqual({ error: "EXPEDITION_REQUEST_CONFLICT" });
    } finally { await t.close(); }
  });

  it("concurrent starts for one ship open exactly one expedition", async () => {
    const t = await setup();
    try {
      const results = await Promise.all(Array.from({ length: 6 }, (_, i) => t.start({ shipId: t.shipId, routeId: "reef.short", requestId: `exp-race-000${i}` })));
      expect(results.filter((r) => r.statusCode === 200)).toHaveLength(1);
      expect(results.filter((r) => r.statusCode === 409)).toHaveLength(5);
      const open = await t.db.query("SELECT 1 FROM ship_expeditions WHERE ship_id=$1 AND collected_at IS NULL", [t.shipId]);
      expect(open.rowCount).toBe(1);
    } finally { await t.close(); }
  });

  it("collecting a returned expedition pays the fixed route reward once and frees the ship", async () => {
    const t = await setup();
    try {
      const exp = JSON.parse((await t.start({ shipId: t.shipId, routeId: "reef.short", requestId: "exp-start-0004" })).body) as { expeditionId: string };
      await t.arrive(exp.expeditionId);
      const results = await Promise.all(Array.from({ length: 5 }, () => t.collect(exp.expeditionId)));
      expect(results.every((r) => r.statusCode === 200)).toBe(true);
      expect(results.map((r) => (JSON.parse(r.body) as { replayed: boolean }).replayed).filter((r) => !r)).toHaveLength(1);
      expect(await t.profile()).toEqual({ gold: "120", inventory: { "resource.wood": 6, "resource.stone": 4 } });
      expect(await t.shipStatus()).toBe("active");
      const audit = await t.db.query("SELECT 1 FROM economy_transactions WHERE user_id=$1 AND operation='ship_expedition_collect'", [t.userId]);
      expect(audit.rowCount).toBe(1);
      const again = await t.start({ shipId: t.shipId, routeId: "isles.long", requestId: "exp-start-0005" });
      expect(again.statusCode).toBe(200);
    } finally { await t.close(); }
  });

  it("rejects other players' ships and expeditions, unknown routes, bad input and non-player tokens", async () => {
    const a = await setup();
    const b = await setup();
    try {
      expect((await b.start({ shipId: a.shipId, routeId: "reef.short", requestId: "exp-steal-0001" })).statusCode).toBe(404);
      const exp = JSON.parse((await a.start({ shipId: a.shipId, routeId: "reef.short", requestId: "exp-own-00001" })).body) as { expeditionId: string };
      await a.arrive(exp.expeditionId);
      expect((await b.collect(exp.expeditionId)).statusCode).toBe(404);
      expect(await a.profile()).toEqual({ gold: "100", inventory: {} });
      expect((await a.start({ shipId: a.shipId, routeId: "moon.trip", requestId: "exp-route-0001" })).statusCode).toBe(404);
      expect((await a.start({ shipId: "not-a-uuid", routeId: "reef.short", requestId: "exp-bad-00001" })).statusCode).toBe(400);
      const admin = a.app.jwt.sign({ sub: a.userId, username: "x", role: "admin", typ: "access" }, { expiresIn: "5m" });
      expect((await a.start({ shipId: a.shipId, routeId: "reef.short", requestId: "exp-adm-00001" }, { authorization: `Bearer ${admin}` })).statusCode).toBe(401);
    } finally { await a.close(); await b.close(); }
  });
});
