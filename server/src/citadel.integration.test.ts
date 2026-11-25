import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { BaseStore } from "./base.js";
import {
  CITADEL_SOFT_WALL_BADGES,
  CITADEL_SOFT_WALL_FOOD,
  CITADEL_SOFT_WALL_STEEL,
  CITADEL_SOFT_WALL_WOOD,
  CitadelStore,
  getCitadelUpgradeCost,
  type CitadelSnapshot,
} from "./citadel.js";
import { createDbPool } from "./db.js";
import { PlayerStore } from "./player.js";

async function setup(nowUnix = 1_700_000_000) {
  let clock = nowUnix;
  const db = createDbPool();
  const app = await buildApp({ db });
  const unique = randomUUID().replace(/-/g, "").slice(0, 20);
  const res = await app.inject({
    method: "POST",
    url: "/auth/register",
    payload: { username: `citadel_${unique}`, email: `citadel_${unique}@example.com`, password: "Correct-Horse-Battery-9" },
  });
  expect(res.statusCode).toBe(201);
  const body = JSON.parse(res.body) as { user: { id: string }; accessToken: string };
  const userId = body.user.id;
  await new PlayerStore(db).loadOrCreate(userId);
  const bases = new BaseStore(db);
  const base = await bases.create(userId, "Citadel Yard", 3, 5);
  const store = new CitadelStore(db, { nowUnix: () => clock });
  const auth = { authorization: `Bearer ${body.accessToken}` };
  const get = async () => {
    const response = await app.inject({ method: "GET", url: "/citadel", headers: auth });
    return { status: response.statusCode, body: JSON.parse(response.body) as CitadelSnapshot | { error: string } };
  };
  const post = async (url: string, payload?: Record<string, unknown>) => {
    const response = await app.inject({ method: "POST", url, headers: auth, payload: payload ?? {} });
    return { status: response.statusCode, body: JSON.parse(response.body) as CitadelSnapshot | { error: string } };
  };
  const seedStorage = async (wood: number, steel: number, food: number) => {
    await db.query(
      `INSERT INTO base_storage(base_id, resource_key, quantity)
       VALUES ($1,'wood',$2),($1,'steel',$3),($1,'food',$4)
       ON CONFLICT (base_id, resource_key) DO UPDATE SET quantity=EXCLUDED.quantity, updated_at=CURRENT_TIMESTAMP`,
      [base.id, wood, steel, food],
    );
  };
  const seedBadges = async (amount: number) => {
    await db.query("UPDATE player_profiles SET triumph_badges=$2 WHERE user_id=$1", [userId, String(amount)]);
  };
  const storage = async () => {
    const rows = await db.query<{ resource_key: string; quantity: string }>(
      "SELECT resource_key, quantity FROM base_storage WHERE base_id=$1",
      [base.id],
    );
    return Object.fromEntries(rows.rows.map((row) => [row.resource_key, Number(row.quantity)]));
  };
  const badges = async () => {
    const row = await db.query<{ triumph_badges: string }>("SELECT triumph_badges FROM player_profiles WHERE user_id=$1", [userId]);
    return row.rows[0]?.triumph_badges;
  };
  const advance = (seconds: number) => { clock += seconds; };
  const setLevel = async (level: number) => {
    await db.query("UPDATE player_citadels SET citadel_level=$2 WHERE owner_user_id=$1", [userId, level]);
  };
  const close = async () => { await app.close(); await db.end(); };
  return { db, userId, store, get, post, seedStorage, seedBadges, storage, badges, advance, setLevel, clock: () => clock, close };
}

