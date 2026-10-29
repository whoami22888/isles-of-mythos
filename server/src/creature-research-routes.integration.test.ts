import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { BaseStore } from "./base.js";
import { createDbPool } from "./db.js";

async function register(app: Awaited<ReturnType<typeof buildApp>>) {
  const suffix = randomUUID().replace(/-/g, "").slice(0, 16);
  const response = await app.inject({
    method: "POST",
    url: "/auth/register",
    payload: { username: `res_${suffix}`, email: `res_${suffix}@example.com`, password: "Correct-Horse-Battery-9" },
  });
  expect(response.statusCode).toBe(201);
  return JSON.parse(response.body) as { accessToken: string; user: { id: string } };
}

describe("IOM-04 research HTTP boundary", () => {
  it("requires JWT for both catalogue and unlock; never accepts a client owner override", async () => {
    const db = createDbPool();
    const app = await buildApp({ db });
    try {
      const unauthenticated = await app.inject({ method: "GET", url: "/creature-research" });
      expect(unauthenticated.statusCode).toBe(401);
      const unauthenticatedWrite = await app.inject({
        method: "POST", url: "/creature-research/unlock", payload: { requestId: "auth-1", skillId: "tracking" },
      });
      expect(unauthenticatedWrite.statusCode).toBe(401);
      const owner = await register(app);
      const tampered = await app.inject({
        method: "POST", url: "/creature-research/unlock",
        headers: { authorization: `Bearer ${owner.accessToken}` },
        payload: { requestId: "auth-2", skillId: "tracking", userId: randomUUID() },
      });
      expect(tampered.statusCode).toBe(400);
    } finally { await app.close(); await db.end(); }
  });

  it("lists only the authenticated player's progress and performs once-only earned research", async () => {
    const db = createDbPool();
    const app = await buildApp({ db });
    try {
      const owner = await register(app);
      const other = await register(app);
      await new BaseStore(db).create(owner.user.id, "Research Base", 0, 0);
      // Registration creates the account, but player_profiles is initialized lazily.
      // Initialize through the real authenticated API before modifying inventory.
      const initialized = await app.inject({ method: "GET", url: "/creature-research",
        headers: { authorization: `Bearer ${owner.accessToken}` } });
      expect(initialized.statusCode).toBe(200);
      const seeded = await db.query("UPDATE player_profiles SET inventory=$2::jsonb WHERE user_id=$1", [
        owner.user.id, JSON.stringify({ "resource.herb": 3 }),
      ]);
      expect(seeded.rowCount).toBe(1);
      const ownerAuth = { authorization: `Bearer ${owner.accessToken}` };
      const otherAuth = { authorization: `Bearer ${other.accessToken}` };

      const before = await app.inject({ method: "GET", url: "/creature-research", headers: ownerAuth });
      expect(before.statusCode).toBe(200);
      const beforeSkills = before.json<{ skills: Array<{ skillId: string; unlocked: boolean; researchRequirementsMet: boolean; cost: Array<{ itemId: string; quantity: number }> }> }>().skills;
      expect(beforeSkills).toHaveLength(9);
      expect(beforeSkills.find(s => s.skillId === "tracking")).toMatchObject({
        unlocked: false, researchRequirementsMet: true, cost: [{ itemId: "resource.herb", quantity: 1 }],
      });
      const action = { requestId: "earned-research-1", skillId: "tracking" };
      const first = await app.inject({ method: "POST", url: "/creature-research/unlock", headers: ownerAuth, payload: action });
      expect(first.statusCode, `first research unlock response: ${first.body}`).toBe(200);
      expect(first.json()).toEqual({ skillId: "tracking", unlocked: true, experience: 0 });

      const replay = await app.inject({ method: "POST", url: "/creature-research/unlock", headers: ownerAuth, payload: action });
      expect(replay.statusCode).toBe(200);
      expect(replay.json()).toEqual(first.json());
      const changedPayload = await app.inject({ method: "POST", url: "/creature-research/unlock", headers: ownerAuth,
        payload: { requestId: "earned-research-1", skillId: "animal_handling" },
      });
      expect(changedPayload.statusCode).toBe(409);
      const persisted = await db.query<{ inventory: Record<string, number> }>(
        "SELECT inventory FROM player_profiles WHERE user_id=$1", [owner.user.id],
      );
      expect(persisted.rows[0]?.inventory["resource.herb"]).toBe(2);

      const ownerAfter = await app.inject({ method: "GET", url: "/creature-research", headers: ownerAuth });
      const otherAfter = await app.inject({ method: "GET", url: "/creature-research", headers: otherAuth });
      expect(ownerAfter.statusCode).toBe(200);
      expect(otherAfter.statusCode).toBe(200);
      const ownerTracking = ownerAfter.json<{skills:Array<{skillId:string;unlocked:boolean;rank:number|null}>}>().skills.find(s=>s.skillId==="tracking");
      const otherTracking = otherAfter.json<{skills:Array<{skillId:string;unlocked:boolean;rank:number|null}>}>().skills.find(s=>s.skillId==="tracking");
      expect(ownerTracking).toMatchObject({ unlocked: true, rank: 1 });
      expect(otherTracking).toMatchObject({ unlocked: false, rank: null });
      expect(JSON.stringify(otherAfter.json())).not.toContain(owner.user.id);
    } finally { await app.close(); await db.end(); }
  });

  it("exposes only owned creature training state and derives trainability from server state", async () => {
    const db = createDbPool();
    const app = await buildApp({ db });
    try {
      const owner = await register(app);
      const other = await register(app);
      await app.inject({ method: "GET", url: "/creature-research",
        headers: { authorization: `Bearer ${owner.accessToken}` } });
      await app.inject({ method: "GET", url: "/creature-research",
        headers: { authorization: `Bearer ${other.accessToken}` } });
      const creature = await db.query<{ id: string }>(
        `INSERT INTO player_creatures
          (owner_user_id,wild_source_id,species,level,xp,health,max_health,attack,defense,element,ability_ids,tame_progress,party_slot,ai_mode,x,y)
         VALUES ($1,$2,'slime',1,0,45,45,18,2,'water','[]'::jsonb,100,NULL,'follow',1,1)
         RETURNING id`,
        [owner.user.id, `training-${randomUUID()}`],
      );
      await db.query(
        "INSERT INTO creature_training_progress(creature_id,experience,bond,learned_commands) VALUES($1,120,68,$2::jsonb)",
        [creature.rows[0].id, JSON.stringify(["follow"])],
      );
      await db.query(
        "INSERT INTO player_creature_skills(user_id,skill_id,experience) VALUES($1,'creature_training',0)",
        [owner.user.id],
      );

      const ownerResponse = await app.inject({ method: "GET", url: "/creature-training",
        headers: { authorization: `Bearer ${owner.accessToken}` } });
      expect(ownerResponse.statusCode).toBe(200);
      expect(ownerResponse.json()).toEqual({ creatures: [{
        id: creature.rows[0].id, species: "slime", nickname: null, level: 1,
        tameProgress: 100, trainingExperience: 120, bond: 68,
        learnedCommands: ["follow"], trainingUnlocked: true, trainable: true,
      }] });

      const otherResponse = await app.inject({ method: "GET", url: "/creature-training",
        headers: { authorization: `Bearer ${other.accessToken}` } });
      expect(otherResponse.statusCode).toBe(200);
      expect(otherResponse.json()).toEqual({ creatures: [] });
    } finally { await app.close(); await db.end(); }
  });

  it("rejects missing research prerequisites and materials without persisting a failed request", async () => {
    const db = createDbPool();
    const app = await buildApp({ db });
    try {
      const owner = await register(app);
      await new BaseStore(db).create(owner.user.id, "Research Base", 0, 0);
      const auth = { authorization: `Bearer ${owner.accessToken}` };
      const blocked = await app.inject({
        method: "POST", url: "/creature-research/unlock", headers: auth,
        payload: { requestId: "prereq-1", skillId: "aerial_riding" },
      });
      expect(blocked.statusCode).toBe(409);
      expect(blocked.json()).toMatchObject({ error: "SKILL_PREREQUISITE_MISSING" });

      const payload = { requestId: "materials-retry-1", skillId: "tracking" };
      const insufficient = await app.inject({ method: "POST", url: "/creature-research/unlock", headers: auth, payload });
      expect(insufficient.statusCode).toBe(409);
      await db.query("UPDATE player_profiles SET inventory=$2::jsonb WHERE user_id=$1", [
        owner.user.id, JSON.stringify({ "resource.herb": 1 }),
      ]);
      const corrected = await app.inject({ method: "POST", url: "/creature-research/unlock", headers: auth, payload });
      expect(corrected.statusCode).toBe(200);
      const invalid = await app.inject({ method: "POST", url: "/creature-research/unlock", headers: auth,
        payload: { requestId: "invalid-1", skillId: "__proto__" },
      });
      expect(invalid.statusCode).toBe(400);
    } finally { await app.close(); await db.end(); }
  });
});
