import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { generateChunk, type ResourceNode } from "./world.js";

function findResource(): ResourceNode {
  for (let chunkY = 8; chunkY <= 16; chunkY += 1) {
    for (let chunkX = 8; chunkX <= 16; chunkX += 1) {
      const node = generateChunk(chunkX, chunkY).resources[0];
      if (node) return node;
    }
  }
  throw new Error("TEST_RESOURCE_NODE_NOT_FOUND");
}

async function waitFor(socket: WebSocket, type: string, predicate?: (message: Record<string, unknown>) => boolean): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("TIMEOUT_" + type)), 2_000);
    const onMessage = (raw: Buffer) => {
      const value = JSON.parse(raw.toString()) as Record<string, unknown>;
      if (predicate ? !predicate(value) : value.type !== type) return;
      clearTimeout(timer);
      socket.off("message", onMessage);
      socket.off("error", onError);
      resolve(value);
    };
    const onError = (error: Error) => {
      clearTimeout(timer);
      socket.off("message", onMessage);
      reject(error);
    };
    socket.on("message", onMessage);
    socket.once("error", onError);
  });
}

describe("resource gathering websocket flow", () => {
  it("gathers a nearby generated resource through the authoritative protocol", async () => {
    const db = createDbPool();
    const app = await buildApp({ db });
    const node = findResource();
    const unique = randomUUID().replace(/-/g, "").slice(0, 20);
    let socket: WebSocket | undefined;
    let userId: string | undefined;
    try {
      const register = await app.inject({
        method: "POST",
        url: "/auth/register",
        payload: {
          username: `resource_${unique}`,
          email: `resource_${unique}@example.com`,
          password: "Correct-Horse-Battery-9",
        },
      });
      expect(register.statusCode).toBe(201);
      const body = JSON.parse(register.body) as { accessToken: string; user: { id: string } };
      userId = body.user.id;
      await db.query("UPDATE player_profiles SET x=$2,y=$3 WHERE user_id=$1", [body.user.id, node.x, node.y]);

      await app.listen({ host: "127.0.0.1", port: 0 });
      const address = app.server.address();
      if (address === null || typeof address === "string") throw new Error("TEST_SERVER_NOT_LISTENING");
      socket = new WebSocket(`ws://127.0.0.1:${address.port}/ws`);
      await waitFor(socket, "server_ready");
      socket.send(JSON.stringify({ type: "auth", token: body.accessToken }));
      const playerState = await waitFor(socket, "player_state");
      const player = playerState.state as { x?: number; y?: number };
      expect(player.x).toBe(node.x);
      expect(player.y).toBe(node.y);

      socket.send(JSON.stringify({
        type: "gather_resource",
        requestId: "resource-flow-1",
        resourceId: node.id,
      }));
      const gathered = await waitFor(socket, "resource_gathered", (value) => value.type === "resource_gathered" || value.type === "error");
      if (gathered.type === "error") throw new Error("GATHER_FAILED:" + String(gathered.code));
      expect(gathered.type).toBe("resource_gathered");
      expect(gathered).toMatchObject({
        requestId: "resource-flow-1",
        resourceId: node.id,
        quantity: node.type === "herb" ? 1 : 2,
      });

      const row = await db.query<{ inventory: Record<string, number> }>(
        "SELECT inventory FROM player_profiles WHERE user_id=$1",
        [body.user.id],
      );
      const itemId = node.type === "wood" ? "resource.wood" : node.type === "stone" ? "resource.stone" : "resource.herb";
      expect(row.rows[0]?.inventory[itemId]).toBe(node.type === "herb" ? 1 : 2);
    } finally {
      socket?.close();
      if (userId) await db.query("DELETE FROM resource_gather_requests WHERE user_id=$1", [userId]);
      await db.query("DELETE FROM world_resource_nodes WHERE node_id=$1", [node.id]).catch(() => undefined);
      await app.close();
      await db.end();
    }
  });
});
