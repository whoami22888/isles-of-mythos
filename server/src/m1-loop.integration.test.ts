import { randomUUID } from "node:crypto";
import { performance } from "node:perf_hooks";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import type { PublicPlayerState } from "./player.js";
import type { ResourceNode } from "./world.js";

/**
 * M1 "First Playable Loop" server contract.
 *
 * Exercises exactly what a phone client performs, over a real WebSocket against the real app and PostgreSQL,
 * using only existing HTTP routes and wire messages: register -> login -> /ws auth -> subscribe_chunks ->
 * move -> gather_resource (+ replay) -> disconnect -> reconnect and verify persisted state.
 *
 * Timings logged by this file are local wall-clock round trips on a developer machine, not an SLO result.
 */

const GATHER_RANGE = 2.5; // app.ts gather_resource handler: distance(state, node) > 2.5 -> RESOURCE_OUT_OF_RANGE
const WAIT_MS = 5_000;
const CHUNK_SIZE = 32;

const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

type Msg = Record<string, unknown> & { type: string };

/** Buffers every server message so no frame can be lost between send and wait. */
class WsClient {
  readonly messages: Msg[] = [];
  closeCode: number | undefined;
  constructor(readonly socket: WebSocket) {
    socket.on("message", (raw: Buffer) => this.messages.push(JSON.parse(raw.toString()) as Msg));
    socket.once("close", (code: number) => { this.closeCode = code; });
  }
  static async connect(url: string): Promise<WsClient> {
    const client = new WsClient(new WebSocket(url));
    await new Promise<void>((resolve, reject) => {
      client.socket.once("open", () => resolve());
      client.socket.once("error", reject);
    });
    return client;
  }
  mark(): number { return this.messages.length; }
  send(message: unknown): void { this.socket.send(typeof message === "string" ? message : JSON.stringify(message)); }
  async waitFor(predicate: (m: Msg) => boolean, from = 0, label = "message"): Promise<Msg> {
    const deadline = Date.now() + WAIT_MS;
    let cursor = from;
    for (;;) {
      while (cursor < this.messages.length) {
        const candidate = this.messages[cursor++];
        if (predicate(candidate)) return candidate;
      }
      if (Date.now() > deadline) throw new Error(`TIMEOUT waiting for ${label}; saw ${JSON.stringify(this.messages.slice(from).map((m) => m.type))}`);
      await new Promise((resolve) => setTimeout(resolve, 5));
    }
  }
  /** Send a message and return the first reply of one of `types` (or an error frame) after the send. */
  async request(message: unknown, types: string[]): Promise<Msg> {
    const from = this.mark();
    this.send(message);
    return this.waitFor((m) => types.includes(m.type) || m.type === "error", from, types.join("|"));
  }
  async waitClosed(): Promise<number> {
    const deadline = Date.now() + WAIT_MS;
    while (this.closeCode === undefined) {
      if (Date.now() > deadline) throw new Error("TIMEOUT waiting for close");
      await sleep(5);
    }
    return this.closeCode;
  }
  close(): void { if (this.socket.readyState === WebSocket.OPEN || this.socket.readyState === WebSocket.CONNECTING) this.socket.close(); }
}

function dist(a: { x: number; y: number }, b: { x: number; y: number }): number { return Math.hypot(a.x - b.x, a.y - b.y); }

