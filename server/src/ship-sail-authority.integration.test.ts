import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { BaseStore } from "./base.js";
import { PlayerStore } from "./player.js";
import { ShipStore, SHIP_CLASSES, MAX_SAIL_SECONDS } from "./ship.js";
import { parseClientMessage } from "./protocol.js";
import { unitSailHeading } from "./sail-heading.js";

// Option A (owner, 2026-10-29): the server owns sailing time. The client sends a heading only; elapsed time is the
// server clock since the ship's last sail, capped at 60 s. Nothing the client sends can lengthen a move.
const SLOOP_SPEED = SHIP_CLASSES.sloop.speed;
const WIND_MAX = 1.5; // windMultiplier upper bound
const WIND_MIN = 0.5; // windMultiplier lower bound (alignment -1)

async function register(app: FastifyInstance, tag: string): Promise<{ userId: string; token: string }> {
  const unique = tag + "_" + Date.now().toString(36).slice(-7) + "_" + Math.random().toString(36).slice(2, 5);
  const r = await app.inject({ method: "POST", url: "/auth/register", payload: { username: unique, email: unique + "@example.com", password: "Correct-Horse-Battery-9" } });
  expect(r.statusCode).toBe(201);
  const body = JSON.parse(r.body) as { accessToken: string; user: { id: string } };
  return { userId: body.user.id, token: body.accessToken };
}

async function sloop(db: Pool, userId: string): Promise<string> {
  await new PlayerStore(db).loadOrCreate(userId);
  const base = await new BaseStore(db).create(userId, "Sail Base", 0, 0);
  await db.query("INSERT INTO base_storage(base_id,resource_key,quantity) VALUES($1,'wood',5000),($1,'steel',5000) ON CONFLICT (base_id,resource_key) DO UPDATE SET quantity=EXCLUDED.quantity", [base.id]);
  await db.query("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'shipyard',1,1,0,true)", [base.id]);
  const ship = await new ShipStore(db).create(userId, "Timed Sloop", "sloop");
  await db.query("UPDATE player_ships SET x=0,y=0 WHERE id=$1", [ship.id]);
  return ship.id;
}
async function anotherSloop(db: Pool, userId: string): Promise<string> {
  await db.query("INSERT INTO base_storage(base_id,resource_key,quantity) SELECT id,'wood',5000 FROM player_bases WHERE owner_user_id=$1 ON CONFLICT (base_id,resource_key) DO UPDATE SET quantity=EXCLUDED.quantity", [userId]);
  await db.query("INSERT INTO base_storage(base_id,resource_key,quantity) SELECT id,'steel',5000 FROM player_bases WHERE owner_user_id=$1 ON CONFLICT (base_id,resource_key) DO UPDATE SET quantity=EXCLUDED.quantity", [userId]);
  const ship = await new ShipStore(db).create(userId, "Timed Sloop", "sloop");
  await db.query("UPDATE player_ships SET x=0,y=0 WHERE id=$1", [ship.id]);
  return ship.id;
}
const backdate = (db: Pool, shipId: string, seconds: number): Promise<unknown> =>
  db.query("UPDATE player_ships SET last_sailed_at = now() - make_interval(secs => $2) WHERE id=$1", [shipId, seconds]);
const lastSailed = async (db: Pool, shipId: string): Promise<number> =>
  Number((await db.query<{ age: string }>("SELECT EXTRACT(EPOCH FROM (now() - last_sailed_at))::text age FROM player_ships WHERE id=$1", [shipId])).rows[0].age);

