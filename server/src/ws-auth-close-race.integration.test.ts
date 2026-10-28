import { randomUUID } from "node:crypto";
import { describe, expect, it, vi } from "vitest";
import { WebSocket } from "ws";
import { AntiCheatService } from "./anti-cheat.js";
import { MemoryAntiCheatStateStore } from "./anti-cheat-store.js";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function nextMessage(socket: WebSocket, type: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("TIMEOUT_" + type)), 3_000);
    const onMessage = (raw: Buffer) => {
      if ((JSON.parse(raw.toString()) as { type?: string }).type !== type) return;
      clearTimeout(timer);
      socket.off("message", onMessage);
      resolve();
    };
    socket.on("message", onMessage);
  });
}

describe("websocket authentication racing a close", () => {
  it("does not register an anti-cheat lease when the socket closes during authentication", async () => {
    const db = createDbPool();
    // Hold the player-profile read that authentication performs, so the close can land mid-auth.
    let gateEnabled = false;
    let releaseGate: () => void = () => undefined;
    let gateReached: () => void = () => undefined;
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
    let socket: WebSocket | undefined;
    try {
      const register = await app.inject({
        method: "POST",
        url: "/auth/register",
        payload: { username: `closerace_${unique}`, email: `closerace_${unique}@example.com`, password: "Correct-Horse-Battery-9" },
      });
      if (register.statusCode !== 201) throw new Error("REGISTER_" + register.statusCode + " " + register.body);
      expect(register.statusCode).toBe(201);
      const body = JSON.parse(register.body) as { accessToken: string };

      await app.listen({ host: "127.0.0.1", port: 0 });
      const address = app.server.address();
      if (address === null || typeof address === "string") throw new Error("TEST_SERVER_NOT_LISTENING");
      socket = new WebSocket(`ws://127.0.0.1:${address.port}/ws`);
      await nextMessage(socket, "server_ready");

      gateEnabled = true;
      socket.send(JSON.stringify({ type: "auth", token: body.accessToken }));
      await reached;
      socket.close();
      // Give the server time to process the close while authentication is still blocked.
      await sleep(200);
      releaseGate();
      await sleep(500);

      expect(connectSocket).not.toHaveBeenCalled();
    } finally {
      socket?.close();
      await app.close();
      await db.end();
    }
  });
});
