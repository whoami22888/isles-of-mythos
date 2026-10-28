import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { generateChunk, type WorldChunk } from "./world.js";

/**
 * W-015: measure actual outbound Fastify /ws world_chunk UTF-8 frame bytes.
 * The Godot adapter rejects packets larger than 65,536 bytes.
 * This runs against the disposable, migrated integration-test database.
 */
const GODOT_MAX_PACKET_BYTES = 65_536;
const WAIT_MS = 5_000;

type Coordinate = { x: number; y: number };
type ReceivedFrame = { raw: string; utf8Bytes: number; binary: boolean };
type ChunkReply = { type: "world_chunk"; requestId: string; chunk: WorldChunk };

function isChunkReply(value: unknown): value is ChunkReply {
  if (typeof value !== "object" || value === null) return false;
  const record = value as Record<string, unknown>;
  return record.type === "world_chunk" && typeof record.requestId === "string"
    && typeof record.chunk === "object" && record.chunk !== null;
}

function selectDenseGeneratedChunk(): { coordinate: Coordinate; resourceCount: number } {
  let best = { coordinate: { x: 0, y: 0 }, resourceCount: -1 };
  // Deterministic, naturally generated high-density candidate, not synthetic payload inflation.
  for (let y = -12; y <= 12; y += 1) {
    for (let x = -12; x <= 12; x += 1) {
      if (Math.abs(x) <= 1 && Math.abs(y) <= 1) continue;
      const chunk = generateChunk(x, y);
      if (chunk.resources.length > best.resourceCount) {
        best = { coordinate: { x, y }, resourceCount: chunk.resources.length };
      }
    }
  }
  return best;
}

describe("W-015 world_chunk WebSocket payload budget", () => {
  const db = createDbPool();
  let app: Awaited<ReturnType<typeof buildApp>> | undefined;
  let socket: WebSocket | undefined;
  const received: ReceivedFrame[] = [];

  beforeAll(async () => {
    app = await buildApp({ db });
    await app.listen({ host: "127.0.0.1", port: 0 });
  });

  afterAll(async () => {
    if (socket && socket.readyState !== WebSocket.CLOSED) socket.terminate();
    if (app) await app.close();
    await db.end();
  });

  async function awaitFrames(
    requestId: string,
    expectedCount: number,
    from: number,
  ): Promise<Array<{ frame: ReceivedFrame; reply: ChunkReply }>> {
    const deadline = Date.now() + WAIT_MS;
    for (;;) {
      const replies: Array<{ frame: ReceivedFrame; reply: ChunkReply }> = [];
      for (const frame of received.slice(from)) {
        const message = JSON.parse(frame.raw) as unknown;
        if (typeof message === "object" && message !== null && (message as { type?: unknown }).type === "error") {
          throw new Error("WORLD_CHUNK_SERVER_ERROR");
        }
        if (isChunkReply(message) && message.requestId === requestId) replies.push({ frame, reply: message });
      }
      if (replies.length >= expectedCount) return replies;
      if (Date.now() >= deadline) {
        throw new Error("WORLD_CHUNK_TIMEOUT: expected " + expectedCount + ", received " + replies.length);
      }
      await new Promise((resolve) => setTimeout(resolve, 5));
    }
  }

  async function subscribe(
    requestId: string,
    coordinates: Coordinate[],
  ): Promise<Array<{ frame: ReceivedFrame; reply: ChunkReply }>> {
    if (!socket) throw new Error("SOCKET_NOT_CONNECTED");
    const from = received.length;
    socket.send(JSON.stringify({ type: "subscribe_chunks", requestId, chunks: coordinates }));
    const replies = await awaitFrames(requestId, coordinates.length, from);
    const requested = new Set(coordinates.map(({ x, y }) => x + "," + y));
    const returned = new Set(replies.map(({ reply }) => reply.chunk.x + "," + reply.chunk.y));
    expect(returned).toEqual(requested);
    expect(replies).toHaveLength(coordinates.length);
    for (const { frame, reply } of replies) {
      expect(frame.binary).toBe(false);
      expect(frame.utf8Bytes).toBeLessThanOrEqual(GODOT_MAX_PACKET_BYTES);
      expect(reply.chunk.tiles).toHaveLength(32 * 32);
    }
    return replies;
  }

  it("bounds nine normal and one high-resource-density real outbound frames", async () => {
    if (!app) throw new Error("APP_NOT_READY");
    const unique = randomUUID().replace(/-/g, "").slice(0, 20);
    const registration = await app.inject({
      method: "POST",
      url: "/auth/register",
      payload: {
        username: "frame_" + unique,
        email: "frame_" + unique + "@example.com",
        password: "Correct-Horse-Battery-9",
      },
    });
    expect(registration.statusCode).toBe(201);
    const token = (JSON.parse(registration.body) as { accessToken: string }).accessToken;
    const address = app.server.address();
    if (!address || typeof address === "string") throw new Error("TEST_SERVER_NOT_LISTENING");

    socket = new WebSocket("ws://127.0.0.1:" + address.port + "/ws");
    socket.on("message", (raw: Buffer, binary: boolean) => {
      const value = raw.toString("utf8");
      received.push({ raw: value, utf8Bytes: Buffer.byteLength(value, "utf8"), binary });
    });
    await new Promise<void>((resolve, reject) => {
      socket?.once("open", () => resolve());
      socket?.once("error", reject);
    });

    const authFrom = received.length;
    socket.send(JSON.stringify({ type: "auth", token }));
    const deadline = Date.now() + WAIT_MS;
    while (!received.slice(authFrom).some((frame) => (JSON.parse(frame.raw) as { type?: string }).type === "auth_ok")) {
      if (Date.now() >= deadline) throw new Error("AUTH_OK_TIMEOUT");
      await new Promise((resolve) => setTimeout(resolve, 5));
    }

    const normal: Coordinate[] = [];
    for (let y = -1; y <= 1; y += 1) {
      for (let x = -1; x <= 1; x += 1) normal.push({ x, y });
    }
    const normalFrames = await subscribe("w015-normal", normal);
    const dense = selectDenseGeneratedChunk();
    expect(dense.resourceCount).toBeGreaterThan(0);
    const denseFrames = await subscribe("w015-dense", [dense.coordinate]);
    expect(denseFrames[0].reply.chunk.resources.length).toBeLessThanOrEqual(dense.resourceCount);

    const measured = [...normalFrames, ...denseFrames].map(({ frame }) => frame.utf8Bytes);
    const maximum = Math.max(...measured);
    console.log("[W-015] real world_chunk frames=" + measured.length
      + "; max_utf8_bytes=" + maximum + "; budget=" + GODOT_MAX_PACKET_BYTES
      + "; dense_resources=" + dense.resourceCount);
    expect(measured).toHaveLength(10);
    expect(maximum).toBeLessThanOrEqual(GODOT_MAX_PACKET_BYTES);
  });
});
