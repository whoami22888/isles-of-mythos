import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { BaseStore } from "./base.js";
import { PlayerStore } from "./player.js";
import { ShipStore } from "./ship.js";
import { NavalStore } from "./naval.js";

// Owner decision D-07 (2026-10-29): NPC crew is paid and fail-closed. Pirate 100 and specialist 250 Gold Doubloons,
// debited atomically with the hire; dragons and mermaids cannot be hired (they are captured/tamed/researched).

async function register(app: FastifyInstance, tag: string): Promise<{ userId: string; token: string }> {
  const unique = tag + "_" + Date.now().toString(36).slice(-7) + "_" + Math.random().toString(36).slice(2, 5);
  const response = await app.inject({ method: "POST", url: "/auth/register", payload: { username: unique, email: unique + "@example.com", password: "Correct-Horse-Battery-9" } });
  expect(response.statusCode).toBe(201);
  const body = JSON.parse(response.body) as { accessToken: string; user: { id: string } };
  return { userId: body.user.id, token: body.accessToken };
}

async function withShip(db: Pool, userId: string, gold: bigint): Promise<string> {
  await new PlayerStore(db).loadOrCreate(userId);
  const base = await new BaseStore(db).create(userId, "Hire Base", 0, 0);
  await db.query("INSERT INTO base_storage(base_id,resource_key,quantity) VALUES($1,'wood',5000),($1,'steel',5000) ON CONFLICT (base_id,resource_key) DO UPDATE SET quantity=EXCLUDED.quantity", [base.id]);
  await db.query("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'shipyard',1,1,0,true)", [base.id]);
  await db.query("UPDATE player_profiles SET gold=$2 WHERE user_id=$1", [userId, gold.toString()]);
  return (await new ShipStore(db).create(userId, "Hire Galleon", "galleon")).id;
}

const goldOf = async (db: Pool, userId: string): Promise<bigint> => BigInt((await db.query<{ gold: string }>("SELECT gold FROM player_profiles WHERE user_id=$1", [userId])).rows[0].gold);
const crewCount = async (db: Pool, shipId: string): Promise<number> => Number((await db.query<{ n: string }>("SELECT COUNT(*)::text n FROM ship_crew WHERE ship_id=$1", [shipId])).rows[0].n);
const hireLedger = async (db: Pool, userId: string): Promise<Array<{ gold_before: string; gold_after: string }>> =>
  (await db.query<{ gold_before: string; gold_after: string }>("SELECT gold_before, gold_after FROM economy_transactions WHERE user_id=$1 AND operation='ship_npc_crew_hire' ORDER BY gold_before::bigint DESC", [userId])).rows;

