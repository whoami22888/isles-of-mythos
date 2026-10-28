import { randomUUID } from "node:crypto";
import { describe, expect, it, vi } from "vitest";
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

async function waitForMessage(inbox: Message[], predicate: (message: Message) => boolean, label: string): Promise<Message> {
  const deadline = Date.now() + 3_000;
  for (;;) {
    const found = inbox.find(predicate);
    if (found) return found;
    if (Date.now() > deadline) throw new Error("TIMEOUT_" + label);
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

describe("two sockets for one account around an early-closed authentication", () => {
  it("keeps the second socket's authoritative state available after the first socket's cleanup", async () => {
    const db = createDbPool();
    // Hold the first profile read of the first authentication, so its socket can close mid-auth.
    let gateEnabled = false;
    let gateReached: () => void = () => undefined;
    let releaseGate: () => void = () => undefined;
    const reached = new Promise<void>((resolve) => { gateReached = resolve; });
    const originalQuery = db.query.bind(db) as (...args: unknown[]) => Promise<unknown>;
    (db as unknown as { query: unknown }).query = async (...args: unknown[]) => {
      const text = typeof args[0] === "string" ? args[0] : "";
      if (gateEnabled && /FROM player_profiles WHERE user_id = \$1/.test(text)) {
        gateEnabled = false;
        gateReached();
        await new Promise<void>((resolve) => { releaseGate = resolve; });
      }
      return originalQuery(...args);
    };

    const antiCheat = new AntiCheatService({ store: new MemoryAntiCheatStateStore() });
    const connectSocket = vi.spyOn(antiCheat, "connectSocket");
    const app = await buildApp({ db, antiCheat });
    const unique = randomUUID().replace(/-/g, "").slice(0, 20);
    const sockets: WebSocket[] = [];
    try {
      const register = await app.inject({
        method: "POST",
        url: "/auth/register",
        payload: { username: `twosock_${unique}`, email: `twosock_${unique}@example.com`, password: "Correct-Horse-Battery-9" },
      });
      if (register.statusCode !== 201) throw new Error("REGISTER_" + register.statusCode);
      const body = JSON.parse(register.body) as { accessToken: string };

      await app.listen({ host: "127.0.0.1", port: 0 });
      const address = app.server.address();
      if (address === null || typeof address === "string") throw new Error("TEST_SERVER_NOT_LISTENING");
      const url = `ws://127.0.0.1:${address.port}/ws`;

      // Socket A starts authenticating and is held mid-load, then closes.
      const a = await connect(url);
      sockets.push(a.socket);
      await waitForMessage(a.inbox, (m) => m.type === "server_ready", "a_ready");
      gateEnabled = true;
      a.socket.send(JSON.stringify({ type: "auth", token: body.accessToken }));
      await reached;
      a.socket.close();
      await new Promise((resolve) => setTimeout(resolve, 100));
      releaseGate();

      // Socket B authenticates for the same account right after A's cleanup begins.
      const b = await connect(url);
      sockets.push(b.socket);
      await waitForMessage(b.inbox, (m) => m.type === "server_ready", "b_ready");
      b.socket.send(JSON.stringify({ type: "auth", token: body.accessToken }));
      await waitForMessage(b.inbox, (m) => m.type === "auth_ok", "b_auth");

      // B must be live with its authoritative state still in memory.
      b.socket.send(JSON.stringify({ type: "move", dx: 1, dy: 0, dt: 0.25, sequence: 1 }));
      await new Promise((resolve) => setTimeout(resolve, 300));
      expect(b.inbox.some((m) => m.type === "error" && m.code === "AUTH_REQUIRED")).toBe(false);
      expect(connectSocket).toHaveBeenCalledTimes(1);
    } finally {
      for (const socket of sockets) socket.close();
      await app.close();
      await db.end();
    }
  });
});
