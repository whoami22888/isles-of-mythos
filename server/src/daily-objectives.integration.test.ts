import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { PlayerStore } from "./player.js";
import { DAILY_OBJECTIVES, progressFor, utcDay } from "./daily-objectives.js";

// Progress comes only from the authoritative gather/craft ledgers. These tests seed
// committed ledger rows directly, exactly as gatherResource/craft would leave them.
async function setup() {
  const db = createDbPool();
  const app = await buildApp({ db });
  const unique = randomUUID().replace(/-/g, "").slice(0, 20);
  const res = await app.inject({ method: "POST", url: "/auth/register", payload: { username: `daily_${unique}`, email: `daily_${unique}@example.com`, password: "Correct-Horse-Battery-9" } });
  expect(res.statusCode).toBe(201);
  const body = JSON.parse(res.body) as { user: { id: string }; accessToken: string };
  await new PlayerStore(db).loadOrCreate(body.user.id);
  const userId = body.user.id;
  await db.query("UPDATE player_profiles SET gold=100 WHERE user_id=$1", [userId]);
  const gathered = async (itemId: string, quantity: number, at = "CURRENT_TIMESTAMP") => {
    await db.query(
      `INSERT INTO resource_gather_requests(user_id,request_id,fingerprint,node_id,item_id,quantity,respawns_at,created_at) VALUES($1,$2,'seed','seed-node',$3,$4,CURRENT_TIMESTAMP,${at})`,
      [userId, randomUUID(), itemId, quantity],
    );
  };
  const gold = async () => (await db.query<{ gold: string }>("SELECT gold FROM player_profiles WHERE user_id=$1", [userId])).rows[0]?.gold;
  const auth = { authorization: `Bearer ${body.accessToken}` };
  const claim = (objectiveId: string, headers = auth) => app.inject({ method: "POST", url: "/daily-objectives/claim", headers, payload: { objectiveId } });
  const list = async () => JSON.parse((await app.inject({ method: "GET", url: "/daily-objectives", headers: auth })).body) as { day: string; objectives: { objectiveId: string; progress: number; complete: boolean; claimed: boolean }[] };
  const close = async () => { await app.close(); await db.end(); };
  return { db, app, userId, gathered, gold, claim, list, close };
}

