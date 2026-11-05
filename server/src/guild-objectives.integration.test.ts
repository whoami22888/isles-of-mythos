import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { PlayerStore } from "./player.js";
import { GUILD_OBJECTIVES, progressFor } from "./guild-objectives.js";

// Guild progress comes only from committed gather-ledger rows of current members, made
// after they joined, inside the current UTC week. Rows are seeded exactly as
// gatherResource commits them.
let db: Pool;
let app: FastifyInstance;

beforeAll(async () => { db = createDbPool(); app = await buildApp({ db }); });
afterAll(async () => { await app.close(); await db.end(); });

async function player() {
  const unique = randomUUID().replace(/-/g, "").slice(0, 20);
  const res = await app.inject({ method: "POST", url: "/auth/register", payload: { username: `go_${unique}`, email: `go_${unique}@example.com`, password: "Correct-Horse-Battery-9" } });
  expect(res.statusCode).toBe(201);
  const body = JSON.parse(res.body) as { user: { id: string }; accessToken: string };
  await new PlayerStore(db).loadOrCreate(body.user.id);
  await db.query("UPDATE player_profiles SET gold=0 WHERE user_id=$1", [body.user.id]);
  const auth = { authorization: `Bearer ${body.accessToken}` };
  return {
    id: body.user.id,
    claim: () => app.inject({ method: "POST", url: "/guild-objectives/claim", headers: auth, payload: { objectiveId: "guild.wood" } }),
    view: async () => JSON.parse((await app.inject({ method: "GET", url: "/guild-objectives", headers: auth })).body) as { guildId: string | null; objectives: { guildProgress: number; myContribution: number; complete: boolean; eligible: boolean; claimed: boolean }[] },
    gold: async () => (await db.query<{ gold: string }>("SELECT gold FROM player_profiles WHERE user_id=$1", [body.user.id])).rows[0]?.gold,
  };
}
async function guild(leaderId: string) {
  const tag = randomUUID().slice(0, 6);
  const g = await db.query<{ id: string }>("INSERT INTO guilds(name, tag, leader_user_id) VALUES($1,$2,$3) RETURNING id", [`Guild ${tag}`, tag, leaderId]);
  return g.rows[0]?.id ?? "";
}
const join = (guildId: string, userId: string, at = "now()") => db.query(`INSERT INTO guild_members(guild_id, user_id, rank, joined_at) VALUES($1,$2,'member',${at})`, [guildId, userId]);
const gathered = (userId: string, quantity: number, at = "now()") =>
  db.query(`INSERT INTO resource_gather_requests(user_id,request_id,fingerprint,node_id,item_id,quantity,respawns_at,created_at) VALUES($1,$2,'seed','seed-node','resource.wood',$3,now(),${at})`, [userId, randomUUID().slice(0, 32), quantity]);
const weekStart = "date_trunc('week', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'";

describe("guild objectives", () => {
  it("requires guild membership", async () => {
    const solo = await player();
    expect((await solo.view()).objectives).toEqual([]);
    const res = await solo.claim();
    expect(res.statusCode).toBe(409);
    expect(JSON.parse(res.body)).toEqual({ error: "GUILD_MEMBERSHIP_REQUIRED" });
  });

  it("pays each contributing member once when the guild total is reached", async () => {
    const a = await player(); const b = await player();
    const g = await guild(a.id);
    await join(g, a.id, `${weekStart} - interval '1 day'`); await join(g, b.id, `${weekStart} - interval '1 day'`);
    await gathered(a.id, 150);
    expect((await a.claim()).statusCode).toBe(409);
    await gathered(b.id, 50);
    await gathered(a.id, 500, `${weekStart} - interval '1 hour'`); // last week: ignored
    const view = await a.view();
    expect(view.objectives[0]).toMatchObject({ guildProgress: 200, myContribution: 150, complete: true, eligible: true, claimed: false });
    const results = await Promise.all([a.claim(), a.claim(), a.claim(), b.claim(), b.claim()]);
    expect(results.every((r) => r.statusCode === 200)).toBe(true);
    expect(results.filter((r) => !(JSON.parse(r.body) as { replayed: boolean }).replayed)).toHaveLength(2);
    expect(await a.gold()).toBe("30");
    expect(await b.gold()).toBe("30");
    const audit = await db.query("SELECT 1 FROM economy_transactions WHERE user_id = ANY($1) AND operation='guild_objective_claim'", [[a.id, b.id]]);
    expect(audit.rowCount).toBe(2);
  });

  it("does not pay a late joiner who has not contributed, and ignores their pre-join gathers", async () => {
    const a = await player(); const late = await player();
    const g = await guild(a.id);
    await join(g, a.id, `${weekStart} - interval '1 day'`);
    await gathered(a.id, 200);
    await gathered(late.id, 40, "now() - interval '1 minute'"); // before joining
    await join(g, late.id);
    const view = await late.view();
    expect(view.objectives[0]).toMatchObject({ guildProgress: 200, myContribution: 0, complete: true, eligible: false });
    const res = await late.claim();
    expect(res.statusCode).toBe(409);
    expect(JSON.parse(res.body)).toEqual({ error: "GUILD_CONTRIBUTION_REQUIRED" });
    expect(await late.gold()).toBe("0");
  });

  it("guild hopping cannot claim the same week twice", async () => {
    const a = await player(); const hopper = await player(); const c = await player();
    const g1 = await guild(a.id); const g2 = await guild(c.id);
    await join(g1, a.id, `${weekStart} - interval '1 day'`); await join(g1, hopper.id, `${weekStart} - interval '1 day'`);
    await join(g2, c.id, `${weekStart} - interval '1 day'`);
    await gathered(a.id, 190); await gathered(hopper.id, 10); await gathered(c.id, 200);
    expect((await hopper.claim()).statusCode).toBe(200);
    await db.query("DELETE FROM guild_members WHERE user_id=$1", [hopper.id]);
    await join(g2, hopper.id, `${weekStart} - interval '1 day'`);
    await gathered(hopper.id, 10);
    const again = await hopper.claim();
    expect(JSON.parse(again.body)).toMatchObject({ replayed: true });
    expect(await hopper.gold()).toBe("30");
  });

  it("keeps the UTC week window exact when the PostgreSQL session time zone observes DST", async () => {
    // Sydney leaves DST on Sunday 2026-04-05, inside the UTC week starting Monday 2026-03-30.
    const a = await player();
    const g = await guild(a.id);
    await join(g, a.id, "'2026-03-01T00:00:00Z'");
    await gathered(a.id, 7, "'2026-04-05T23:30:00Z'"); // last 30 minutes of the UTC week: counts
    await gathered(a.id, 40, "'2026-04-06T00:30:00Z'"); // next UTC week: must not count
    await gathered(a.id, 900, "'2026-03-29T23:30:00Z'"); // previous UTC week: must not count
    const objective = GUILD_OBJECTIVES.find((o) => o.id === "guild.wood");
    if (!objective) throw new Error("guild.wood objective missing");
    const client = await db.connect();
    try {
      await client.query("BEGIN");
      await client.query("SET LOCAL TIME ZONE 'Australia/Sydney'");
      const progress = await progressFor(client, a.id, objective, new Date("2026-04-02T12:00:00Z"));
      expect(progress).toMatchObject({ weekStart: "2026-03-30", guildTotal: 7, mine: 7 });
    } finally {
      await client.query("ROLLBACK");
      client.release();
    }
  });
});
