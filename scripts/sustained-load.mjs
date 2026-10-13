import { createHmac } from "node:crypto";
import { writeFileSync } from "node:fs";
import { WebSocket } from "ws";
import pg from "pg";
import { generateChunk } from "../server/dist/world.js";

const baseUrl = process.env.LOADTEST_BASE_URL ?? "http://127.0.0.1:3000";
const wsUrl = `${baseUrl.replace(/^http/, "ws")}/ws`;
const durationMs = Number(process.env.LOADTEST_DURATION_MS ?? 10000);
const httpRequests = Number(process.env.LOADTEST_HTTP_REQUESTS ?? 100);
const section93Players = [1, 50, 250, 1000];
const loadTestPlayers = [10, 50, 100, 500, 1000];
const levels = [...new Set([...section93Players, ...loadTestPlayers])].sort((a, b) => a - b);
const secret = process.env.JWT_SECRET ?? "loadtest-secret";
const { Pool } = pg;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function loadTestUsers() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  try {
    const result = await pool.query(
      "SELECT id, username FROM users WHERE username LIKE 'loadtest_%' ORDER BY username",
    );
    if (result.rows.length < 5000) {
      throw new Error(`Expected 5000 seeded load-test users, found ${result.rows.length}`);
    }
    return result.rows.slice(0, 5000);
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

// The production API permits 120 requests per minute. Each 100-request
// HTTP sample must run in a fresh rate-limit window; do not weaken server limits.
let lastHttpLoadStartedAt;
async function httpLoad() {
  if (lastHttpLoadStartedAt !== undefined) {
    const remainingMs = 60_500 - (performance.now() - lastHttpLoadStartedAt);
    if (remainingMs > 0) await sleep(remainingMs);
  }
  const latencies = [];
  let errors = 0;
  let next = 0;
  const started = performance.now();
  lastHttpLoadStartedAt = started;

  async function worker() {
    while (true) {
      const index = next++;
      if (index >= httpRequests) return;
      const startedRequest = performance.now();
      try {
        const chunkX = 8 + (index % 9);
      const chunkY = 8 + (Math.floor(index / 9) % 9);
      const response = await fetch(baseUrl + "/world/chunks/" + chunkX + "/" + chunkY);
      if (!response.ok) errors++;
      else await response.json();
      } catch {
        errors++;
      }
      latencies.push(performance.now() - startedRequest);
    }
  }

  await Promise.all(Array.from({ length: Math.min(20, httpRequests) }, worker));
  const elapsed = performance.now() - started;

  return {
    endpoint: "world_chunks",
    requests: httpRequests,
    errors,
    durationMs: Math.round(elapsed),
    requestsPerSecond: httpRequests / Math.max(0.001, elapsed / 1000),
    p50Ms: percentile(latencies, 0.5),
    p95Ms: percentile(latencies, 0.95),
    p99Ms: percentile(latencies, 0.99),
  };
}

function loadMutationNodes(required) {
  // Keep performance-test gather fixtures outside creature aggro/ability range.
  // Otherwise the live combat loop can stun a sample player and make an economy
  // mutation fail for a reason unrelated to the resource-gathering path.
  const nodes = [];
  const creatures = [];
  for (let chunkY = 7; chunkY <= 17; chunkY += 1) {
    for (let chunkX = 7; chunkX <= 17; chunkX += 1) {
      const chunk = generateChunk(chunkX, chunkY);
      creatures.push(...chunk.creatures);
      if (chunkX < 8 || chunkX > 16 || chunkY < 8 || chunkY > 16) continue;
      nodes.push(...chunk.resources);
    }
  }
  const safeNodes = nodes.filter((resource) =>
    creatures.every((creature) => Math.hypot(resource.x - creature.x, resource.y - creature.y) > 10),
  );
  if (safeNodes.length < required) {
    throw new Error(`Expected ${required} resource nodes outside creature aggro range, found ${safeNodes.length}`);
  }
  return safeNodes.slice(0, required);
}
async function prepareMutationUsers(users, nodes) {
  if (users.length !== nodes.length) throw new Error("Mutation user/node fixture count mismatch");
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  try {
    for (let index = 0; index < users.length; index++) {
      await pool.query(
        "INSERT INTO player_profiles(user_id,x,y,inventory) VALUES($1,$2,$3,$4::jsonb) ON CONFLICT(user_id) DO UPDATE SET x=EXCLUDED.x,y=EXCLUDED.y,inventory=EXCLUDED.inventory",
        [users[index].id, nodes[index].x, nodes[index].y, JSON.stringify({ "resource.wood": 8 })],
      );
    }
  } finally {
    await pool.end();
  }
}
async function exerciseCraftMutation(socket, user, scenario) {
  const requestId = "performance-craft-" + scenario;
  const requestStarted = performance.now();
  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off("message", onMessage);
      reject(new Error("Gameplay mutation timed out: craft " + requestId));
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
  const latencyMs = performance.now() - requestStarted;
  if (result.type === "error") throw new Error("Gameplay mutation failed: craft " + result.code);
  if (result.type !== "craft_result" || result.requestId !== requestId ||
      result.recipeId !== "tool.wooden-club" || typeof result.transactionId !== "string") {
    throw new Error("Gameplay mutation returned invalid craft result for " + requestId);
  }
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  let inventory;
  let row;
  try {
    const profile = await pool.query("SELECT inventory FROM player_profiles WHERE user_id=$1", [user.id]);
    inventory = profile.rows[0]?.inventory;
    if (inventory?.["resource.wood"] !== 0 || inventory?.["tool.wooden-club"] !== 1) {
      throw new Error("Gameplay craft did not persist expected inventory for " + requestId);
    }
    const ledger = await pool.query("SELECT transaction_id, response FROM craft_requests WHERE request_key=$1", [user.id + ":" + requestId]);
    row = ledger.rows[0];
    if (!row || row.transaction_id !== result.transactionId || row.response?.recipeId !== "tool.wooden-club") {
      throw new Error("Gameplay craft transaction was not durably persisted for " + requestId);
    }
  } finally {
    await pool.end();
  }
  return {
    action: "craft",
    recipeId: "tool.wooden-club",
    transactionId: result.transactionId,
    latencyMs,
    persisted: true,
    persistenceEvidence: {
      inventoryAfter: {
        "resource.wood": inventory["resource.wood"],
        "tool.wooden-club": inventory["tool.wooden-club"],
      },
      ledger: { transactionId: row.transaction_id, recipeId: row.response.recipeId },
    },
  };
}

async function exerciseGatherMutation(socket, user, node, scenario) {
  const requestId = "performance-gather-" + scenario;
  const itemId = node.type === "wood" ? "resource.wood" : node.type === "stone" ? "resource.stone" : "resource.herb";
  const expectedQuantity = node.type === "herb" ? 1 : 2;
  const requestStarted = performance.now();
  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off("message", onMessage);
      reject(new Error("Gameplay mutation timed out: gather_resource " + node.id));
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
  const latencyMs = performance.now() - requestStarted;
  if (result.type === "error") throw new Error("Gameplay mutation failed: " + result.code);
  if (result.type !== "resource_gathered" || result.requestId !== requestId ||
      result.resourceId !== node.id || result.itemId !== itemId || result.quantity !== expectedQuantity) {
    throw new Error("Gameplay mutation returned invalid result for " + node.id);
  }
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  let inventoryQuantity;
  let depletedUntil;
  try {
    const profile = await pool.query("SELECT inventory->>$2 AS quantity FROM player_profiles WHERE user_id=$1", [user.id, itemId]);
    inventoryQuantity = Number(profile.rows[0]?.quantity ?? 0);
    if (inventoryQuantity < expectedQuantity) {
      throw new Error("Gameplay mutation did not persist inventory for " + node.id);
    }
    const nodeState = await pool.query("SELECT depleted_until FROM world_resource_nodes WHERE node_id=$1", [node.id]);
    depletedUntil = nodeState.rows[0]?.depleted_until;
    if (!depletedUntil || new Date(depletedUntil).getTime() <= Date.now()) {
      throw new Error("Gameplay mutation did not persist resource depletion for " + node.id);
    }
  } finally {
    await pool.end();
  }
  return {
    action: "gather_resource",
    resourceId: node.id,
    itemId,
    quantity: expectedQuantity,
    latencyMs,
    persisted: true,
    persistenceEvidence: {
      inventoryQuantity,
      depletedUntil: new Date(depletedUntil).toISOString(),
    },
  };
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

async function wsLoad(playerCount, users, sampleUsers, sampleNodes, cohortStart, scenario, includeGameplayMutations = true, scenarioDurationMs = durationMs) {
  const sockets = [];
  const authLatencies = [];
  const pingLatencies = [];
  const gameplayLatencies = [];
  let networkBytesSent = 0;
  let networkBytesReceived = 0;
  let connected = 0;
  let authenticated = 0;
  let errors = 0;

  await new Promise((resolve, reject) => {
    let remaining = playerCount;
    let settled = false;
    const finish = () => { if (remaining === 0 && !settled) { settled = true; resolve(); } };

    for (let index = 0; index < playerCount; index++) {
      const socket = new WebSocket(wsUrl);
      sockets.push(socket);
      const originalSend = socket.send.bind(socket);
      socket.send = (data, ...args) => {
        networkBytesSent += typeof data === "string" ? Buffer.byteLength(data) : (data?.byteLength ?? data?.length ?? 0);
        return originalSend(data, ...args);
      };
      socket.on("message", raw => { networkBytesReceived += Buffer.isBuffer(raw) ? raw.length : Buffer.byteLength(String(raw)); });
      const started = performance.now();
      socket.once("open", () => {
        connected++;
        socket.once("message", raw => {
          try {
            const ready = JSON.parse(raw.toString());
            if (ready.type !== "server_ready") throw new Error("missing server_ready");
            socket.on("message", function authMessage(authRaw) {
              try {
                const auth = JSON.parse(authRaw.toString());
                if (auth.type !== "auth_ok") return;
                socket.off("message", authMessage);
                authenticated++;
                authLatencies.push(performance.now() - started);
              } catch { errors++; }
              remaining--;
              finish();
            });
            socket.send(JSON.stringify({ type: "auth", token: tokenFor(users[cohortStart + index]) }));
          } catch { errors++; remaining--; finish(); }
        });
      });
      socket.on("error", () => { errors++; remaining--; finish(); });
    }
    setTimeout(() => { if (!settled) reject(new Error("Timed out establishing " + playerCount + " WebSockets")); }, Math.max(60000, durationMs * 6));
  });

  if (connected !== playerCount || authenticated !== playerCount || errors !== 0) {
    for (const socket of sockets) socket.close();
    throw new Error("Player-load establishment failed: requested=" + playerCount + " connected=" + connected + " authenticated=" + authenticated + " errors=" + errors);
  }

  const sampleCount = includeGameplayMutations ? Math.min(playerCount, 100) : 0;
  if (sampleUsers.length !== sampleCount || sampleNodes.length !== sampleCount) {
    for (const socket of sockets) socket.close();
    throw new Error("Gameplay latency sample fixtures do not match scenario size");
  }
  const end = Date.now() + scenarioDurationMs;
  let pings = 0;
  let pongs = 0;
  while (Date.now() < end) {
    const active = sockets.filter(socket => socket.readyState === WebSocket.OPEN);
    await Promise.all(active.map(async socket => {
      const started = performance.now();
      pings++;
      if (await waitForPong(socket)) {
        pongs++;
        pingLatencies.push(performance.now() - started);
      }
    }));
    await sleep(250);
  }

  const pingSuccessRate = pings ? pongs / pings : 0;
  if (pings === 0 || pongs !== pings) throw new Error("Player-load ping failure: requested=" + playerCount + " pings=" + pings + " pongs=" + pongs);

  const gameplayResults = [];
  for (let offset = 0; offset < sampleCount; offset += 10) {
    const batchSize = Math.min(10, sampleCount - offset);
    const batch = await Promise.all(Array.from({ length: batchSize }, async (_, localIndex) => {
      const index = offset + localIndex;
      const user = sampleUsers[index];
      const node = sampleNodes[index];
      const socket = sockets[index];
      const suffix = scenario * 1000 + index;
      const craft = await exerciseCraftMutation(socket, user, suffix);
      const mutation = await exerciseGatherMutation(socket, user, node, suffix);
      gameplayLatencies.push(craft.latencyMs, mutation.latencyMs);
      return { craft, mutation };
    }));
    gameplayResults.push(...batch);
  }

  const gameplayCraft = gameplayResults[0]?.craft;
  const gameplayMutation = gameplayResults[0]?.mutation;
  for (const socket of sockets) socket.close();
  await sleep(100);

  return {
    requestedPlayers: playerCount, connected, authenticated, errors, gameplayCraft, gameplayMutation,
    gameplayLatencySamples: gameplayLatencies.length,
    gameplayP50Ms: percentile(gameplayLatencies, 0.5),
    gameplayP95Ms: percentile(gameplayLatencies, 0.95),
    gameplayP99Ms: percentile(gameplayLatencies, 0.99),
    authP95Ms: percentile(authLatencies, 0.95),
    authP99Ms: percentile(authLatencies, 0.99),
    pings, pongs, pingSuccessRate,
    pingP50Ms: percentile(pingLatencies, 0.5),
    pingP95Ms: percentile(pingLatencies, 0.95),
    pingP99Ms: percentile(pingLatencies, 0.99),
    networkBytesSent, networkBytesReceived,
  };
}
async function readTickCounters() {
  const response = await fetch(baseUrl + "/metrics");
  if (!response.ok) throw new Error("Metrics endpoint returned " + response.status);
  const body = await response.text();
  function value(name) {
    const line = body.split(/\r?\n/).find(item => item.startsWith(name + " "));
    return line ? Number(line.trim().split(/\s+/)[1]) : null;
  }
  const count = value("isles_tick_duration_seconds_count");
  const sum = value("isles_tick_duration_seconds_sum");
  if (!Number.isFinite(count) || !Number.isFinite(sum)) {
    throw new Error("Missing server tick counters at performance measurement boundary");
  }
  return { count, sum };
}
const tickMeasurementStartedAt = performance.now();
const tickMeasurementStart = await readTickCounters();

const users = await loadTestUsers();
const mutationNodes = loadMutationNodes(251);
const scenarios = [];
const loadTestScenarios = [];

// Run the union of both required matrices once. Section 93 requires persisted
// gameplay evidence at 1/50/250/1,000; section 65 separately requires player
// load at 10/50/100/500/1,000. Shared 50/1,000 cohorts satisfy both matrices.
const cohortStarts = [0, 1, 11, 61, 161, 411, 911];
const nodeStartsByPlayers = new Map([[1, 0], [50, 1], [250, 51], [1000, 151]]);
for (let index = 0; index < levels.length; index += 1) {
  const players = levels[index];
  const includeGameplayMutations = section93Players.includes(players);
  const sampleCount = includeGameplayMutations ? Math.min(players, 100) : 0;
  const cohortStart = cohortStarts[index];
  const sampleUsers = includeGameplayMutations
    ? users.slice(cohortStart, cohortStart + sampleCount)
    : [];
  const nodeStart = nodeStartsByPlayers.get(players);
  const sampleNodes = includeGameplayMutations
    ? mutationNodes.slice(nodeStart, nodeStart + sampleCount)
    : [];
  if (includeGameplayMutations) await prepareMutationUsers(sampleUsers, sampleNodes);

  const result = {
    players,
    http: await httpLoad(),
    websocket: await wsLoad(players, users, sampleUsers, sampleNodes, cohortStart, index + 1, includeGameplayMutations),
  };
  if (result.http.errors !== 0) {
    throw new Error(`HTTP load failed at ${players} players: ${result.http.errors} errors`);
  }
  if (includeGameplayMutations) scenarios.push(result);
  if (loadTestPlayers.includes(players)) loadTestScenarios.push(result);
  writeFileSync("performance-results.json", JSON.stringify({
    event: "sustained_load_progress",
    durationMs,
    scenarios,
    loadTestScenarios,
  }, null, 2));
  console.log(JSON.stringify(result));
}

const {runDomainScenarios}=await import("./domain-load-scenarios.mjs");
const domainScenarios=await runDomainScenarios(users);
const finalMutationNodes = loadMutationNodes(323).slice(251).filter(node => node.type !== "herb").slice(0, 4);
if (finalMutationNodes.length !== 4) throw new Error("Expected four long-lived final mutation evidence nodes");
const finalMutationCohortStarts = [0, 11, 161, 911];
const refreshedMutations = await Promise.all(finalMutationCohortStarts.map(async (cohortStart, index) => {
  const user = users[cohortStart];
  const node = finalMutationNodes[index];
  await prepareMutationUsers([user], [node]);
  const refreshed = await wsLoad(1, users, [user], [node], cohortStart, 10000 + index, true, 250);
  return refreshed.gameplayMutation;
}));
for (let index = 0; index < scenarios.length; index += 1) {
  scenarios[index].websocket.gameplayMutation = refreshedMutations[index];
}
writeFileSync("performance-results.json",JSON.stringify({event:"sustained_load_progress",durationMs,scenarios,domainScenarios},null,2));
const mr=await fetch(`${baseUrl}/metrics`);if(!mr.ok)throw Error("Metrics endpoint returned "+mr.status);const mt=await mr.text();
function metricValue(n){const l=mt.split(/\r?\n/).find(x=>x.startsWith(n+" "));return l?Number(l.trim().split(/\s+/)[1]):null;}
function histogramQuantileMs(prefix,q){const count=metricValue(prefix+"_count");if(!Number.isFinite(count)||count<=0)return null;const buckets=mt.split(/\r?\n/).filter(x=>x.startsWith(prefix+"_bucket{")).map(line=>{const label=line.match(/le="([^"]+)"/)?.[1];const value=Number(line.trim().split(/\s+/)[1]);return{bound:label==="+Inf"?Number.POSITIVE_INFINITY:Number(label),value};}).sort((a,b)=>a.bound-b.bound);const target=Math.ceil(count*q),bucket=buckets.find(x=>x.value>=target);return bucket&&Number.isFinite(bucket.bound)?bucket.bound*1000:null;}
const finalTickCounters={count:metricValue("isles_tick_duration_seconds_count"),sum:metricValue("isles_tick_duration_seconds_sum")};
const tickMeasurementWindowSeconds=(performance.now()-tickMeasurementStartedAt)/1000;
const tc=finalTickCounters.count-tickMeasurementStart.count,ts=finalTickCounters.sum-tickMeasurementStart.sum;
if(!Number.isInteger(tc)||tc<=0||!Number.isFinite(ts)||ts<0||!Number.isFinite(tickMeasurementWindowSeconds)||tickMeasurementWindowSeconds<=0)throw Error("Invalid window-bounded server tick measurements");
const tickRateHz=tc/tickMeasurementWindowSeconds;
const serverMetrics={postgresServerVersion:Number(process.env.POSTGRES_SERVER_VERSION_NUM??0),tickCount:tc,tickMeasurementWindowSeconds,tickRateHz,averageTickMs:tc>0?ts*1000/tc:null,tickP95Ms:histogramQuantileMs("isles_tick_duration_seconds",0.95),tickP99Ms:histogramQuantileMs("isles_tick_duration_seconds",0.99),residentMemoryBytes:metricValue("isles_process_resident_memory_bytes"),heapUsedBytes:metricValue("isles_process_heap_used_bytes"),cpuUserSeconds:metricValue("isles_process_cpu_user_seconds_total"),cpuSystemSeconds:metricValue("isles_process_cpu_system_seconds_total"),httpRequestsTotal:metricValue("isles_http_requests_total"),httpErrorsTotal:metricValue("isles_http_errors_total"),networkBytesSent:scenarios.reduce((s,x)=>s+x.websocket.networkBytesSent,0),networkBytesReceived:scenarios.reduce((s,x)=>s+x.websocket.networkBytesReceived,0)};
const finalResult={event:"sustained_load_complete",durationMs,scenarios,loadTestScenarios,domainScenarios,serverMetrics,clientMetrics:{status:"not_measured_in_headless_ci",reason:"Physical-device FPS/frame-time/GPU evidence requires the Android/iOS matrix in Master Build Prompt section 94."}};
writeFileSync("performance-results.json",JSON.stringify(finalResult,null,2));console.log(JSON.stringify(finalResult));