describe("daily objectives", () => {
  it("lists today's objectives with ledger-derived progress", async () => {
    const t = await setup();
    try {
      const view = await t.list();
      expect(view.day).toBe(utcDay(new Date()));
      expect(view.objectives.map((o) => o.objectiveId)).toEqual(DAILY_OBJECTIVES.map((o) => o.id));
      expect(view.objectives.every((o) => o.progress === 0 && !o.complete && !o.claimed)).toBe(true);
      await t.gathered("resource.wood", 4);
      await t.gathered("resource.wood", 2, "CURRENT_TIMESTAMP - interval '2 days'");
      const wood = (await t.list()).objectives.find((o) => o.objectiveId === "gather.wood");
      expect(wood).toMatchObject({ progress: 4, complete: false });
    } finally { await t.close(); }
  });

  it("refuses an incomplete claim without moving gold", async () => {
    const t = await setup();
    try {
      await t.gathered("resource.wood", 8);
      const res = await t.claim("gather.wood");
      expect(res.statusCode).toBe(409);
      expect(JSON.parse(res.body)).toEqual({ error: "DAILY_OBJECTIVE_INCOMPLETE" });
      expect(await t.gold()).toBe("100");
    } finally { await t.close(); }
  });

  it("pays a completed objective once and replays later claims", async () => {
    const t = await setup();
    try {
      for (let i = 0; i < 5; i++) await t.gathered("resource.wood", 2);
      const first = await t.claim("gather.wood");
      expect(first.statusCode).toBe(200);
      const body = JSON.parse(first.body) as { transactionId: string; replayed: boolean; rewardGold: string };
      expect(body).toMatchObject({ replayed: false, rewardGold: "50" });
      expect(await t.gold()).toBe("150");
      const again = JSON.parse((await t.claim("gather.wood")).body) as { transactionId: string; replayed: boolean };
      expect(again).toEqual(expect.objectContaining({ transactionId: body.transactionId, replayed: true }));
      expect(await t.gold()).toBe("150");
      expect((await t.list()).objectives.find((o) => o.objectiveId === "gather.wood")?.claimed).toBe(true);
    } finally { await t.close(); }
  });

  it("concurrent claims credit exactly once", async () => {
    const t = await setup();
    try {
      await t.gathered("resource.stone", 6);
      const results = await Promise.all(Array.from({ length: 6 }, () => t.claim("gather.stone")));
      expect(results.every((r) => r.statusCode === 200)).toBe(true);
      const bodies = results.map((r) => JSON.parse(r.body) as { replayed: boolean; transactionId: string });
      expect(bodies.filter((b) => !b.replayed)).toHaveLength(1);
      expect(new Set(bodies.map((b) => b.transactionId)).size).toBe(1);
      expect(await t.gold()).toBe("140");
      const ledger = await t.db.query("SELECT 1 FROM daily_objective_claims WHERE user_id=$1", [t.userId]);
      expect(ledger.rowCount).toBe(1);
      // Replays must not write economy audit rows: only the real payout is recorded.
      const audit = await t.db.query("SELECT 1 FROM economy_transactions WHERE user_id=$1 AND operation='daily_objective_claim'", [t.userId]);
      expect(audit.rowCount).toBe(1);
    } finally { await t.close(); }
  });

  it("does not count yesterday's gathers toward today", async () => {
    const t = await setup();
    try {
      await t.gathered("resource.stone", 20, "CURRENT_TIMESTAMP - interval '1 day'");
      expect((await t.claim("gather.stone")).statusCode).toBe(409);
      expect(await t.gold()).toBe("100");
    } finally { await t.close(); }
  });

  it("rejects unknown objectives, malformed ids and non-player tokens", async () => {
    const t = await setup();
    try {
      expect((await t.claim("gather.gold")).statusCode).toBe(404);
      expect((await t.claim("DROP TABLE")).statusCode).toBe(400);
      const admin = t.app.jwt.sign({ sub: t.userId, username: "x", role: "admin", typ: "access" }, { expiresIn: "5m" });
      expect((await t.claim("gather.wood", { authorization: `Bearer ${admin}` })).statusCode).toBe(401);
      expect((await t.app.inject({ method: "GET", url: "/daily-objectives" })).statusCode).toBe(401);
    } finally { await t.close(); }
  });

  it("uses UTC ledger boundaries with a non-UTC PostgreSQL session", async () => {
    const t = await setup();
    const client = await t.db.connect();
    try {
      await client.query("BEGIN");
      await client.query("SET LOCAL TIME ZONE 'Australia/Sydney'");
      const day = "2026-11-06";
      const rows = [
        { at: "2026-11-05T13:30:00Z", quantity: 5 }, // Nov 6 Sydney, Nov 5 UTC
        { at: "2026-11-06T00:30:00Z", quantity: 7 }, // Nov 6 UTC
      ];
      for (const row of rows) {
        await client.query(
          "INSERT INTO resource_gather_requests(user_id,request_id,fingerprint,node_id,item_id,quantity,respawns_at,created_at) VALUES($1,$2,'seed','seed-node','resource.wood',$3,now(),$4::timestamptz)",
          [t.userId, randomUUID(), row.quantity, row.at],
        );
        await client.query(
          "INSERT INTO craft_requests(request_key,user_id,fingerprint,response,created_at) VALUES($1,$2,'test.recipe','{}'::jsonb,$3::timestamptz)",
          [t.userId + ":" + randomUUID(), t.userId, row.at],
        );
      }
      const wood = DAILY_OBJECTIVES.find((objective) => objective.id === "gather.wood");
      const craft = DAILY_OBJECTIVES.find((objective) => objective.id === "craft.any");
      if (!wood || !craft) throw new Error("TEST_OBJECTIVE_MISSING");
      expect(await progressFor(client, t.userId, wood, day)).toBe(7);
      expect(await progressFor(client, t.userId, craft, day)).toBe(1);
    } finally {
      await client.query("ROLLBACK");
      client.release();
      await t.close();
    }
  });


});
