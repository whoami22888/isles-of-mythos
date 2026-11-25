import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readdirSync } from "node:fs";
import pg from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

// Migration 042 rollback on a disposable database: a ship that is away on an uncollected
// expedition is 'docked'. Dropping ship_expeditions must not strand it in that state.
const ADMIN_URL = process.env.DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:5432/isles_test";
const scratchName = `isles_mig042_${randomBytes(4).toString("hex")}`;
const scratchUrl = (() => { const u = new URL(ADMIN_URL); u.pathname = `/${scratchName}`; return u.toString(); })();
const bin = new URL("../../node_modules/.bin/node-pg-migrate", import.meta.url).pathname;
// Roll back every migration from 042 onward so 042's down runs even after later migrations land.
const stepsThrough042 = readdirSync(new URL("../migrations", import.meta.url)).filter((f) => /^\d{3}_.*\.js$/.test(f) && Number(f.slice(0, 3)) >= 42).length;
const run = (...args: string[]): string =>
  execFileSync(bin, [...args, "-m", "migrations"], { cwd: new URL("..", import.meta.url).pathname, env: { ...process.env, DATABASE_URL: scratchUrl }, encoding: "utf8" });

async function withScratch<T>(fn: (c: pg.Client) => Promise<T>): Promise<T> {
  const c = new pg.Client({ connectionString: scratchUrl });
  await c.connect();
  try { return await fn(c); } finally { await c.end(); }
}

async function ship(c: pg.Client, ownerId: string, status: string): Promise<string> {
  const r = await c.query<{ id: string }>(
    `INSERT INTO player_ships(owner_user_id,name,ship_class,hull,max_hull,armor,speed,turn_rate,cargo_capacity,crew_capacity,cannon_count,sail_power,fuel,max_fuel,status)
     VALUES($1,'Test','sloop',100,100,1,1,1,1,1,1,1,1,1,$2) RETURNING id`, [ownerId, status]);
  return r.rows[0]?.id ?? "";
}

describe("migration 042 ship_expeditions rollback", () => {
  beforeAll(async () => {
    const admin = new pg.Client({ connectionString: ADMIN_URL });
    await admin.connect();
    try { await admin.query(`CREATE DATABASE ${scratchName}`); } finally { await admin.end(); }
  });
  afterAll(async () => {
    const admin = new pg.Client({ connectionString: ADMIN_URL });
    await admin.connect();
    try { await admin.query(`DROP DATABASE IF EXISTS ${scratchName} WITH (FORCE)`); } finally { await admin.end(); }
  });

  it("returns ships on uncollected expeditions to active and leaves other ships alone", async () => {
    run("up");
    const ids = await withScratch(async (c) => {
      const user = await c.query<{ id: string }>("INSERT INTO users(username,email,password_hash) VALUES('mig042','mig042@example.com','x') RETURNING id");
      const owner = user.rows[0]?.id ?? "";
      const away = await ship(c, owner, "docked");
      const returned = await ship(c, owner, "active");
      const sunk = await ship(c, owner, "destroyed");
      await c.query("INSERT INTO ship_expeditions(owner_user_id,ship_id,route_id,request_id,returns_at,reward) VALUES($1,$2,'reef.short','r1',now()+interval '1 hour','{}')", [owner, away]);
      await c.query("INSERT INTO ship_expeditions(owner_user_id,ship_id,route_id,request_id,started_at,returns_at,collected_at,reward) VALUES($1,$2,'reef.short','r2',now()-interval '2 hours',now()-interval '1 hour',now(),'{}')", [owner, returned]);
      return { away, returned, sunk };
    });

    run("down", String(stepsThrough042));

    const status = await withScratch(async (c) => {
      const r = await c.query<{ id: string; status: string }>("SELECT id, status FROM player_ships");
      return Object.fromEntries(r.rows.map((row) => [row.id, row.status]));
    });
    expect(status).toEqual({ [ids.away]: "active", [ids.returned]: "active", [ids.sunk]: "destroyed" });

    run("up");
  }, 120_000);
});