describe("citadel store and routes", () => {
  it("creates a level-1 snapshot with the full server cost matrix", async () => {
    const t = await setup();
    try {
      const res = await t.get();
      expect(res.status).toBe(200);
      const body = res.body as CitadelSnapshot;
      expect(body.citadel_level).toBe(1);
      expect(body.upgrade_target_level).toBe(0);
      expect(body.server_now_unix).toBeGreaterThan(0);
      expect(Object.keys(body.upgrade_costs)).toHaveLength(19);
      expect(body.upgrade_costs["16"]).toEqual({
        wood: CITADEL_SOFT_WALL_WOOD,
        steel: CITADEL_SOFT_WALL_STEEL,
        food: CITADEL_SOFT_WALL_FOOD,
        badge_alternative: CITADEL_SOFT_WALL_BADGES,
      });
      expect(body.queue_flags).toEqual({ primary_busy: false, second_queue_enabled: false, secondary_busy: false });
    } finally { await t.close(); }
  });

  it("starts a resource-paid upgrade, applies guild help, and completes on the server clock", async () => {
    const t = await setup();
    try {
      const cost = getCitadelUpgradeCost(2);
      await t.seedStorage(cost.wood + 5, cost.steel + 5, cost.food + 5);
      const started = await t.store.requestUpgrade(t.userId, 1, "resources");
      expect(started).toMatchObject({
        citadel_level: 1,
        upgrade_target_level: 2,
        guild_help_seconds_applied: 0,
        queue_flags: { primary_busy: true, second_queue_enabled: false, secondary_busy: false },
      });
      expect(started.upgrade_completes_at_unix - started.upgrade_started_at_unix).toBe(60);
      const afterPay = await t.storage();
      expect(afterPay.wood).toBe(5);
      expect(afterPay.steel).toBe(5);
      expect(afterPay.food).toBe(5);

      await expect(t.store.completeUpgrade(t.userId)).rejects.toThrow("CITADEL_UPGRADE_INCOMPLETE");
      const helped = await t.store.applyGuildHelp(t.userId, 20);
      expect(helped.guild_help_seconds_applied).toBe(20);
      expect(helped.upgrade_completes_at_unix).toBe(started.upgrade_completes_at_unix - 20);

      t.advance(40);
      const complete = await t.store.completeUpgrade(t.userId);
      expect(complete.citadel_level).toBe(2);
      expect(complete.upgrade_target_level).toBe(0);
      expect(complete.guild_help_seconds_applied).toBe(0);
      expect(complete.queue_flags.primary_busy).toBe(false);
    } finally { await t.close(); }
  });

  it("rejects the 15→16 soft wall without materials or badges, then accepts a badge payment", async () => {
    const t = await setup();
    try {
      await t.store.snapshot(t.userId);
      await t.setLevel(15);
      await t.seedStorage(1, 1, 1);
      await t.seedBadges(0);
      const blocked = await t.post("/citadel/upgrade", { queue_slot: 1 });
      expect(blocked.status).toBe(409);
      expect(blocked.body).toEqual({ error: "CITADEL_SOFT_WALL_BLOCKED" });
      expect((await t.store.snapshot(t.userId)).citadel_level).toBe(15);

      await t.seedBadges(CITADEL_SOFT_WALL_BADGES);
      const started = await t.post("/citadel/upgrade", { queue_slot: 1, payment: "badges" });
      expect(started.status).toBe(200);
      const body = started.body as CitadelSnapshot;
      expect(body.upgrade_target_level).toBe(16);
      expect(await t.badges()).toBe("0");
      expect((await t.storage()).wood).toBe(1);
    } finally { await t.close(); }
  });

  it("locks the second queue until citadel level 10 and blocks a second concurrent upgrade", async () => {
    const t = await setup();
    try {
      await t.store.snapshot(t.userId);
      const locked = await t.post("/citadel/upgrade", { queue_slot: 2 });
      expect(locked.status).toBe(409);
      expect(locked.body).toEqual({ error: "CITADEL_SECOND_QUEUE_LOCKED" });

      const cost = getCitadelUpgradeCost(2);
      await t.seedStorage(cost.wood, cost.steel, cost.food);
      await t.store.requestUpgrade(t.userId, 1);
      await expect(t.store.requestUpgrade(t.userId, 1)).rejects.toThrow("CITADEL_UPGRADE_IN_PROGRESS");
    } finally { await t.close(); }
  });
});
