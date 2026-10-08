import { describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { buildApp } from "./app.js";
import { config } from "./config.js";
import { parseClientMessage } from "./protocol.js";
import { CREATURE_STATS } from "./combat.js";

type JsonObject = Record<string, unknown>;

function waitForMessage(socket: WebSocket): Promise<unknown> {
  return waitForMatchingMessage(socket, () => true);
}

function waitForMatchingMessage(
  socket: WebSocket,
  predicate: (message: unknown) => boolean,
): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const received: unknown[] = [];
    const timer = setTimeout(() => {
      reject(new Error(`Timed out waiting for WebSocket message; received: ${JSON.stringify(received)}`));
    }, 2_000);

    const onMessage = (raw: Buffer) => {
      let message: unknown;
      try {
        message = JSON.parse(raw.toString()) as unknown;
      } catch (error: unknown) {
        clearTimeout(timer);
        socket.off("message", onMessage);
        reject(error instanceof Error ? error : new Error("Invalid JSON message"));
        return;
      }
      received.push(message);
      if (!predicate(message)) return;
      clearTimeout(timer);
      socket.off("message", onMessage);
      resolve(message);
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

function parseJsonObject(body: string): JsonObject {
  const value: unknown = JSON.parse(body);
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Expected JSON object");
  }
  return value as JsonObject;
}

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function getObject(value: JsonObject, key: string): JsonObject {
  const nested = value[key];
  if (typeof nested !== "object" || nested === null || Array.isArray(nested)) {
    throw new Error(`Expected object property: ${key}`);
  }
  return nested as JsonObject;
}

function getString(value: JsonObject, key: string): string {
  const result = value[key];
  if (typeof result !== "string") throw new Error(`Expected string property: ${key}`);
  return result;
}

async function openSocket(app: Awaited<ReturnType<typeof buildApp>>): Promise<WebSocket> {
  await app.listen({ host: "127.0.0.1", port: 0 });
  const address = app.server.address();
  if (address === null || typeof address === "string") throw new Error("Test server has no TCP address");
  return new WebSocket(`ws://127.0.0.1:${address.port}/ws`);
}

describe("server foundation", () => {
  it("uses a valid port", () => {
    expect(config.port).toBeGreaterThan(0);
    expect(config.port).toBeLessThanOrEqual(65535);
  });

  it("builds the Fastify application and exposes readiness", async () => {
    const app = await buildApp();

    try {
      expect((await app.inject({ method: "GET", url: "/health" })).statusCode).toBe(200);
      const ready = await app.inject({ method: "GET", url: "/ready" });
      expect(ready.statusCode).toBe(200);
      expect(parseJsonObject(ready.body)).toMatchObject({ status: "ready", database: "ok" });

      const docs = await app.inject({ method: "GET", url: "/documentation/json" });
      expect(docs.statusCode).toBe(200);
      const docsBody = parseJsonObject(docs.body);
      expect(getString(getObject(docsBody, "info"), "title")).toBe("Isles of Mythos API");

      const chunk = await app.inject({ method: "GET", url: "/world/chunks/0/0" });
      expect(chunk.statusCode).toBe(200);
      expect(parseJsonObject(chunk.body)).toMatchObject({ size: 32 });
      const trustedCors = await app.inject({ method: "GET", url: "/health", headers: { origin: config.corsOrigin } });
      expect(trustedCors.headers["access-control-allow-origin"]).toBe(config.corsOrigin);
      const untrustedCors = await app.inject({ method: "GET", url: "/health", headers: { origin: "https://untrusted.example" } });
      expect(untrustedCors.headers["access-control-allow-origin"]).toBeUndefined();
    } finally {
      await app.close();
    }
  });

  it("does not perform captured-creature DB loading during application construction", async () => {
    const database = (await import("./db.js")).createDbPool();
    let queryCount = 0;
    const originalQuery = database.query.bind(database);
    database.query = ((...args: Parameters<typeof database.query>) => {
      queryCount += 1;
      return originalQuery(...args);
    }) as typeof database.query;

    const app = await buildApp({ db: database });
    try {
      expect(queryCount).toBe(0);
    } finally {
      await app.close();
      await database.end();
    }
  });

  it("parses only supported protocol messages", () => {
    expect(parseClientMessage('{"type":"ping"}')).toEqual({ type: "ping" });
    expect(parseClientMessage('{"type":"auth","token":"abc"}')).toEqual({ type: "auth", token: "abc" });
    expect(parseClientMessage('{"type":"subscribe_chunks","requestId":"r1","chunks":[{"x":0,"y":0}]}')).toEqual({
      type: "subscribe_chunks",
      requestId: "r1",
      chunks: [{ x: 0, y: 0 }],
    });
    expect(parseClientMessage('{"type":"move","dx":1,"dy":0,"sequence":7}')).toEqual({
      type: "move",
      dx: 1,
      dy: 0,
      sequence: 7,
    });
    expect(parseClientMessage('{"type":"select_hotbar","slot":7}')).toEqual({
      type: "select_hotbar",
      slot: 7,
    });
    expect(parseClientMessage('{"type":"select_hotbar","slot":8}')).toBeNull();
    expect(parseClientMessage('{"type":"move","dx":2,"dy":0,"sequence":8}')).toBeNull();
    expect(parseClientMessage('{"type":"move","dx":1,"dy":0,"dt":0.25,"sequence":8}')).toEqual({ type: "move", dx: 1, dy: 0, sequence: 8 });
    expect(parseClientMessage('{"type":"move","dx":1,"dy":0,"sequence":-1}')).toBeNull();
    expect(parseClientMessage('{"type":"subscribe_chunks","requestId":"r1","chunks":[]}')).toBeNull();
    expect(parseClientMessage("not-json")).toBeNull();
  });

  it("enforces authoritative melee stamina cost and cooldown", async () => {
    const app = await buildApp();
    const unique = Date.now();
    const register = await app.inject({
      method: "POST",
      url: "/auth/register",
      payload: {
        username: `combat_${unique}`,
        email: `combat_${unique}@example.com`,
        password: "Correct-Horse-Battery-9",
      },
    });
    expect(register.statusCode).toBe(201);
    const registerBody = parseJsonObject(register.body);
    const token = getString(registerBody, "accessToken");
    const user = getObject(registerBody, "user");
    const userId = getString(user, "id");

    let spawnObject: JsonObject | null = null;
    for (let chunkY = 0; chunkY < 8 && !spawnObject; chunkY += 1) {
      for (let chunkX = 0; chunkX < 8 && !spawnObject; chunkX += 1) {
        const chunkResponse = await app.inject({ method: "GET", url: `/world/chunks/${chunkX}/${chunkY}` });
        expect(chunkResponse.statusCode).toBe(200);
        const chunk = parseJsonObject(chunkResponse.body);
        const creatures = chunk.creatures;
        if (!Array.isArray(creatures)) throw new Error("Test world chunk creatures are malformed");
        const spawn = creatures.find(isJsonObject);
        if (spawn) spawnObject = spawn;
      }
    }
    if (!spawnObject) throw new Error("Deterministic test world contains no creature spawn");
    const targetId = getString(spawnObject, "id");
    const targetX = Number(spawnObject.x);
    const targetY = Number(spawnObject.y);
    expect(Number.isFinite(targetX)).toBe(true);
    expect(Number.isFinite(targetY)).toBe(true);

    const database = (await import("./db.js")).createDbPool();
    await database.query(
      "INSERT INTO player_profiles (user_id, x, y, stamina) VALUES ($1, $2, $3, 100) ON CONFLICT (user_id) DO UPDATE SET x=EXCLUDED.x, y=EXCLUDED.y, stamina=100",
      [userId, targetX - 0.5, targetY],
    );

    const socket = await openSocket(app);
    try {
      await new Promise<void>((resolve, reject) => {
        socket.once("open", () => resolve());
        socket.once("error", reject);
      });
      const authenticated = waitForMatchingMessage(socket, (message) => typeof message === "object" && message !== null && (message as JsonObject).type === "auth_ok");
      const initialState = waitForMatchingMessage(socket, (message) => typeof message === "object" && message !== null && (message as JsonObject).type === "player_state");
      socket.send(JSON.stringify({ type: "auth", token }));
      await authenticated;
      const authenticatedState = await initialState;
      if (!isJsonObject(authenticatedState)) throw new Error("Expected player_state message");
      const state = authenticatedState.state;
      if (!isJsonObject(state)) throw new Error("Expected player state object");
      expect(state.x).toBe(targetX - 0.5);
      expect(state.y).toBe(targetY);

      const attackResult = waitForMatchingMessage(socket, (message) => typeof message === "object" && message !== null && (message as JsonObject).type === "combat_result");
      socket.send(JSON.stringify({
        type: "attack",
        requestId: "melee-1",
        targetId,
        facingX: 1,
        facingY: 0,
      }));
      await expect(attackResult).resolves.toMatchObject({
        type: "combat_result",
        requestId: "melee-1",
        targetId,
      });

      const cooldown = waitForMatchingMessage(socket, (message) => (
        typeof message === "object"
        && message !== null
        && (message as JsonObject).type === "error"
        && (message as JsonObject).code === "COMBAT_COOLDOWN"
      ));
      socket.send(JSON.stringify({
        type: "attack",
        requestId: "melee-2",
        targetId,
        facingX: 1,
        facingY: 0,
      }));
      await expect(cooldown).resolves.toEqual({ type: "error", code: "COMBAT_COOLDOWN" });

      const stateAfterAttack = waitForMatchingMessage(socket, (message) => typeof message === "object" && message !== null && (message as JsonObject).type === "player_state");
      socket.send(JSON.stringify({ type: "move", dx: 0, dy: 0, sequence: 0 }));
      await expect(stateAfterAttack).resolves.toMatchObject({
        type: "player_state",
        state: { stamina: expect.any(Number) },
      });
    } finally {
      socket.close();
      await database.end();
      await app.close();
    }
  });

  it("enforces authoritative ranged ammunition consumption", async () => {
    const app = await buildApp();
    const unique = Date.now();
    const register = await app.inject({
      method: "POST",
      url: "/auth/register",
      payload: {
        username: `ammo_${unique}`,
        email: `ammo_${unique}@example.com`,
        password: "Correct-Horse-Battery-9",
      },
    });
    expect(register.statusCode).toBe(201);
    const registerBody = parseJsonObject(register.body);
    const token = getString(registerBody, "accessToken");
    const userId = getString(getObject(registerBody, "user"), "id");

    let spawnObject: JsonObject | null = null;
    for (let chunkY = 0; chunkY < 8 && !spawnObject; chunkY += 1) {
      for (let chunkX = 0; chunkX < 8 && !spawnObject; chunkX += 1) {
        const chunkResponse = await app.inject({ method: "GET", url: `/world/chunks/${chunkX}/${chunkY}` });
        expect(chunkResponse.statusCode).toBe(200);
        const chunk = parseJsonObject(chunkResponse.body);
        const creatures = chunk.creatures;
        if (!Array.isArray(creatures)) throw new Error("Test world chunk creatures are malformed");
        const spawn = creatures.find(isJsonObject);
        if (spawn) spawnObject = spawn;
      }
    }
    if (!spawnObject) throw new Error("Deterministic test world contains no creature spawn");
    const targetId = getString(spawnObject, "id");
    const targetX = Number(spawnObject.x);
    const targetY = Number(spawnObject.y);
    const database = (await import("./db.js")).createDbPool();
    await database.query(
      "INSERT INTO player_profiles (user_id, x, y, stamina, inventory) VALUES ($1, $2, $3, 100, $4::jsonb) ON CONFLICT (user_id) DO UPDATE SET x=EXCLUDED.x, y=EXCLUDED.y, stamina=100, inventory=EXCLUDED.inventory",
      [userId, targetX - 0.5, targetY, JSON.stringify({ "ammo.flintlock": 1 })],
    );

    const socket = await openSocket(app);
    try {
      await new Promise<void>((resolve, reject) => {
        socket.once("open", () => resolve());
        socket.once("error", reject);
      });
      const authenticated = waitForMatchingMessage(socket, (message) => isJsonObject(message) && message.type === "auth_ok");
      const initialState = waitForMatchingMessage(socket, (message) => isJsonObject(message) && message.type === "player_state");
      socket.send(JSON.stringify({ type: "auth", token }));
      await authenticated;
      await initialState;

      const selected = waitForMatchingMessage(socket, (message) => isJsonObject(message) && message.type === "player_state" && getObject(message, "state").selectedHotbarSlot === 1);
      socket.send(JSON.stringify({ type: "select_hotbar", slot: 1 }));
      await selected;

      const hit = waitForMatchingMessage(socket, (message) => isJsonObject(message) && message.type === "combat_result");
      socket.send(JSON.stringify({
        type: "attack",
        requestId: "ammo-1",
        targetId,
        facingX: 1,
        facingY: 0,
      }));
      await expect(hit).resolves.toMatchObject({ type: "combat_result", requestId: "ammo-1", targetId });

      const stateAfterAttack = waitForMatchingMessage(socket, (message) => isJsonObject(message) && message.type === "player_state");
      socket.send(JSON.stringify({ type: "move", dx: 0, dy: 0, sequence: 0 }));
      await expect(stateAfterAttack).resolves.toMatchObject({
        type: "player_state",
        state: { inventory: { "ammo.flintlock": 0 } },
      });

      await new Promise((resolve) => setTimeout(resolve, 950));
      const noAmmo = waitForMatchingMessage(socket, (message) => isJsonObject(message) && message.type === "error" && message.code === "NO_AMMO");
      socket.send(JSON.stringify({
        type: "attack",
        requestId: "ammo-2",
        targetId,
        facingX: 1,
        facingY: 0,
      }));
      await expect(noAmmo).resolves.toEqual({ type: "error", code: "NO_AMMO" });
    } finally {
      socket.close();
      await database.end();
      await app.close();
    }
  });

  it("acquires nearby creatures for autonomous server AI", async () => {
    const app = await buildApp();
    const unique = Date.now();
    const register = await app.inject({
      method: "POST",
      url: "/auth/register",
      payload: {
        username: `ai_${unique}`,
        email: `ai_${unique}@example.com`,
        password: "Correct-Horse-Battery-9",
      },
    });
    expect(register.statusCode).toBe(201);
    const registerBody = parseJsonObject(register.body);
    const token = getString(registerBody, "accessToken");
    const userId = getString(getObject(registerBody, "user"), "id");

    let spawnObject: JsonObject | null = null;
    for (let chunkY = 0; chunkY < 8 && !spawnObject; chunkY += 1) {
      for (let chunkX = 0; chunkX < 8 && !spawnObject; chunkX += 1) {
        const chunkResponse = await app.inject({ method: "GET", url: `/world/chunks/${chunkX}/${chunkY}` });
        expect(chunkResponse.statusCode).toBe(200);
        const chunk = parseJsonObject(chunkResponse.body);
        const creatures = chunk.creatures;
        if (!Array.isArray(creatures)) throw new Error("Test world chunk creatures are malformed");
        const spawn = creatures.find(isJsonObject);
        if (spawn) spawnObject = spawn;
      }
    }
    if (!spawnObject) throw new Error("Deterministic test world contains no creature spawn");
    const targetX = Number(spawnObject.x);
    const targetY = Number(spawnObject.y);
    const species = getString(spawnObject, "species");
    const creatureStats = CREATURE_STATS[species];
    if (!creatureStats) throw new Error(`Unknown deterministic test creature species: ${species}`);
    const database = (await import("./db.js")).createDbPool();
    await database.query(
      "INSERT INTO player_profiles (user_id, x, y, stamina, health, defense) VALUES ($1, $2, $3, 100, 100, 5) ON CONFLICT (user_id) DO UPDATE SET x=EXCLUDED.x, y=EXCLUDED.y, stamina=100, health=100, defense=5",
      [userId, targetX - 0.25, targetY],
    );

    const socket = await openSocket(app);
    try {
      await new Promise<void>((resolve, reject) => {
        socket.once("open", () => resolve());
        socket.once("error", reject);
      });
      const authenticated = waitForMatchingMessage(socket, (message) => isJsonObject(message) && message.type === "auth_ok");
      const initialState = waitForMatchingMessage(socket, (message) => isJsonObject(message) && message.type === "player_state");
      socket.send(JSON.stringify({ type: "auth", token }));
      await authenticated;
      await initialState;

      const damaged = waitForMatchingMessage(socket, (message) => {
        if (!isJsonObject(message) || message.type !== "player_state") return false;
        const state = getObject(message, "state");
        return typeof state.health === "number" && state.health < 100;
      });
      await expect(damaged).resolves.toMatchObject({
        type: "player_state",
        state: { health: 100 - Math.max(1, creatureStats.attack + Math.max(0, Number(spawnObject.level) - 1) * 2 - 5) },
      });
    } finally {
      socket.close();
      await database.end();
      await app.close();
    }
  });

  it("persists base, building, and storage state across server restart", async () => {
    const database = (await import("./db.js")).createDbPool();
    const firstApp = await buildApp({ db: database });
    const unique = Date.now();
    const register = await firstApp.inject({
      method: "POST",
      url: "/auth/register",
      payload: {
        username: `base_restart_${unique}`,
        email: `base_restart_${unique}@example.com`,
        password: "Correct-Horse-Battery-9",
      },
    });
    expect(register.statusCode).toBe(201);
    const registerBody = parseJsonObject(register.body);
    const token = getString(registerBody, "accessToken");

    const socket = await openSocket(firstApp);
    let baseId: string | undefined;
    try {
      await new Promise<void>((resolve, reject) => {
        socket.once("open", () => resolve());
        socket.once("error", reject);
      });
      const authenticated = waitForMatchingMessage(socket, (message) => isJsonObject(message) && message.type === "auth_ok");
      socket.send(JSON.stringify({ type: "auth", token }));
      await authenticated;

      const baseCreated = waitForMatchingMessage(socket, (message) => isJsonObject(message) && message.type === "base_state");
      socket.send(JSON.stringify({
        type: "create_base",
        requestId: "base-create-1",
        name: "Restart Test Base",
        x: unique % 100000,
        y: -Math.floor(unique % 100000),
      }));
      const created = await baseCreated;
      const createdBase = getObject(created as JsonObject, "base");
      baseId = getString(createdBase, "id");
      expect(getString(createdBase, "name")).toBe("Restart Test Base");

      const buildingCreated = waitForMatchingMessage(socket, (message) => isJsonObject(message) && message.type === "building_state");
      socket.send(JSON.stringify({
        type: "build",
        requestId: "base-build-1",
        buildingType: "storage",
        level: 1,
        gridX: 1,
        gridY: 0,
      }));
      const building = await buildingCreated;
      expect(getObject(building as JsonObject, "building")).toMatchObject({
        baseId,
        type: "storage",
        level: 1,
        gridX: 1,
        gridY: 0,
      });
    } finally {
      socket.close();
      await firstApp.close();
    }

    if (!baseId) throw new Error("Base creation test did not produce a base id");
    const secondApp = await buildApp({ db: database });
    const secondSocket = await openSocket(secondApp);
    try {
      await new Promise<void>((resolve, reject) => {
        secondSocket.once("open", () => resolve());
        secondSocket.once("error", reject);
      });
      const authenticated = waitForMatchingMessage(secondSocket, (message) => isJsonObject(message) && message.type === "auth_ok");
      const persistedBase = waitForMatchingMessage(secondSocket, (message) => isJsonObject(message) && message.type === "base_state");
      secondSocket.send(JSON.stringify({ type: "auth", token }));
      await authenticated;
      const persisted = await persistedBase;
      const persistedObject = getObject(persisted as JsonObject, "base");
      expect(getString(persistedObject, "id")).toBe(baseId);
      expect(getString(persistedObject, "name")).toBe("Restart Test Base");
      expect(Array.isArray(persistedObject.buildings)).toBe(true);
      const buildings = persistedObject.buildings as unknown[];
      expect(buildings.some((entry) => isJsonObject(entry) && entry.type === "storage" && entry.level === 1 && entry.gridX === 1 && entry.gridY === 0)).toBe(true);
      const storage = getObject(persistedObject, "storage");
      expect(storage.wood).toBe(450);
      expect(storage.stone).toBe(225);
    } finally {
      secondSocket.close();
      await secondApp.close();
      await database.end();
    }
  });

  it("authenticates a WebSocket before allowing world subscriptions", async () => {
    const app = await buildApp();
    const unique = Date.now();
    const register = await app.inject({
      method: "POST",
      url: "/auth/register",
      payload: {
        username: `ws_${unique}`,
        email: `ws_${unique}@example.com`,
        password: "Correct-Horse-Battery-9",
      },
    });
    expect(register.statusCode).toBe(201);
    const registerBody = parseJsonObject(register.body);
    const token = getString(registerBody, "accessToken");

    const socket = await openSocket(app);

    try {
      const ready = waitForMessage(socket);
      await new Promise<void>((resolve, reject) => {
        socket.once("open", () => resolve());
        socket.once("error", reject);
      });
      await expect(ready).resolves.toMatchObject({ type: "server_ready" });

      const denied = waitForMessage(socket);
      socket.send(JSON.stringify({
        type: "subscribe_chunks",
        requestId: "denied",
        chunks: [{ x: 0, y: 0 }],
      }));
      await expect(denied).resolves.toEqual({ type: "error", code: "AUTH_REQUIRED" });

      const authenticated = waitForMessage(socket);
      const playerState = waitForMatchingMessage(socket, (message) => {
        if (typeof message !== "object" || message === null || Array.isArray(message)) return false;
        return (message as JsonObject).type === "player_state";
      });
      socket.send(JSON.stringify({ type: "auth", token }));
      await expect(authenticated).resolves.toMatchObject({ type: "auth_ok" });
      const authenticatedState = await playerState;
      const authenticatedStateObject = getObject(authenticatedState as JsonObject, "state");
      expect(getString(authenticatedState as JsonObject, "type")).toBe("player_state");
      expect(getString(authenticatedStateObject, "userId")).toBeTruthy();
      expect(authenticatedStateObject.health).toBe(100);
      expect(authenticatedStateObject.hunger).toBe(100);
      expect(authenticatedStateObject.oxygen).toBe(100);

      const moved = waitForMessage(socket);
      socket.send(JSON.stringify({ type: "move", dx: 1, dy: 0, sequence: 0 }));
      const movedMessage = await moved;
      const movedObject = movedMessage as JsonObject;
      const movedState = getObject(movedObject, "state");
      expect(getString(movedObject, "type")).toBe("player_state");
      expect(typeof movedState.x).toBe("number");
      expect(typeof movedState.y).toBe("number");

      const selected = waitForMessage(socket);
      socket.send(JSON.stringify({ type: "select_hotbar", slot: 1 }));
      await expect(selected).resolves.toMatchObject({
        type: "player_state",
        state: { selectedHotbarSlot: 1 },
      });

      const chunk = waitForMessage(socket);
      socket.send(JSON.stringify({
        type: "subscribe_chunks",
        requestId: "world-1",
        chunks: [{ x: 0, y: 0 }],
      }));
      await expect(chunk).resolves.toMatchObject({
        type: "world_chunk",
        requestId: "world-1",
        chunk: { x: 0, y: 0, size: 32 },
      });
    } finally {
      socket.close();
      await app.close();
    }
  });

  it("handles bounded concurrent HTTP health traffic", async () => {
    const app = await buildApp();
    try {
      const responses = await Promise.all(
        Array.from({ length: 100 }, () => app.inject({ method: "GET", url: "/health" })),
      );
      expect(responses).toHaveLength(100);
      expect(responses.every((response) => response.statusCode === 200)).toBe(true);
      expect(responses.every((response) => parseJsonObject(response.body).status === "ok")).toBe(true);
    } finally {
      await app.close();
    }
  });

  it("rate-limits excessive WebSocket messages per connection", async () => {
    const app = await buildApp();
    const socket = await openSocket(app);
    try {
      const ready = waitForMessage(socket);
      await new Promise<void>((resolve, reject) => {
        socket.once("open", () => resolve());
        socket.once("error", reject);
      });
      await ready;
      const limited = waitForMatchingMessage(socket, (message) =>
        isJsonObject(message) && message.type === "error" && message.code === "RATE_LIMITED");
      for (let i = 0; i < 121; i += 1) {
        socket.send(JSON.stringify({ type: "ping" }));
      }
      await expect(limited).resolves.toEqual({ type: "error", code: "RATE_LIMITED" });
    } finally {
      socket.close();
      await app.close();
    }
  });

});
