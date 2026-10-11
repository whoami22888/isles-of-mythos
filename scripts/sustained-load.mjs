import { createHmac } from "node:crypto";
import { writeFileSync } from "node:fs";
import { WebSocket } from "ws";
import pg from "pg";

const baseUrl = process.env.LOADTEST_BASE_URL ?? "http://127.0.0.1:3000";
const wsUrl = `${baseUrl.replace(/^http/, "ws")}/ws`;
const durationMs = Number(process.env.LOADTEST_DURATION_MS ?? 10000);
const httpRequests = Number(process.env.LOADTEST_HTTP_REQUESTS ?? 100);
const levels = [10, 50, 100, 500, 1000];
const secret = process.env.JWT_SECRET ?? "loadtest-secret";
const { Pool } = pg;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function loadTestUsers() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  try {
    const result = await pool.query(
      "SELECT id, username FROM users WHERE username LIKE 'loadtest_%' ORDER BY username",
    );
    if (result.rows.length < 1000) {
      throw new Error(`Expected 1000 seeded load-test users, found ${result.rows.length}`);
    }
    return result.rows.slice(0, 1000);
  } finally {
    await pool.end();
  }
}

function tokenFor(user) {
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({
    sub: user.id,
    username: user.username,
    iat: Math.floor(Date.now() / 1000),
  })).toString("base64url");
  const data = `${header}.${payload}`;
  const signature = createHmac("sha256", secret).update(data).digest("base64url");
  return `${data}.${signature}`;
}

function percentile(values, p) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * p) - 1)];
}

async function httpLoad() {
  const latencies = [];
  let errors = 0;
  let next = 0;
  const started = performance.now();

  async function worker() {
    while (true) {
      const index = next++;
      if (index >= httpRequests) return;
      const startedRequest = performance.now();
      try {
        const response = await fetch(`${baseUrl}/health`);
        if (!response.ok) errors++;
        else await response.text();
      } catch {
        errors++;
      }
      latencies.push(performance.now() - startedRequest);
    }
  }

  await Promise.all(Array.from({ length: Math.min(20, httpRequests) }, worker));
  const elapsed = performance.now() - started;

  return {
    requests: httpRequests,
    errors,
    durationMs: Math.round(elapsed),
    requestsPerSecond: httpRequests / Math.max(0.001, elapsed / 1000),
    p50Ms: percentile(latencies, 0.5),
    p95Ms: percentile(latencies, 0.95),
    p99Ms: percentile(latencies, 0.99),
  };
}

async function loadMutationNodes(required) {
  const nodes = [];
  for (let chunkY = 8; chunkY <= 16 && nodes.length < required; chunkY += 1) {
    for (let chunkX = 8; chunkX <= 16 && nodes.length < required; chunkX += 1) {
      const response = await fetch(`${baseUrl}/world/chunks/${chunkX}/${chunkY}`);
      if (!response.ok) throw new Error(`Failed to load performance resource chunk ${chunkX}/${chunkY}: ${response.status}`);
      const chunk = await response.json();
      for (const resource of chunk.resources ?? []) {
        if (resource?.id && resource?.type && Number.isSafeInteger(resource.x) && Number.isSafeInteger(resource.y)) {
          nodes.push(resource);
          if (nodes.length === required) break;
        }
      }
    }
  }
  if (nodes.length < required) throw new Error(`Expected ${required} generated performance resource nodes, found ${nodes.length}`);
  return nodes;
}

async function prepareMutationUser(user, node) {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  try {
    await pool.query(
      "INSERT INTO player_profiles(user_id,x,y,inventory) VALUES($1,$2,$3,$4::jsonb) ON CONFLICT(user_id) DO UPDATE SET x=EXCLUDED.x,y=EXCLUDED.y,inventory=EXCLUDED.inventory",
      [user.id, node.x, node.y, JSON.stringify({ "resource.wood": 8 })],
    );
  } finally {
    await pool.end();
  }
}

