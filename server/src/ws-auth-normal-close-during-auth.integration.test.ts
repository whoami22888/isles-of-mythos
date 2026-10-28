import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { AntiCheatService } from "./anti-cheat.js";
import { MemoryAntiCheatStateStore } from "./anti-cheat-store.js";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";

type Message = Record<string, unknown>;

function connect(url: string): Promise<{ socket: WebSocket; inbox: Message[] }> {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    const inbox: Message[] = [];
    socket.on("message", (raw: Buffer) => inbox.push(JSON.parse(raw.toString()) as Message));
    socket.once("error", reject);
    socket.once("open", () => resolve({ socket, inbox }));
  });
}

async function waitForMessage(
  inbox: Message[],
  predicate: (message: Message) => boolean,
  label: string,
  skip = 0,
): Promise<Message> {
  const deadline = Date.now() + 3_000;
  for (;;) {
    const found = inbox.filter(predicate)[skip];
    if (found) return found;
    if (Date.now() > deadline) throw new Error("TIMEOUT_" + label);
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

describe("normal close of an authenticated socket during another socket's authentication", () => {
  it("keeps the in-flight second socket's state live when the first socket closes normally mid-load", async () => {
    const db = createDbPool();
    // Hold the second socket at its first base read: it has already passed the pending-unload check and is
    // in flight while the first socket is still registered. Only the first base read is held.
    let gateArmed = false;
    let gateReached: () => void = () => undefined;
    let releaseGate: () => void = () => undefined;
    const reached = new Promise<void>((resolve) => { gateReached = resolve; });
    const originalQuery = db.query.bind(db) as (...args: unknown[]) => Promise<unknown>;
    (db as unknown as { query: unknown }).query = async (...args: unknown[]) => {
      const text = typeof args[0] === "string" ? args[0] : "";
      if (gateArmed && /FROM player_bases WHERE owner_user_id=\$1/.test(text)) {
        gateArmed = false;
        gateReached();
        await new Promise<void>((resolve) => { releaseGate = resolve; });
      }
      return originalQuery(...args);
    };

    const antiCheat = new AntiCheatService({ store: new MemoryAntiCheatStateStore() });
    const app = await buildApp({ db, antiCheat });
    const unique = randomUUID().replace(/-/g, "").slice(0, 20);
    const sockets: WebSocket[] = [];
    try {
      const register = await app.inject({
        method: "POST",
        url: "/auth/register",
        payload: { username: `normclose_${unique}`, email: `normclose_${unique}@example.com`, password: "Correct-Horse-Battery-9" },
      });
      if (register.statusCode !== 201) throw new Error("REGISTER_" + register.statusCode);
      const body = JSON.parse(register.body) as { accessToken: string };

      await app.listen({ host: "127.0.0.1", port: 0 });
      const address = app.server.address();
      if (address === null || typeof address === "string") throw new Error("TEST_SERVER_NOT_LISTENING");
      const url = `ws://127.0.0.1:${address.port}/ws`;

      // Socket A authenticates fully and is registered.
      const a = await connect(url);
      sockets.push(a.socket);
      await waitForMessage(a.inbox, (m) => m.type === "server_ready", "a_ready");
      a.socket.send(JSON.stringify({ type: "auth", token: body.accessToken }));
      await waitForMessage(a.inbox, (m) => m.type === "auth_ok", "a_auth");

      // Socket B starts authenticating for the same account and is held in flight.
      const b = await connect(url);
      sockets.push(b.socket);
      await waitForMessage(b.inbox, (m) => m.type === "server_ready", "b_ready");
      gateArmed = true;
      b.socket.send(JSON.stringify({ type: "auth", token: body.accessToken }));
      await reached;

      // A closes normally while B is in flight. Its normal close schedules the unload of the shared account state.
      a.socket.close();
      await new Promise((resolve) => setTimeout(resolve, 500));

      // Let B finish loading and register.
      releaseGate();
      await waitForMessage(b.inbox, (m) => m.type === "auth_ok", "b_auth");

      // B must still have live authoritative state after A's unload: an accepted move answers with a new
      // player_state and no error. Wait for that event, not for a fixed delay.
      const stateCountBeforeMove = b.inbox.filter((m) => m.type === "player_state").length;
      b.socket.send(JSON.stringify({ type: "move", dx: 1, dy: 0, dt: 0.25, sequence: 1 }));
      await waitForMessage(b.inbox, (m) => m.type === "player_state", "b_move_state_after", stateCountBeforeMove);
      expect(b.inbox.some((m) => m.type === "error")).toBe(false);
    } finally {
      for (const socket of sockets) socket.close();
      await app.close();
      await db.end();
    }
  });
});
