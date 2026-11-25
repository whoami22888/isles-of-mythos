import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { BaseStore } from "./base.js";
import { createDbPool } from "./db.js";
import { MythosCompanionStore } from "./mythos-companion.js";
import { PlayerStore } from "./player.js";

async function setup() {
  const db = createDbPool();
  const app = await buildApp({ db });
  const unique = randomUUID().replace(/-/g, "").slice(0, 20);
  const res = await app.inject({
    method: "POST",
    url: "/auth/register",
    payload: { username: `mythos_${unique}`, email: `mythos_${unique}@example.com`, password: "Correct-Horse-Battery-9" },
  });
  expect(res.statusCode).toBe(201);
  const body = JSON.parse(res.body) as { user: { id: string }; accessToken: string };
  const userId = body.user.id;
  await new PlayerStore(db).loadOrCreate(userId);
  const bases = new BaseStore(db);
  await bases.create(userId, "Companion Yard", 8, 8);
  const creatureId = randomUUID();
  await db.query(
    `INSERT INTO player_creatures(id,owner_user_id,wild_source_id,species,level,xp,health,max_health,attack,defense,element,ability_ids,tame_progress,party_slot,ai_mode,x,y,mood,companion_state)
     VALUES($1,$2,$3,'fire_wisp',1,0,55,55,10,3,'fire','[]'::jsonb,100,NULL,'follow',0,0,70,'tamed_follow')`,
    [creatureId, userId, "seed:" + creatureId],
  );
  const forge = await bases.createBuilding(userId, "forge", 1, 2, 0);
  const store = new MythosCompanionStore(db);
  const auth = { authorization: `Bearer ${body.accessToken}` };
  const close = async () => { await app.close(); await db.end(); };
  return { db, app, userId, creatureId, forge, store, bases, auth, close };
}

describe("mythos companion persistence", () => {
  it("persists care, blocks wild/unfed paths, and reports fire/forge 1.6x yield", async () => {
    const t = await setup();
    try {
      const before = await t.store.snapshot(t.userId, t.creatureId);
      expect(before).toMatchObject({ state: "tamed_follow", mood: 70, xp_multiplier: 1, work_output_max: false, work_yield_multiplier: 1 });
      const petted = await t.store.care(t.userId, t.creatureId, "pet");
      expect(petted.mood).toBe(80);
      expect(petted.xp_multiplier).toBe(2);
      expect(petted.work_output_max).toBe(true);

      // New profiles are seeded with creature.feed; clear it to assert the empty path.
      await t.db.query("UPDATE player_profiles SET inventory = inventory || '{\"creature.feed\":0}'::jsonb WHERE user_id=$1", [t.userId]);
      const noFeed = await t.app.inject({
        method: "POST",
        url: `/creatures/${t.creatureId}/care`,
        headers: t.auth,
        payload: { action: "feed" },
      });
      expect(noFeed.statusCode).toBe(409);
      expect(JSON.parse(noFeed.body)).toEqual({ error: "NO_CREATURE_FEED" });
      expect((await t.store.snapshot(t.userId, t.creatureId)).mood).toBe(80);

      await t.db.query("UPDATE player_profiles SET inventory = inventory || '{\"creature.feed\":2}'::jsonb WHERE user_id=$1", [t.userId]);
      const fed = await t.store.care(t.userId, t.creatureId, "feed");
      expect(fed.mood).toBe(95);

      await t.bases.assignWorker(t.userId, t.creatureId, t.forge.id, "ore_smelting");
      const working = await t.store.snapshot(t.userId, t.creatureId);
      expect(working).toMatchObject({
        state: "tamed_work",
        workstation: "forge",
        work_task: "ore_smelting",
        work_yield_multiplier: 1.6,
        xp_multiplier: 2,
      });
    } finally { await t.close(); }
  });
});