describe("paid, fail-closed NPC crew (D-07)", () => {
  const db = createDbPool();
  let app: FastifyInstance;
  beforeAll(async () => { app = await buildApp({ db }); });
  afterAll(async () => { await app.close(); await db.end(); });

  it("debits 5,000 for a pirate and 25,000 for a specialist atomically and records each hire in the economy ledger", async () => {
    const { userId } = await register(app, "hp");
    const shipId = await withShip(db, userId, 40_000n);
    const naval = new NavalStore(db);
    const pirate = await naval.assignNpcCrew(userId, shipId, "pirate", "boarding_specialist");
    expect(pirate.npcType).toBe("pirate");
    expect(await goldOf(db, userId)).toBe(35_000n);
    const specialist = await naval.assignNpcCrew(userId, shipId, "npc_specialist", "engineer");
    expect(specialist.npcType).toBe("npc_specialist");
    expect(await goldOf(db, userId)).toBe(10_000n);
    expect(await crewCount(db, shipId)).toBe(2);
    expect(await hireLedger(db, userId)).toEqual([
      { gold_before: "40000", gold_after: "35000" },
      { gold_before: "35000", gold_after: "10000" },
    ]);
  });

  it("rejects dragon and mermaid without charging or creating crew", async () => {
    const { userId } = await register(app, "uc");
    const shipId = await withShip(db, userId, 50_000n);
    const naval = new NavalStore(db);
    await expect(naval.assignNpcCrew(userId, shipId, "dragon", "gunner")).rejects.toThrow("NPC_CREW_UNAVAILABLE");
    await expect(naval.assignNpcCrew(userId, shipId, "mermaid", "medic")).rejects.toThrow("NPC_CREW_UNAVAILABLE");
    expect(await goldOf(db, userId)).toBe(50_000n);
    expect(await crewCount(db, shipId)).toBe(0);
    expect(await hireLedger(db, userId)).toEqual([]);
  });

  it("rejects an unaffordable hire with INSUFFICIENT_GOLD and leaves gold, crew and ledger untouched", async () => {
    const { userId } = await register(app, "ig");
    const shipId = await withShip(db, userId, 4_999n);
    const naval = new NavalStore(db);
    await expect(naval.assignNpcCrew(userId, shipId, "pirate", "gunner")).rejects.toThrow("INSUFFICIENT_GOLD");
    expect(await goldOf(db, userId)).toBe(4_999n);
    expect(await crewCount(db, shipId)).toBe(0);
    expect(await hireLedger(db, userId)).toEqual([]);
  });

  it("does not charge when the ship is full (the failed hire rolls back)", async () => {
    const { userId } = await register(app, "cf");
    const shipId = await withShip(db, userId, 1_000_000n);
    const naval = new NavalStore(db);
    const { rows } = await db.query<{ crew_capacity: number }>("SELECT crew_capacity FROM player_ships WHERE id=$1", [shipId]);
    for (let i = 0; i < rows[0].crew_capacity; i += 1) await naval.assignNpcCrew(userId, shipId, "pirate", "gunner");
    const before = await goldOf(db, userId);
    await expect(naval.assignNpcCrew(userId, shipId, "pirate", "gunner")).rejects.toThrow("SHIP_CREW_CAPACITY_REACHED");
    expect(await goldOf(db, userId)).toBe(before);
    expect(await crewCount(db, shipId)).toBe(rows[0].crew_capacity);
  });

  it("charges exactly once when two hires race with gold for only one", async () => {
    const { userId } = await register(app, "rc");
    const shipId = await withShip(db, userId, 7_500n);
    const naval = new NavalStore(db);
    const results = await Promise.allSettled([
      naval.assignNpcCrew(userId, shipId, "pirate", "gunner"),
      naval.assignNpcCrew(userId, shipId, "pirate", "navigator"),
    ]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    const rejected = results.find((r) => r.status === "rejected") as PromiseRejectedResult;
    expect((rejected.reason as Error).message).toBe("INSUFFICIENT_GOLD");
    expect(await goldOf(db, userId)).toBe(2_500n);
    expect(await crewCount(db, shipId)).toBe(1);
    expect(await hireLedger(db, userId)).toHaveLength(1);
  });
});

describe("durable hire idempotency (Codex P1: replay survives cache loss, restart and other instances)", () => {
  const db = createDbPool();
  let app: FastifyInstance;
  beforeAll(async () => { app = await buildApp({ db }); });
  afterAll(async () => { await app.close(); await db.end(); });
  const req = (requestId: string, role = "gunner") => ({ requestId, fingerprint: `assign_ship_npc_crew|S|pirate|${role}` });

  it("replaying the same requestId returns the same crew member and charges once", async () => {
    const { userId } = await register(app, "dr");
    const shipId = await withShip(db, userId, 20_000n);
    const naval = new NavalStore(db);
    const first = await naval.assignNpcCrew(userId, shipId, "pirate", "gunner", req("durable-1"));
    const second = await new NavalStore(db).assignNpcCrew(userId, shipId, "pirate", "gunner", req("durable-1"));
    expect(second).toEqual(first);
    expect(await goldOf(db, userId)).toBe(15_000n);
    expect(await crewCount(db, shipId)).toBe(1);
    expect(await hireLedger(db, userId)).toHaveLength(1);
  });

  it("rejects the same requestId with a different fingerprint and charges nothing more", async () => {
    const { userId } = await register(app, "dc");
    const shipId = await withShip(db, userId, 20_000n);
    const naval = new NavalStore(db);
    await naval.assignNpcCrew(userId, shipId, "pirate", "gunner", req("durable-2"));
    await expect(naval.assignNpcCrew(userId, shipId, "pirate", "navigator", req("durable-2", "navigator"))).rejects.toThrow("NPC_CREW_REQUEST_CONFLICT");
    expect(await goldOf(db, userId)).toBe(15_000n);
    expect(await crewCount(db, shipId)).toBe(1);
  });

  it("concurrent duplicates of one requestId (separate store instances) charge exactly once", async () => {
    const { userId } = await register(app, "dp");
    const shipId = await withShip(db, userId, 20_000n);
    const results = await Promise.all([1, 2, 3].map(() => new NavalStore(db).assignNpcCrew(userId, shipId, "pirate", "gunner", req("durable-3"))));
    expect(new Set(results.map((r) => r.id)).size).toBe(1);
    expect(await goldOf(db, userId)).toBe(15_000n);
    expect(await crewCount(db, shipId)).toBe(1);
  });

  it("concurrent hires with distinct requestIds on one ship do not deadlock (Codex P2): both succeed and both are charged", async () => {
    const { userId } = await register(app, "dd");
    const shipId = await withShip(db, userId, 20_000n);
    for (let round = 0; round < 5; round += 1) {
      await db.query("UPDATE player_profiles SET gold=20000 WHERE user_id=$1", [userId]);
      await db.query("DELETE FROM ship_crew WHERE ship_id=$1", [shipId]);
      const results = await Promise.allSettled([1, 2, 3, 4].map((n) => new NavalStore(db).assignNpcCrew(userId, shipId, "pirate", "gunner", req(`dd-${round}-${n}`))));
      expect(results.map((r) => (r.status === "rejected" ? (r.reason as Error).message : "ok"))).toEqual(["ok", "ok", "ok", "ok"]);
      expect(await goldOf(db, userId)).toBe(0n);
      expect(await crewCount(db, shipId)).toBe(4);
    }
  });

  it("a failed hire does not burn the requestId: it can be retried once gold arrives", async () => {
    const { userId } = await register(app, "df");
    const shipId = await withShip(db, userId, 10n);
    const naval = new NavalStore(db);
    await expect(naval.assignNpcCrew(userId, shipId, "pirate", "gunner", req("durable-4"))).rejects.toThrow("INSUFFICIENT_GOLD");
    await db.query("UPDATE player_profiles SET gold=6000 WHERE user_id=$1", [userId]);
    await naval.assignNpcCrew(userId, shipId, "pirate", "gunner", req("durable-4"));
    expect(await goldOf(db, userId)).toBe(1_000n);
  });

  it("does not collide with a cargo request that reuses the same requestId", async () => {
    const { userId } = await register(app, "dx");
    const shipId = await withShip(db, userId, 20_000n);
    await db.query("INSERT INTO ship_cargo_requests(request_key,user_id,fingerprint,response) VALUES($1,$2,'cargo','{}'::jsonb)", [userId + ":shared-id", userId]);
    await new NavalStore(db).assignNpcCrew(userId, shipId, "pirate", "gunner", req("shared-id"));
    expect(await crewCount(db, shipId)).toBe(1);
  });
});

describe("paid NPC crew over the WebSocket: replay, state push and error codes (D-07)", () => {
  const db = createDbPool();
  let app: FastifyInstance;
  let wsUrl = "";
  const sockets: WebSocket[] = [];
  beforeAll(async () => {
    app = await buildApp({ db });
    await app.listen({ host: "127.0.0.1", port: 0 });
    const address = app.server.address();
    if (address === null || typeof address === "string") throw new Error("TEST_SERVER_NOT_LISTENING");
    wsUrl = `ws://127.0.0.1:${address.port}/ws`;
  });
  afterAll(async () => { for (const s of sockets) s.close(); await app.close(); await db.end(); });

  type Msg = Record<string, unknown> & { type: string };
  async function connect(token: string): Promise<{ send: (m: unknown) => void; next: (pred: (m: Msg) => boolean, label: string) => Promise<Msg> }> {
    const socket = new WebSocket(wsUrl);
    sockets.push(socket);
    const seen: Msg[] = [];
    socket.on("message", (raw: Buffer) => seen.push(JSON.parse(raw.toString()) as Msg));
    await new Promise<void>((resolve, reject) => { socket.once("open", () => resolve()); socket.once("error", reject); });
    let cursor = 0;
    const next = async (pred: (m: Msg) => boolean, label: string): Promise<Msg> => {
      const deadline = Date.now() + 8_000;
      for (;;) {
        while (cursor < seen.length) { const m = seen[cursor++]; if (pred(m)) return m; }
        if (Date.now() > deadline) throw new Error(`TIMEOUT ${label}; saw ${JSON.stringify(seen.map((m) => m.type))}`);
        await new Promise((r) => setTimeout(r, 10));
      }
    };
    const send = (m: unknown): void => socket.send(JSON.stringify(m));
    send({ type: "auth", token });
    await next((m) => m.type === "auth_ok", "auth_ok");
    return { send, next };
  }

  it("a replayed requestId returns the same crew and charges once; a conflicting replay is rejected; the player_state gold is pushed", async () => {
    const { userId, token } = await register(app, "wr");
    const shipId = await withShip(db, userId, 12_000n);
    const ws = await connect(token);
    const hire = { type: "assign_ship_npc_crew", requestId: "hire-1", shipId, npcType: "pirate", role: "gunner" };
    ws.send(hire);
    const first = await ws.next((m) => m.type === "ship_crew" || m.type === "error", "ship_crew #1");
    expect(first.type).toBe("ship_crew");
    const pushed = await ws.next((m) => m.type === "player_state", "player_state after hire");
    expect((pushed.state as { gold: string }).gold).toBe("7000");
    ws.send(hire);
    const second = await ws.next((m) => m.type === "ship_crew" || m.type === "error", "ship_crew replay");
    expect(second.type).toBe("ship_crew");
    expect((second.crew as { id: string }).id).toBe((first.crew as { id: string }).id);
    expect(await goldOf(db, userId)).toBe(7_000n);
    expect(await crewCount(db, shipId)).toBe(1);
    ws.send({ ...hire, role: "navigator" });
    const conflict = await ws.next((m) => m.type === "ship_crew" || m.type === "error", "conflicting replay");
    expect(conflict).toMatchObject({ type: "error", code: "INVALID_MESSAGE" });
    expect(await goldOf(db, userId)).toBe(7_000n);
  });

  it("maps NPC_CREW_UNAVAILABLE and INSUFFICIENT_GOLD to their own error codes", async () => {
    const { userId, token } = await register(app, "we");
    const shipId = await withShip(db, userId, 10n);
    const ws = await connect(token);
    ws.send({ type: "assign_ship_npc_crew", requestId: "dragon-1", shipId, npcType: "dragon", role: "gunner" });
    expect(await ws.next((m) => m.type === "ship_crew" || m.type === "error", "dragon")).toMatchObject({ type: "error", code: "NPC_CREW_UNAVAILABLE" });
    ws.send({ type: "assign_ship_npc_crew", requestId: "pirate-poor", shipId, npcType: "pirate", role: "gunner" });
    expect(await ws.next((m) => m.type === "ship_crew" || m.type === "error", "poor")).toMatchObject({ type: "error", code: "INSUFFICIENT_GOLD" });
    expect(await goldOf(db, userId)).toBe(10n);
  });

  it("a replay arriving at a different server instance (empty in-memory cache) is still served from the database", async () => {
    const { userId, token } = await register(app, "xi");
    const shipId = await withShip(db, userId, 20_000n);
    const db2 = createDbPool();
    const app2 = await buildApp({ db: db2 });
    try {
      await app2.listen({ host: "127.0.0.1", port: 0 });
      const addr = app2.server.address();
      if (addr === null || typeof addr === "string") throw new Error("TEST_SERVER_NOT_LISTENING");
      const hire = { type: "assign_ship_npc_crew", requestId: "xi-1", shipId, npcType: "pirate", role: "gunner" };
      const ws1 = await connect(token);
      ws1.send(hire);
      const a = await ws1.next((m) => m.type === "ship_crew" || m.type === "error", "instance 1");
      const socket2 = new WebSocket(`ws://127.0.0.1:${addr.port}/ws`);
      sockets.push(socket2);
      const seen2: Msg[] = [];
      socket2.on("message", (raw: Buffer) => seen2.push(JSON.parse(raw.toString()) as Msg));
      await new Promise<void>((resolve, reject) => { socket2.once("open", () => resolve()); socket2.once("error", reject); });
      socket2.send(JSON.stringify({ type: "auth", token }));
      const waitFor = async (type: string): Promise<Msg> => { for (let i = 0; i < 800; i += 1) { const m = seen2.find((x) => x.type === type || x.type === "error"); if (m) return m; await new Promise((r) => setTimeout(r, 10)); } throw new Error("TIMEOUT " + type); };
      await waitFor("auth_ok");
      seen2.length = 0;
      socket2.send(JSON.stringify(hire));
      const b = await waitFor("ship_crew");
      expect(a.type).toBe("ship_crew");
      expect(b.type).toBe("ship_crew");
      expect((b.crew as { id: string }).id).toBe((a.crew as { id: string }).id);
      expect(await goldOf(db, userId)).toBe(15_000n);
      expect(await crewCount(db, shipId)).toBe(1);
    } finally { await app2.close(); await db2.end(); }
  });
});