describe("M1 first playable loop (server contract)", () => {
  const db = createDbPool();
  let app: Awaited<ReturnType<typeof buildApp>>;
  let wsUrl = "";
  const clients: WsClient[] = [];
  const unique = randomUUID().replace(/-/g, "").slice(0, 20);
  const credentials = {
    username: `m1_${unique}`,
    email: `m1_${unique}@example.com`,
    password: "Correct-Horse-Battery-9",
  };
  let userId = "";
  let token = "";
  let touchedNodeId: string | undefined;

  beforeAll(async () => {
    app = await buildApp({ db });
    await app.listen({ host: "127.0.0.1", port: 0 });
    const address = app.server.address();
    if (address === null || typeof address === "string") throw new Error("TEST_SERVER_NOT_LISTENING");
    wsUrl = `ws://127.0.0.1:${address.port}/ws`;
  });

  afterAll(async () => {
    for (const client of clients) client.close();
    if (userId) await db.query("DELETE FROM resource_gather_requests WHERE user_id=$1", [userId]);
    if (touchedNodeId) await db.query("DELETE FROM world_resource_nodes WHERE node_id=$1", [touchedNodeId]);
    await app.close();
    await db.end();
  });

  async function connectAndAuth(): Promise<{ client: WsClient; authOk: Msg; state: PublicPlayerState }> {
    const client = await WsClient.connect(wsUrl);
    clients.push(client);
    await client.waitFor((m) => m.type === "server_ready", 0, "server_ready");
    const from = client.mark();
    client.send({ type: "auth", token });
    const authOk = await client.waitFor((m) => m.type === "auth_ok" || m.type === "error", from, "auth_ok");
    if (authOk.type !== "auth_ok") throw new Error("AUTH_FAILED:" + String(authOk.code));
    const playerState = await client.waitFor((m) => m.type === "player_state", from, "player_state");
    return { client, authOk, state: playerState.state as PublicPlayerState };
  }

  async function subscribeAround(client: WsClient, spawn: { x: number; y: number }, requestId: string): Promise<ResourceNode[]> {
    const cx = Math.floor(spawn.x / CHUNK_SIZE);
    const cy = Math.floor(spawn.y / CHUNK_SIZE);
    const coords: Array<{ x: number; y: number }> = [];
    for (let y = cy - 1; y <= cy + 1; y += 1) for (let x = cx - 1; x <= cx + 1; x += 1) coords.push({ x, y });
    const from = client.mark();
    client.send({ type: "subscribe_chunks", requestId, chunks: coords });
    const resources: ResourceNode[] = [];
    const seen = new Set<string>();
    const frames: Msg[] = [];
    while (frames.length < coords.length) {
      const cursor = frames.length === 0 ? from : client.messages.indexOf(frames[frames.length - 1]) + 1;
      const frame = await client.waitFor((m) => m.type === "world_chunk" || m.type === "error", cursor, "world_chunk");
      if (frame.type === "error") throw new Error("SUBSCRIBE_FAILED:" + String(frame.code));
      frames.push(frame);
      expect(frame.requestId).toBe(requestId);
      const chunk = frame.chunk as { x: number; y: number; size: number; tiles: number[]; resources: ResourceNode[] };
      expect(chunk.size).toBe(CHUNK_SIZE);
      expect(chunk.tiles).toHaveLength(CHUNK_SIZE * CHUNK_SIZE);
      seen.add(`${chunk.x},${chunk.y}`);
      resources.push(...chunk.resources);
    }
    expect(seen.size).toBe(coords.length);
    return resources;
  }

  const timings = { moveMs: [] as number[], gatherMs: 0 };
  let spawn = { x: 0, y: 0 };
  let nodes: ResourceNode[] = [];
  let target: ResourceNode;
  let positionBeforeDisconnect = { x: 0, y: 0 };
  let inventoryAfterGather: Record<string, number> = {};
  let gatherAck: Msg;
  let session!: { client: WsClient };

  it("step 1: registers and logs in with the existing credential rules and returns a JWT", async () => {
    const register = await app.inject({ method: "POST", url: "/auth/register", payload: credentials });
    expect(register.statusCode).toBe(201);
    const registered = JSON.parse(register.body) as { accessToken: string; user: { id: string } };
    expect(registered.user.id).toMatch(/^[0-9a-f-]{36}$/);

    const badLogin = await app.inject({ method: "POST", url: "/auth/login", payload: { identifier: credentials.username, password: "wrong-password-123" } });
    expect(badLogin.statusCode).toBe(401);

    const login = await app.inject({ method: "POST", url: "/auth/login", payload: { identifier: credentials.username, password: credentials.password } });
    expect(login.statusCode).toBe(200);
    const body = JSON.parse(login.body) as { accessToken: string; user: { id: string } };
    expect(body.user.id).toBe(registered.user.id);
    expect(body.accessToken.split(".")).toHaveLength(3);
    userId = body.user.id;
    token = body.accessToken;
  });

  it("step 2: opens /ws, sends auth and receives auth_ok for the same user", async () => {
    const { client, authOk, state } = await connectAndAuth();
    session = { client };
    expect(authOk).toMatchObject({ type: "auth_ok", userId });
    expect(state.userId).toBe(userId);
    spawn = { x: state.x, y: state.y };
    expect(state.health).toBeGreaterThan(0);
  });

  it("step 3: subscribe_chunks returns the chunk(s) around spawn (documented finding: no gatherable node within gather range of the new-player spawn)", async () => {
    nodes = await subscribeAround(session.client, spawn, "m1-chunks-1");
    expect(nodes.length).toBeGreaterThan(0);
    const nearest = [...nodes].sort((a, b) => dist(a, spawn) - dist(b, spawn))[0];
    target = nearest;
    // FINDING (Codex P2 on PR #193, "provide a reachable resource for the default gather flow"):
    // createDefaultPlayer() spawns every new player at (0,0) (server/src/player.ts createDefaultPlayer), which is a Reef
    // tile, and the nearest generated resource is wood:-7:-2 (~7.3 tiles away) while the gather range is 2.5
    // (server/src/app.ts gather_resource handler). By design of the current server a brand-new player cannot gather
    // from spawn: they must first `move` ~5 tiles. This assertion pins that CURRENT behaviour; when the server provides
    // a reachable starter resource this assertion should be flipped to `<= GATHER_RANGE`.
    expect(spawn).toEqual({ x: 0, y: 0 });
    expect(dist(spawn, nearest)).toBeGreaterThan(GATHER_RANGE);
    expect(dist(spawn, nearest)).toBeLessThan(GATHER_RANGE * 4);
  });

  it("step 7a: gather from spawn (out of range) is rejected with RESOURCE_OUT_OF_RANGE and grants nothing", async () => {
    const reply = await session.client.request({ type: "gather_resource", requestId: "m1-oor-" + unique.slice(0, 8), resourceId: target.id }, ["resource_gathered"]);
    expect(reply).toMatchObject({ type: "error", code: "RESOURCE_OUT_OF_RANGE" });
    const row = await db.query<{ inventory: Record<string, number> }>("SELECT inventory FROM player_profiles WHERE user_id=$1", [userId]);
    expect(row.rows[0]?.inventory["resource.wood"]).toBeUndefined();
  });

  it("step 4: move sends intent only and the server returns the authoritative position", async () => {
    const { client } = session;
    let sequence = 1;
    let last = spawn;
    for (let i = 0; i < 200 && dist(last, target) > GATHER_RANGE - 0.5; i += 1) {
      await sleep(60); // serverDt is derived from server clocks (max 0.1 s per packet); client time is never trusted
      const len = dist(last, target) || 1;
      const startedAt = performance.now();
      const reply = await client.request({ type: "move", dx: (target.x - last.x) / len, dy: (target.y - last.y) / len, sequence: sequence++ }, ["player_state"]);
      timings.moveMs.push(performance.now() - startedAt);
      expect(reply.type).toBe("player_state");
      const next = (reply.state as PublicPlayerState);
      // authoritative step is bounded by speed (<= 4/s land) * server dt (<= 0.1 s) regardless of what the client sent
      expect(dist(last, next)).toBeLessThanOrEqual(0.4 + 1e-9);
      expect(dist(last, next)).toBeGreaterThan(0);
      last = { x: next.x, y: next.y };
    }
    expect(dist(last, spawn)).toBeGreaterThan(0);
    expect(dist(last, target)).toBeLessThanOrEqual(GATHER_RANGE - 0.5 + 0.4);
    expect(dist(last, target)).toBeLessThanOrEqual(GATHER_RANGE);

    // a client trying to teleport with an out-of-bounds vector is rejected by the parser; position is unchanged
    const before = client.mark();
    client.send({ type: "move", dx: 1000, dy: 1000, sequence });
    const rejected = await client.waitFor((m) => m.type === "error", before, "error for oversized move vector");
    expect(rejected).toMatchObject({ code: "INVALID_MESSAGE" });
    positionBeforeDisconnect = last;
    console.log(`[m1-loop] local wall-clock (not an SLO): move round trip median ${median(timings.moveMs).toFixed(1)} ms over ${timings.moveMs.length} moves`);
  });

  it("step 5: gather_resource returns an authoritative ACK + inventory change, and a replayed requestId does not double-grant", async () => {
    const { client } = session;
    const itemId = target.type === "wood" ? "resource.wood" : target.type === "stone" ? "resource.stone" : "resource.herb";
    const quantity = target.type === "herb" ? 1 : 2;
    const requestId = "m1-gather-" + unique.slice(0, 12);
    touchedNodeId = target.id;

    const startedAt = performance.now();
    const ack = await client.request({ type: "gather_resource", requestId, resourceId: target.id }, ["resource_gathered"]);
    timings.gatherMs = performance.now() - startedAt;
    expect(ack).toMatchObject({ type: "resource_gathered", requestId, resourceId: target.id, itemId, quantity });
    expect(typeof ack.transactionId).toBe("string");
    expect(typeof ack.respawnsAt).toBe("string");
    gatherAck = ack;
    const state = ack.state as PublicPlayerState;
    expect(state.inventory[itemId]).toBe(quantity);
    inventoryAfterGather = { ...state.inventory };

    const persisted = await db.query<{ inventory: Record<string, number> }>("SELECT inventory FROM player_profiles WHERE user_id=$1", [userId]);
    expect(persisted.rows[0]?.inventory[itemId]).toBe(quantity);

    // The node is now depleted for everybody.
    const chunkResponse = await app.inject({ method: "GET", url: `/world/chunks/${Math.floor(target.x / CHUNK_SIZE)}/${Math.floor(target.y / CHUNK_SIZE)}` });
    expect((JSON.parse(chunkResponse.body) as { resources: ResourceNode[] }).resources.some((r) => r.id === target.id)).toBe(false);

    // Replay of the same requestId + same intent: server answers idempotently, no second grant.
    const replay = await client.request({ type: "gather_resource", requestId, resourceId: target.id }, ["resource_gathered"]);
    expect(replay).toMatchObject({ type: "resource_gathered", requestId, resourceId: target.id, itemId, quantity });
    expect(replay.transactionId).toBe(gatherAck.transactionId);
    expect((replay.state as PublicPlayerState).inventory[itemId]).toBe(quantity);
    const afterReplay = await db.query<{ inventory: Record<string, number> }>("SELECT inventory FROM player_profiles WHERE user_id=$1", [userId]);
    expect(afterReplay.rows[0]?.inventory[itemId]).toBe(quantity);
    const requests = await db.query("SELECT 1 FROM resource_gather_requests WHERE user_id=$1 AND request_id=$2", [userId, requestId]);
    expect(requests.rowCount).toBe(1);

    // Same requestId reused for a different intent is a conflict, not a second grant.
    const other = [...nodes].find((n) => n.id !== target.id)!;
    const conflict = await client.request({ type: "gather_resource", requestId, resourceId: other.id }, ["resource_gathered"]);
    // The in-memory economy replay layer (app.ts runEconomyRequest) answers a reused requestId with a
    // different intent with INVALID_MESSAGE before the range check or any DB work. Pin that exact code,
    // and prove it is the conflict path and not a range rejection: the same far node with a FRESH
    // requestId is rejected with RESOURCE_OUT_OF_RANGE instead.
    expect(conflict).toMatchObject({ type: "error", code: "INVALID_MESSAGE" });
    const freshFar = await client.request({ type: "gather_resource", requestId: `${requestId}-far`, resourceId: other.id }, ["resource_gathered"]);
    expect(freshFar).toMatchObject({ type: "error", code: "RESOURCE_OUT_OF_RANGE" });
    const afterConflict = await db.query<{ inventory: Record<string, number> }>("SELECT inventory FROM player_profiles WHERE user_id=$1", [userId]);
    expect(afterConflict.rows[0]?.inventory[itemId]).toBe(quantity);
    console.log(`[m1-loop] local wall-clock (not an SLO): gather round trip ${timings.gatherMs.toFixed(1)} ms`);
  });

  it("step 6: after disconnect and reconnect with the same JWT, position and inventory are restored from PostgreSQL", async () => {
    session.client.close();
    await session.client.waitClosed();

    const { client, state } = await connectAndAuth();
    session = { client };
    // Server memory was unloaded on disconnect, so these values are the persisted ones, not client memory.
    expect(state.x).toBe(positionBeforeDisconnect.x);
    expect(state.y).toBe(positionBeforeDisconnect.y);
    expect(state.inventory).toEqual(inventoryAfterGather);
    const row = await db.query<{ x: number; y: number; inventory: Record<string, number> }>("SELECT x,y,inventory FROM player_profiles WHERE user_id=$1", [userId]);
    expect(row.rows[0]?.x).toBe(positionBeforeDisconnect.x);
    expect(row.rows[0]?.y).toBe(positionBeforeDisconnect.y);
    expect(row.rows[0]?.inventory).toEqual(inventoryAfterGather);

    // Re-subscribe: the gathered node is still depleted and the chunk set is delivered again.
    const resources = await subscribeAround(client, { x: state.x, y: state.y }, "m1-chunks-2");
    expect(resources.some((r) => r.id === target.id)).toBe(false);
  });

  it("step 7b: an unauthenticated socket cannot send gameplay messages", async () => {
    const client = await WsClient.connect(wsUrl);
    clients.push(client);
    await client.waitFor((m) => m.type === "server_ready", 0, "server_ready");
    const probes: Array<Record<string, unknown>> = [
      { type: "move", dx: 1, dy: 0, sequence: 1 },
      { type: "gather_resource", requestId: "m1-unauth", resourceId: target.id },
      { type: "subscribe_chunks", requestId: "m1-unauth-chunks", chunks: [{ x: 0, y: 0 }] },
    ];
    for (const probe of probes) {
      const reply = await client.request(probe, ["player_state", "resource_gathered", "world_chunk"]);
      expect(reply, String(probe.type)).toMatchObject({ type: "error", code: "AUTH_REQUIRED" });
    }
    expect(client.messages.some((m) => m.type === "world_chunk" || m.type === "player_state" || m.type === "resource_gathered")).toBe(false);
    // An invalid token is rejected and the socket is closed.
    const bad = await WsClient.connect(wsUrl);
    clients.push(bad);
    bad.send({ type: "auth", token: "not-a-jwt" });
    await bad.waitFor((m) => m.type === "error" && m.code === "INVALID_TOKEN", 0, "INVALID_TOKEN");
    expect(await bad.waitClosed()).toBe(1008);
    client.close();
  });

  it("step 7c: oversized payloads are rejected (over-length ids at the parser, over-size frames at the transport)", async () => {
    const { client } = session;
    const parserReply = await client.request({ type: "gather_resource", requestId: "m1-long-id", resourceId: "wood:" + "9".repeat(200) }, ["resource_gathered"]);
    expect(parserReply).toMatchObject({ type: "error", code: "INVALID_MESSAGE" });

    const huge = await WsClient.connect(wsUrl);
    clients.push(huge);
    huge.send(JSON.stringify({ type: "ping", pad: "x".repeat(70 * 1024) })); // > websocketMaxPayloadBytes (64 KiB)
    expect(await huge.waitClosed()).toBe(1009);
    expect(huge.messages.some((m) => m.type === "pong")).toBe(false);

    // The authenticated session is unaffected.
    const pong = await client.request({ type: "ping" }, ["pong"]);
    expect(pong.type).toBe("pong");
  });
});

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
}

