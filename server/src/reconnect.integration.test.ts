import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import type { PublicPlayerState } from "./player.js";
import type { ResourceNode } from "./world.js";

/**
 * Reconnect durability: a player whose socket dies ABRUPTLY (terminate, no close frame) mid-session,
 * then logs in again for a refreshed JWT and reconnects, keeps authoritative position and inventory
 * from PostgreSQL, and a gather requestId replayed AFTER the reconnect is answered idempotently
 * (no second grant). m1-loop covers a graceful close with the same JWT and a same-connection replay;
 * this file covers the abrupt-drop + re-login + cross-connection replay gap. Real app, real PostgreSQL.
 */

const GATHER_RANGE = 2.5;
const WAIT_MS = 5_000;
const CHUNK_SIZE = 32;
const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));
type Msg = Record<string, unknown> & { type: string };

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
  async waitFor(predicate: (m: Msg) => boolean, from = 0, label = "message"): Promise<Msg> {
    const deadline = Date.now() + WAIT_MS;
    let cursor = from;
    for (;;) {
      while (cursor < this.messages.length) {
        const candidate = this.messages[cursor++];
        if (predicate(candidate)) return candidate;
      }
      if (Date.now() > deadline) throw new Error(`TIMEOUT waiting for ${label}; saw ${JSON.stringify(this.messages.slice(from).map((m) => m.type))}`);
      await sleep(5);
    }
  }
  async request(message: unknown, types: string[]): Promise<Msg> {
    const from = this.messages.length;
    this.socket.send(JSON.stringify(message));
    return this.waitFor((m) => types.includes(m.type) || m.type === "error", from, types.join("|"));
  }
  async waitClosed(): Promise<void> {
    const deadline = Date.now() + WAIT_MS;
    while (this.closeCode === undefined) {
      if (Date.now() > deadline) throw new Error("TIMEOUT waiting for close");
      await sleep(5);
    }
  }
}

const dist = (a: { x: number; y: number }, b: { x: number; y: number }): number => Math.hypot(a.x - b.x, a.y - b.y);

