import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";

// A REST reward (here a daily objective claim) changes gold for a player who is in the world.
// The server must push the refreshed player_state over the player's WebSocket at once, so the
// HUD does not stay stale until the player next moves.
type Msg = Record<string, unknown> & { type: string };

describe("REST reward pushes player_state to the in-world player", () => {
  const db = createDbPool();
  let app: Awaited<ReturnType<typeof buildApp>>;
  let base = "";
  beforeAll(async () => {
    app = await buildApp({ db });
    await app.listen({ host: "127.0.0.1", port: 0 });
    const address = app.server.address();
    if (!address || typeof address === "string") throw new Error("no address");
    base = `127.0.0.1:${address.port}`;
  });
  afterAll(async () => { await app.close(); await db.end(); });

  it("sends player_state with the new gold right after a daily objective claim", async () => {
    const unique = randomUUID().replace(/-/g, "").slice(0, 20);
    const reg = await app.inject({ method: "POST", url: "/auth/register", payload: { username: `rp_${unique}`, email: `rp_${unique}@example.com`, password: "Correct-Horse-Battery-9" } });
    expect(reg.statusCode).toBe(201);
    const { user, accessToken } = JSON.parse(reg.body) as { user: { id: string }; accessToken: string };

    const messages: Msg[] = [];
    const socket = new WebSocket(`ws://${base}/ws`);
    socket.on("message", (raw: Buffer) => messages.push(JSON.parse(raw.toString()) as Msg));
    await new Promise<void>((resolve, reject) => { socket.once("open", () => resolve()); socket.once("error", reject); });
    const waitFor = async (predicate: (m: Msg) => boolean, from: number, label: string): Promise<Msg> => {
      const deadline = Date.now() + 5_000;
      for (;;) {
        const hit = messages.slice(from).find(predicate);
        if (hit) return hit;
        if (Date.now() > deadline) throw new Error(`TIMEOUT ${label}: ${JSON.stringify(messages.slice(from).map((m) => m.type))}`);
        await new Promise((r) => setTimeout(r, 5));
      }
    };
    try {
      socket.send(JSON.stringify({ type: "auth", token: accessToken }));
      const first = await waitFor((m) => m.type === "player_state", 0, "initial player_state");
      const goldBefore = BigInt(String((first.state as { gold: string }).gold));

      await db.query(
        "INSERT INTO resource_gather_requests(user_id,request_id,fingerprint,node_id,item_id,quantity,respawns_at) VALUES($1,$2,'seed','seed-node','resource.wood',10,now())",
        [user.id, randomUUID().slice(0, 32)],
      );
      const mark = messages.length;
      const claim = await app.inject({ method: "POST", url: "/daily-objectives/claim", headers: { authorization: `Bearer ${accessToken}` }, payload: { objectiveId: "gather.wood" } });
      expect(claim.statusCode).toBe(200);
      const pushed = await waitFor((m) => m.type === "player_state", mark, "pushed player_state");
      expect(BigInt(String((pushed.state as { gold: string }).gold))).toBe(goldBefore + 50n);
    } finally {
      socket.close();
    }
  });
});