async function exerciseCraftMutation(socket, user, scenario) {
  const requestId = `performance-craft-${scenario}`;
  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off("message", onMessage);
      reject(new Error(`Gameplay mutation timed out: craft ${requestId}`));
    }, 5000);

    function onMessage(raw) {
      try {
        const value = JSON.parse(raw.toString());
        if (value.type !== "craft_result" && value.type !== "error") return;
        clearTimeout(timer);
        socket.off("message", onMessage);
        resolve(value);
      } catch {}
    }

    socket.on("message", onMessage);
    socket.send(JSON.stringify({ type: "craft", requestId, recipeId: "tool.wooden-club" }));
  });

  if (result.type === "error") throw new Error(`Gameplay mutation failed: craft ${result.code}`);
  if (result.type !== "craft_result" ||
      result.requestId !== requestId ||
      result.recipeId !== "tool.wooden-club" ||
      typeof result.transactionId !== "string") {
    throw new Error(`Gameplay mutation returned invalid craft result for ${requestId}`);
  }

  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  try {
    const profile = await pool.query(
      "SELECT inventory FROM player_profiles WHERE user_id=$1",
      [user.id],
    );
    const inventory = profile.rows[0]?.inventory;
    if (inventory?.["resource.wood"] !== 0 || inventory?.["tool.wooden-club"] !== 1) {
      throw new Error(`Gameplay craft did not persist expected inventory for ${requestId}`);
    }

    const ledger = await pool.query(
      "SELECT transaction_id, response FROM craft_requests WHERE request_key=$1",
      [`${user.id}:${requestId}`],
    );
    const row = ledger.rows[0];
    if (!row || row.transaction_id !== result.transactionId || row.response?.recipeId !== "tool.wooden-club") {
      throw new Error(`Gameplay craft transaction was not durably persisted for ${requestId}`);
    }
  } finally {
    await pool.end();
  }

  return {
    action: "craft",
    recipeId: "tool.wooden-club",
    transactionId: result.transactionId,
    persisted: true,
  };
}

async function exerciseGatherMutation(socket, user, node, scenario) {
  const requestId = `performance-gather-${scenario}`;
  const itemId = node.type === "wood" ? "resource.wood" : node.type === "stone" ? "resource.stone" : "resource.herb";
  const expectedQuantity = node.type === "herb" ? 1 : 2;

  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off("message", onMessage);
      reject(new Error(`Gameplay mutation timed out: gather_resource ${node.id}`));
    }, 5000);

    function onMessage(raw) {
      try {
        const value = JSON.parse(raw.toString());
        if (value.type !== "resource_gathered" && value.type !== "error") return;
        clearTimeout(timer);
        socket.off("message", onMessage);
        resolve(value);
      } catch {}
    }

    socket.on("message", onMessage);
    socket.send(JSON.stringify({ type: "gather_resource", requestId, resourceId: node.id }));
  });

  if (result.type === "error") throw new Error(`Gameplay mutation failed: ${result.code}`);
  if (result.type !== "resource_gathered" ||
      result.requestId !== requestId ||
      result.resourceId !== node.id ||
      result.itemId !== itemId ||
      result.quantity !== expectedQuantity) {
    throw new Error(`Gameplay mutation returned invalid result for ${node.id}`);
  }

  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  try {
    const profile = await pool.query(
      "SELECT inventory->>$2 AS quantity FROM player_profiles WHERE user_id=$1",
      [user.id, itemId],
    );
    if (Number(profile.rows[0]?.quantity ?? 0) < expectedQuantity) {
      throw new Error(`Gameplay mutation did not persist inventory for ${node.id}`);
    }
    const nodeState = await pool.query(
      "SELECT depleted_until FROM world_resource_nodes WHERE node_id=$1",
      [node.id],
    );
    const depletedUntil = nodeState.rows[0]?.depleted_until;
    if (!depletedUntil || new Date(depletedUntil).getTime() <= Date.now()) {
      throw new Error(`Gameplay mutation did not persist resource depletion for ${node.id}`);
    }
  } finally {
    await pool.end();
  }

  return { action: "gather_resource", resourceId: node.id, itemId, quantity: expectedQuantity, persisted: true };
}

async function waitForPong(socket) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      socket.off("message", onMessage);
      resolve(false);
    }, 2000);

    function onMessage(raw) {
      try {
        if (JSON.parse(raw.toString()).type !== "pong") return;
        clearTimeout(timer);
        socket.off("message", onMessage);
        resolve(true);
      } catch {}
    }

    socket.on("message", onMessage);
    socket.send(JSON.stringify({ type: "ping" }));
  });
}