describe("reconnect durability after an abrupt socket drop (real server + PostgreSQL)", () => {
  const db = createDbPool();
  let app: Awaited<ReturnType<typeof buildApp>>;
  let wsUrl = "";
  const clients: WsClient[] = [];
  const unique = randomUUID().replace(/-/g, "").slice(0, 20);
  const credentials = { username: `rc_${unique}`, email: `rc_${unique}@example.com`, password: "Correct-Horse-Battery-9" };
  let userId = "";
  let touchedNodeId: string | undefined;

  beforeAll(async () => {
    app = await buildApp({ db });
    await app.listen({ host: "127.0.0.1", port: 0 });
    const address = app.server.address();
    if (address === null || typeof address === "string") throw new Error("TEST_SERVER_NOT_LISTENING");
    wsUrl = `ws://127.0.0.1:${address.port}/ws`;
  });

  afterAll(async () => {
    for (const client of clients) client.socket.terminate();
    await app.close();
    if (userId) await db.query("DELETE FROM resource_gather_requests WHERE user_id=$1", [userId]);
    if (touchedNodeId) await db.query("DELETE FROM world_resource_nodes WHERE node_id=$1", [touchedNodeId]);
    await db.end();
  });

  async function connectAndAuth(token: string): Promise<{ client: WsClient; state: PublicPlayerState }> {
    const client = await WsClient.connect(wsUrl);
    clients.push(client);
    await client.waitFor((m) => m.type === "server_ready", 0, "server_ready");
    client.socket.send(JSON.stringify({ type: "auth", token }));
    const authOk = await client.waitFor((m) => m.type === "auth_ok" || m.type === "error", 0, "auth_ok");
    if (authOk.type !== "auth_ok") throw new Error("AUTH_FAILED:" + String(authOk.code));
    expect(authOk.userId).toBe(userId);
    const playerState = await client.waitFor((m) => m.type === "player_state", 0, "player_state");
    return { client, state: playerState.state as PublicPlayerState };
  }

  async function login(): Promise<string> {
    const res = await app.inject({ method: "POST", url: "/auth/login", payload: { identifier: credentials.username, password: credentials.password } });
    expect(res.statusCode).toBe(200);
    return (JSON.parse(res.body) as { accessToken: string }).accessToken;
  }

  async function discoverNodes(client: WsClient, spawn: { x: number; y: number }): Promise<ResourceNode[]> {
    const cx = Math.floor(spawn.x / CHUNK_SIZE);
    const cy = Math.floor(spawn.y / CHUNK_SIZE);
    const coords: Array<{ x: number; y: number }> = [];
    for (let y = cy - 1; y <= cy + 1; y += 1) for (let x = cx - 1; x <= cx + 1; x += 1) coords.push({ x, y });
    const from = client.messages.length;
    client.socket.send(JSON.stringify({ type: "subscribe_chunks", requestId: "rc-chunks", chunks: coords }));
    const nodes: ResourceNode[] = [];
    let cursor = from;
    for (let received = 0; received < coords.length; received += 1) {
      const frame = await client.waitFor((m) => m.type === "world_chunk" || m.type === "error", cursor, "world_chunk");
      if (frame.type === "error") throw new Error("SUBSCRIBE_FAILED:" + String(frame.code));
      cursor = client.messages.indexOf(frame) + 1;
      nodes.push(...(frame.chunk as { resources: ResourceNode[] }).resources);
    }
    return nodes;
  }

  it("keeps position and inventory across abrupt drop + re-login, and a replayed gather requestId does not double-grant", async () => {
    const register = await app.inject({ method: "POST", url: "/auth/register", payload: credentials });
    expect(register.statusCode).toBe(201);
    userId = (JSON.parse(register.body) as { user: { id: string } }).user.id;
    const firstToken = await login();

    const { client: first, state: spawn } = await connectAndAuth(firstToken);
    const nodes = await discoverNodes(first, spawn);
    expect(nodes.length).toBeGreaterThan(1);
    // Every new player spawns on the same tile, and m1-loop.integration.test.ts
    // depletes the node nearest to it. Vitest runs files in parallel against
    // one database, so take the second-nearest node to avoid racing m1-loop.
    const target = [...nodes].sort((a, b) => dist(a, spawn) - dist(b, spawn))[1];
    touchedNodeId = target.id;

    // Move (intent only) until within gather range.
    let sequence = 1;
    let last = { x: spawn.x, y: spawn.y };
    for (let i = 0; i < 200 && dist(last, target) > GATHER_RANGE - 0.5; i += 1) {
      await sleep(60); // server dt comes from server clocks, never the client's
      const len = dist(last, target) || 1;
      const reply = await first.request({ type: "move", dx: (target.x - last.x) / len, dy: (target.y - last.y) / len, sequence: sequence++ }, ["player_state"]);
      expect(reply.type).toBe("player_state");
      const next = reply.state as PublicPlayerState;
      last = { x: next.x, y: next.y };
    }
    expect(dist(last, spawn)).toBeGreaterThan(0);
    expect(dist(last, target)).toBeLessThanOrEqual(GATHER_RANGE);

    const itemId = target.type === "wood" ? "resource.wood" : target.type === "stone" ? "resource.stone" : "resource.herb";
    const requestId = "rc-gather-" + unique.slice(0, 12);
    const ack = await first.request({ type: "gather_resource", requestId, resourceId: target.id }, ["resource_gathered"]);
    expect(ack).toMatchObject({ type: "resource_gathered", requestId, resourceId: target.id, itemId });
    const quantity = ack.quantity as number;
    expect(quantity).toBeGreaterThan(0);
    const stateAfterGather = ack.state as PublicPlayerState;
    expect(stateAfterGather.inventory[itemId]).toBe(quantity);
    const inventoryBefore = { ...stateAfterGather.inventory };
    const positionBefore = { x: stateAfterGather.x, y: stateAfterGather.y };

    // Abrupt kill: no close frame, the server only sees the TCP connection die.
    first.socket.terminate();
    await first.waitClosed();
    // Let the server's disconnect handler persist and unload the session.
    await sleep(300);

    // Refreshed JWT via a new login, then reconnect and re-auth.
    const refreshedToken = await login();
    const { client: second, state } = await connectAndAuth(refreshedToken);
    expect(state.x).toBe(positionBefore.x);
    expect(state.y).toBe(positionBefore.y);
    expect(state.inventory).toEqual(inventoryBefore);
    const persisted = await db.query<{ x: number; y: number; inventory: Record<string, number> }>("SELECT x,y,inventory FROM player_profiles WHERE user_id=$1", [userId]);
    expect(persisted.rows[0]?.x).toBe(positionBefore.x);
    expect(persisted.rows[0]?.y).toBe(positionBefore.y);
    expect(persisted.rows[0]?.inventory).toEqual(inventoryBefore);

    // Replay the SAME requestId on the NEW connection: idempotent answer, no second grant.
    const replay = await second.request({ type: "gather_resource", requestId, resourceId: target.id }, ["resource_gathered"]);
    expect(replay).toMatchObject({ type: "resource_gathered", requestId, resourceId: target.id, itemId, quantity });
    expect(replay.transactionId).toBe(ack.transactionId);
    expect((replay.state as PublicPlayerState).inventory[itemId]).toBe(quantity);
    const afterReplay = await db.query<{ inventory: Record<string, number> }>("SELECT inventory FROM player_profiles WHERE user_id=$1", [userId]);
    expect(afterReplay.rows[0]?.inventory[itemId]).toBe(quantity);
    const ledger = await db.query("SELECT 1 FROM resource_gather_requests WHERE user_id=$1 AND request_id=$2", [userId, requestId]);
    expect(ledger.rowCount).toBe(1);

    // A FRESH requestId for the already-depleted node must not grant either.
    const fresh = await second.request({ type: "gather_resource", requestId: `${requestId}-b`, resourceId: target.id }, ["resource_gathered"]);
    expect(fresh.type).toBe("error");
    const afterFresh = await db.query<{ inventory: Record<string, number> }>("SELECT inventory FROM player_profiles WHERE user_id=$1", [userId]);
    expect(afterFresh.rows[0]?.inventory[itemId]).toBe(quantity);
  }, 60_000);
});
