import { describe, expect, it } from "vitest";
import type { Pool } from "pg";
import { WebSocket } from "ws";
import { buildApp } from "./app.js";

// MYTHOS-NET-02: a slow handler must not let a socket build an unbounded
// message backlog. A stalled database holds the first (auth) message in the
// per-socket queue, so every later frame queues behind it.

function stalledPool(): { pool: Pool; release: () => void } {
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  const stall = async (): Promise<never> => {
    await gate;
    throw new Error("released");
  };
  const pool = {
    query: stall,
    connect: stall,
    on: () => pool,
    end: () => Promise.resolve(),
  } as unknown as Pool;
  return { pool, release };
}

async function openStalledSocket(): Promise<{
  app: Awaited<ReturnType<typeof buildApp>>;
  socket: WebSocket;
  release: () => void;
  errors: string[];
  closeInfo: { code?: number; reason?: string };
}> {
  const { pool, release } = stalledPool();
  const app = await buildApp({ db: pool });
  await app.listen({ host: "127.0.0.1", port: 0 });
  const address = app.server.address();
  if (address === null || typeof address === "string") throw new Error("Test server has no TCP address");
  const socket = new WebSocket(`ws://127.0.0.1:${address.port}/ws`);
  const errors: string[] = [];
  const closeInfo: { code?: number; reason?: string } = {};
  socket.on("message", (raw) => {
    const text = Buffer.isBuffer(raw) ? raw.toString("utf8") : Buffer.concat(Array.isArray(raw) ? raw : [Buffer.from(raw)]).toString("utf8");
    const message = JSON.parse(text) as { type?: string; code?: string };
    if (message.type === "error" && typeof message.code === "string") errors.push(message.code);
  });
  socket.on("close", (code, reason) => {
    closeInfo.code = code;
    closeInfo.reason = reason.toString();
  });
  await new Promise<void>((resolve, reject) => {
    socket.once("open", () => resolve());
    socket.once("error", reject);
  });
  return { app, socket, release, errors, closeInfo };
}

async function waitFor(condition: () => boolean, timeoutMs: number): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (!condition()) {
    if (Date.now() > deadline) return false;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  return true;
}

describe("WebSocket message backlog cap", () => {
  it("rejects frames beyond the queue depth with RATE_LIMITED and keeps the socket open", async () => {
    const { app, socket, release, errors, closeInfo } = await openStalledSocket();
    try {
      const token = app.jwt.sign({ sub: "backlog-user-1", username: "backlog1" });
      socket.send(JSON.stringify({ type: "auth", token }));
      // Depth 64 = the stalled auth frame plus 63 accepted pings; 80 pings => 17 rejected.
      for (let i = 0; i < 80; i += 1) socket.send(JSON.stringify({ type: "ping" }));
      expect(await waitFor(() => errors.length >= 17, 3000)).toBe(true);
      await new Promise((resolve) => setTimeout(resolve, 150));
      expect(errors.filter((code) => code === "RATE_LIMITED")).toHaveLength(17);
      expect(closeInfo.code).toBeUndefined();
    } finally {
      release();
      socket.close();
      await app.close();
    }
  });

  // 1013 "Try Again Later", not 1008: the Godot client never reconnects after a
  // 1008 (rejected credentials), so 1008 would permanently drop a legitimate
  // player whose requests only queued behind a slow database.
  it("closes the socket with 1013 (retryable) after sustained backlog overflow", async () => {
    const { app, socket, release, errors, closeInfo } = await openStalledSocket();
    try {
      const token = app.jwt.sign({ sub: "backlog-user-2", username: "backlog2" });
      socket.send(JSON.stringify({ type: "auth", token }));
      // 110 pings => 47 over the cap; the 32nd overflow strike closes the socket.
      for (let i = 0; i < 110; i += 1) socket.send(JSON.stringify({ type: "ping" }));
      expect(await waitFor(() => closeInfo.code !== undefined, 3000)).toBe(true);
      expect(closeInfo.code).toBe(1013);
      expect(closeInfo.reason).toBe("message_backlog");
      expect(errors.filter((code) => code === "RATE_LIMITED")).toHaveLength(32);
    } finally {
      release();
      socket.close();
      await app.close();
    }
  });
});