describe("protocol: the sail message carries heading only", () => {
  it("accepts a heading with no duration and drops any client-supplied dt", () => {
    const withoutDt = parseClientMessage(JSON.stringify({ type: "sail", requestId: "r", shipId: "s", dx: 1, dy: 0 }));
    expect(withoutDt).toEqual({ type: "sail", requestId: "r", shipId: "s", dx: 1, dy: 0 });
    for (const dt of [60, 1e9, -5, 0, "60", null]) {
      const parsed = parseClientMessage(JSON.stringify({ type: "sail", requestId: "r", shipId: "s", dx: 1, dy: 0, dt }));
      expect(parsed).toEqual({ type: "sail", requestId: "r", shipId: "s", dx: 1, dy: 0 });
      expect(parsed).not.toHaveProperty("dt");
    }
  });
  it("still rejects an invalid heading", () => {
    expect(parseClientMessage(JSON.stringify({ type: "sail", requestId: "r", shipId: "s", dx: 0, dy: 0 }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({ type: "sail", requestId: "r", shipId: "s", dx: 2, dy: 0 }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({ type: "sail", requestId: "r", shipId: "s", dx: Number.NaN, dy: 1 }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({ type: "sail", requestId: "r", shipId: "s", dx: 1e-8, dy: 0 }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({ type: "sail", requestId: "r", shipId: "s", dx: 1e-8, dy: 1e-8 }))).toBeNull();
  });

  it("accepts a diagonal heading and keeps the components for the authoritative store to normalize", () => {
    expect(parseClientMessage(JSON.stringify({ type: "sail", requestId: "r", shipId: "s", dx: 1, dy: 1 }))).toEqual({
      type: "sail", requestId: "r", shipId: "s", dx: 1, dy: 1,
    });
    expect(parseClientMessage(JSON.stringify({ type: "sail", requestId: "r", shipId: "s", dx: -1, dy: 1 }))).toEqual({
      type: "sail", requestId: "r", shipId: "s", dx: -1, dy: 1,
    });
  });
});

describe("server-timed sailing (store)", () => {
  const db = createDbPool();
  let app: FastifyInstance;
  beforeAll(async () => { app = await buildApp({ db }); });
  afterAll(async () => { await app.close(); await db.end(); });

  it("(c) caps elapsed time at 60 s: an hour offline moves one minute, not one hour", async () => {
    const { userId } = await register(app, "cap");
    const shipId = await sloop(db, userId);
    await backdate(db, shipId, 3_600);
    const moved = await new ShipStore(db).sail(userId, shipId, 1, 0);
    expect(moved.x).toBeLessThanOrEqual(SLOOP_SPEED * 60 * WIND_MAX + 1e-6);
    expect(moved.x).toBeGreaterThanOrEqual(SLOOP_SPEED * 60 * WIND_MIN - 1e-6);
  });

  it("moves in proportion to the server's elapsed time (30 s of idle, not the full cap)", async () => {
    const { userId } = await register(app, "prop");
    const shipId = await sloop(db, userId);
    await backdate(db, shipId, 30);
    const moved = await new ShipStore(db).sail(userId, shipId, 1, 0);
    expect(moved.x).toBeLessThanOrEqual(SLOOP_SPEED * 31 * WIND_MAX);
    expect(moved.x).toBeGreaterThanOrEqual(SLOOP_SPEED * 30 * WIND_MIN - 1e-6);
  });

  it("(b) rapid spamming cannot outrun the wall clock", async () => {
    const { userId } = await register(app, "spam");
    const shipId = await sloop(db, userId);
    const store = new ShipStore(db);
    const started = Date.now();
    let x = 0;
    for (let i = 0; i < 25; i += 1) {
      try { x = (await store.sail(userId, shipId, 1, 0)).x; } catch (e) { expect((e as Error).message).toBe("INSUFFICIENT_SHIP_FUEL"); break; }
    }
    const wallSeconds = (Date.now() - started) / 1000 + 1; // +1 s: creation-to-first-sail slack
    expect(x).toBeLessThanOrEqual(SLOOP_SPEED * wallSeconds * WIND_MAX);
  });

  it("advances last_sailed_at on every sail, so the same time cannot be spent twice", async () => {
    const { userId } = await register(app, "adv");
    const shipId = await sloop(db, userId);
    await backdate(db, shipId, 45);
    const store = new ShipStore(db);
    const first = await store.sail(userId, shipId, 1, 0);
    expect(await lastSailed(db, shipId)).toBeLessThan(5);
    const second = await store.sail(userId, shipId, 1, 0);
    expect(second.x - first.x).toBeLessThan(SLOOP_SPEED * 3 * WIND_MAX);
  });

  it("concurrent sails share one elapsed window", async () => {
    const { userId } = await register(app, "conc");
    const shipId = await sloop(db, userId);
    await backdate(db, shipId, 30);
    const store = new ShipStore(db);
    await Promise.all([store.sail(userId, shipId, 1, 0), store.sail(userId, shipId, 1, 0), store.sail(userId, shipId, 1, 0)]);
    const { rows } = await db.query<{ x: number }>("SELECT x FROM player_ships WHERE id=$1", [shipId]);
    expect(rows[0].x).toBeLessThanOrEqual(SLOOP_SPEED * 32 * WIND_MAX);
  });

  it("a diagonal heading cannot outrun a unit heading or buy extra distance per fuel", async () => {
    const { userId } = await register(app, "diag");
    const wind = await db.query<{ wind_x: number; wind_y: number }>("SELECT wind_x, wind_y FROM naval_world_state WHERE id=1");
    const wx = Number(wind.rows[0]?.wind_x ?? 0);
    const wy = Number(wind.rows[0]?.wind_y ?? 0);
    const store = new ShipStore(db);
    const headings: Array<[number, number]> = [[1, 0], [0, 1], [1, 1], [-1, -1], [1, -1], [0.2, -0.2]];
    let firstShip = true;
    for (const [dx, dy] of headings) {
      const shipId = firstShip ? await sloop(db, userId) : await anotherSloop(db, userId);
      firstShip = false;
      await backdate(db, shipId, MAX_SAIL_SECONDS * 2);
      const before = await db.query<{ fuel: number }>("SELECT fuel FROM player_ships WHERE id=$1", [shipId]);
      const moved = await store.sail(userId, shipId, dx, dy);
      const heading = unitSailHeading(dx, dy);
      if (!heading) throw new Error("EXPECTED_HEADING");
      const windLength = Math.hypot(wx, wy);
      const alignment = windLength === 0 ? 0 : (heading.x * wx + heading.y * wy) / windLength;
      const windMultiplier = Math.max(0, Math.min(1.5, 1 + alignment * 0.5));
      const expected = SLOOP_SPEED * MAX_SAIL_SECONDS * windMultiplier;
      const travelled = Math.hypot(moved.x, moved.y);
      const unnormalized = Math.hypot(dx * expected, dy * expected);
      expect(travelled).toBeCloseTo(expected, 4);
      expect(travelled).toBeLessThanOrEqual(expected + 1e-6);
      if (Math.hypot(dx, dy) > 1.01) expect(unnormalized).toBeGreaterThan(travelled * 1.2);
      const fuelCost = Math.max(1, Math.ceil(travelled / SHIP_CLASSES.sloop.sail - 1e-9));
      expect(before.rows[0].fuel - moved.fuel).toBe(fuelCost);
      expect(moved.heading).toBeCloseTo(Math.atan2(heading.y, heading.x), 6);
    }
  });

  it("rejects a tiny heading in the store without moving the ship or spending fuel", async () => {
    const { userId } = await register(app, "tiny");
    const shipId = await sloop(db, userId);
    await backdate(db, shipId, 30);
    const before = await db.query<{ fuel: number; x: number; y: number }>("SELECT fuel, x, y FROM player_ships WHERE id=$1", [shipId]);
    await expect(new ShipStore(db).sail(userId, shipId, 1e-8, 0)).rejects.toThrow("INVALID_SAIL_INPUT");
    const after = await db.query<{ fuel: number; x: number; y: number }>("SELECT fuel, x, y FROM player_ships WHERE id=$1", [shipId]);
    expect(after.rows[0]).toEqual(before.rows[0]);
  });

  it("a failed sail (no fuel) does not consume the elapsed time", async () => {
    const { userId } = await register(app, "fuel");
    const shipId = await sloop(db, userId);
    await backdate(db, shipId, 50);
    await db.query("UPDATE player_ships SET fuel=0 WHERE id=$1", [shipId]);
    const store = new ShipStore(db);
    await expect(store.sail(userId, shipId, 1, 0)).rejects.toThrow("INSUFFICIENT_SHIP_FUEL");
    expect(await lastSailed(db, shipId)).toBeGreaterThanOrEqual(49);
  });
});

describe("(a) a client-supplied dt is ignored over the WebSocket", () => {
  const db = createDbPool();
  let app: FastifyInstance;
  let socket: WebSocket | undefined;
  beforeAll(async () => { app = await buildApp({ db }); await app.listen({ host: "127.0.0.1", port: 0 }); });
  afterAll(async () => { socket?.close(); await app.close(); await db.end(); });

  it("sail with dt:60 on a freshly sailed ship moves it by server time only", async () => {
    const { userId, token } = await register(app, "wsdt");
    const shipId = await sloop(db, userId);
    const address = app.server.address();
    if (address === null || typeof address === "string") throw new Error("TEST_SERVER_NOT_LISTENING");
    socket = new WebSocket(`ws://127.0.0.1:${address.port}/ws`);
    const seen: Array<Record<string, unknown> & { type: string }> = [];
    socket.on("message", (raw: Buffer) => seen.push(JSON.parse(raw.toString()) as never));
    await new Promise<void>((res, rej) => { socket!.once("open", () => res()); socket!.once("error", rej); });
    const wait = async (pred: (m: { type: string }) => boolean): Promise<Record<string, unknown>> => {
      for (let i = 0; i < 800; i += 1) { const m = seen.find(pred); if (m) return m; await new Promise((r) => setTimeout(r, 10)); }
      throw new Error("TIMEOUT " + JSON.stringify(seen.map((m) => m.type)));
    };
    socket.send(JSON.stringify({ type: "auth", token }));
    await wait((m) => m.type === "auth_ok");
    socket.send(JSON.stringify({ type: "sail", requestId: "s1", shipId, dx: 1, dy: 0, dt: 60 }));
    const reply = await wait((m) => m.type === "ship_state" || m.type === "error");
    expect(reply.type).toBe("ship_state");
    const ship = reply.ship as { x: number };
    // A trusted dt:60 would be ~192 units. Server-timed: the ship was created moments ago.
    expect(ship.x).toBeLessThan(SLOOP_SPEED * 5 * WIND_MAX);
  });
});