async function wsLoad(playerCount, users, mutationUser, mutationNode, scenario) {
  const sockets = [];
  const latencies = [];
  let connected = 0;
  let authenticated = 0;
  let errors = 0;

  await new Promise((resolve, reject) => {
    let remaining = playerCount;
    let settled = false;

    const finish = () => {
      if (remaining === 0 && !settled) {
        settled = true;
        resolve();
      }
    };

    for (let index = 0; index < playerCount; index++) {
      const socket = new WebSocket(wsUrl);
      sockets.push(socket);
      const started = performance.now();

      socket.once("open", () => {
        connected++;
        socket.once("message", (raw) => {
          try {
            const ready = JSON.parse(raw.toString());
            if (ready.type !== "server_ready") throw new Error("missing server_ready");

            socket.on("message", function authMessage(authRaw) {
              try {
                const auth = JSON.parse(authRaw.toString());
                if (auth.type !== "auth_ok") return;
                socket.off("message", authMessage);
                authenticated++;
                latencies.push(performance.now() - started);
              } catch {
                errors++;
              }
              remaining--;
              finish();
            });

            socket.send(JSON.stringify({ type: "auth", token: tokenFor(users[index]) }));
          } catch {
            errors++;
            remaining--;
            finish();
          }
        });
      });

      socket.on("error", () => {
        errors++;
        remaining--;
        finish();
      });
    }

    setTimeout(() => {
      if (!settled) reject(new Error(`Timed out establishing ${playerCount} WebSockets`));
    }, Math.max(60000, durationMs * 6));
  });

  if (connected !== playerCount || authenticated !== playerCount || errors !== 0) {
    for (const socket of sockets) socket.close();
    throw new Error(`Player-load establishment failed: requested=${playerCount} connected=${connected} authenticated=${authenticated} errors=${errors}`);
  }

  const mutationIndex = users.findIndex((user) => user.id === mutationUser.id);
  if (mutationIndex < 0 || mutationIndex >= sockets.length) {
    for (const socket of sockets) socket.close();
    throw new Error("Performance mutation user was not included in this scenario");
  }
  const gameplayCraft = await exerciseCraftMutation(sockets[mutationIndex], mutationUser, scenario);
  const gameplayMutation = await exerciseGatherMutation(sockets[mutationIndex], mutationUser, mutationNode, scenario);

  const end = Date.now() + durationMs;
  let pings = 0;
  let pongs = 0;

  while (Date.now() < end) {
    const active = sockets.filter((socket) => socket.readyState === WebSocket.OPEN);
    await Promise.all(active.map(async (socket) => {
      const started = performance.now();
      pings++;
      if (await waitForPong(socket)) {
        pongs++;
        latencies.push(performance.now() - started);
      }
    }));
    await sleep(250);
  }

  for (const socket of sockets) socket.close();
  await sleep(100);

  const pingSuccessRate = pings ? pongs / pings : 0;
  if (pings === 0 || pongs !== pings) {
    throw new Error(`Player-load ping failure: requested=${playerCount} pings=${pings} pongs=${pongs}`);
  }

  return {
    requestedPlayers: playerCount,
    connected,
    authenticated,
    errors,
    gameplayCraft,
    gameplayMutation,
    pings,
    pongs,
    pingSuccessRate,
    p50Ms: percentile(latencies, 0.5),
    p95Ms: percentile(latencies, 0.95),
    p99Ms: percentile(latencies, 0.99),
  };
}

const users = await loadTestUsers();
const mutationNodes = await loadMutationNodes(levels.length);
const scenarios = [];

for (let index = 0; index < levels.length; index += 1) {
  const players = levels[index];
  // Use a player outside all earlier cohorts so its active server state cannot be stale.
const mutationUserIndexes = [0, 10, 50, 100, 500];
const mutationUser = users[mutationUserIndexes[index]];
  const mutationNode = mutationNodes[index];
  await prepareMutationUser(mutationUser, mutationNode);

  const result = {
    players,
    http: await httpLoad(),
    websocket: await wsLoad(players, users, mutationUser, mutationNode, index + 1),
  };
  if (result.http.errors !== 0) {
    throw new Error(`HTTP load failed at ${players} players: ${result.http.errors} errors`);
  }
  scenarios.push(result);
  writeFileSync("performance-results.json", JSON.stringify({
    event: "sustained_load_progress",
    durationMs,
    scenarios,
  }, null, 2));
  console.log(JSON.stringify(result));
}

const finalResult = { event: "sustained_load_complete", durationMs, scenarios };
writeFileSync("performance-results.json", JSON.stringify(finalResult, null, 2));
console.log(JSON.stringify(finalResult));
