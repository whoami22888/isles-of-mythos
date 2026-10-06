import { createHash } from "node:crypto";
import { WebSocket } from "ws";

const baseUrl = process.env.LOADTEST_BASE_URL ?? "http://127.0.0.1:3000";
const wsUrl = baseUrl.replace(/^http/, "ws");
const durationMs = Number(process.env.LOADTEST_DURATION_MS ?? 10_000);
const httpRequests = Number(process.env.LOADTEST_HTTP_REQUESTS ?? 100);
const levels = [1, 50, 250, 1_000];
const secret = process.env.JWT_SECRET ?? "loadtest-secret-change-me";

function sleep(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }

function tokenFor(index) {
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({ sub: `loadtest-${index}`, iat: Math.floor(Date.now() / 1000) })).toString("base64url");
  const data = `${header}.${payload}`;
  const signature = createHash("sha256").update(secret + data).digest("base64url");
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
  const started = Date.now();
  let completed = 0;
  const workers = Math.min(20, httpRequests);
  let next = 0;
  async function worker() {
    while (true) {
      const i = next++;
      if (i >= httpRequests) return;
      const t = performance.now();
      try {
        const response = await fetch(`${baseUrl}/health`);
        if (!response.ok) errors++;
        else await response.text();
      } catch {
        errors++;
      } finally {
        latencies.push(performance.now() - t);
        completed++;
      }
    }
  }
  await Promise.all(Array.from({ length: workers }, worker));
  return {
    requests: completed,
    errors,
    durationMs: Date.now() - started,
    requestsPerSecond: completed / Math.max(0.001, (Date.now() - started) / 1000),
    p50Ms: percentile(latencies, 0.50),
    p95Ms: percentile(latencies, 0.95),
    p99Ms: percentile(latencies, 0.99),
  };
}

async function wsLoad(playerCount) {
  const sockets = [];
  const latencies = [];
  let connected = 0;
  let authenticated = 0;
  let errors = 0;
  const openStarted = Date.now();

  await new Promise((resolve, reject) => {
    let settled = false;
    let remaining = playerCount;
    const fail = (error) => {
      if (!settled) { settled = true; reject(error); }
    };
    for (let i = 0; i < playerCount; i++) {
      const socket = new WebSocket(wsUrl);
      sockets.push(socket);
      const started = performance.now();
      socket.on("open", () => {
        connected++;
        socket.once("message", (raw) => {
          try {
            const message = JSON.parse(raw.toString());
            if (message.type === "server_ready") {
              const token = tokenFor(i);
              socket.once("message", (authRaw) => {
                try {
                  const auth = JSON.parse(authRaw.toString());
                  if (auth.type === "auth_ok") {
                    authenticated++;
                    latencies.push(performance.now() - started);
                  } else {
                    errors++;
                  }
                } catch { errors++; }
                remaining--;
                if (remaining === 0 && !settled) { settled = true; resolve(); }
              });
              socket.send(JSON.stringify({ type: "auth", token }));
            } else {
              errors++;
              remaining--;
              if (remaining === 0 && !settled) { settled = true; resolve(); }
            }
          } catch {
            errors++;
            remaining--;
            if (remaining === 0 && !settled) { settled = true; resolve(); }
          }
        });
      });
      socket.on("error", () => {
        errors++;
        remaining--;
        if (remaining === 0 && !settled) { settled = true; resolve(); }
      });
    }
    setTimeout(() => fail(new Error(`Timed out establishing ${playerCount} WebSockets`)), Math.max(60_000, durationMs * 6));
  });

  const connectedDuration = Date.now() - openStarted;
  const pingEnd = Date.now() + durationMs;
  let pings = 0;
  let pongs = 0;
  while (Date.now() < pingEnd) {
    const active = sockets.filter((socket) => socket.readyState === WebSocket.OPEN);
    const pingStarted = performance.now();
    await Promise.all(active.map((socket) => new Promise((resolve) => {
      const timer = setTimeout(() => resolve(), 2_000);
      socket.once("message", (raw) => {
        clearTimeout(timer);
        try {
          const message = JSON.parse(raw.toString());
          if (message.type === "pong") {
            pongs++;
            latencies.push(performance.now() - pingStarted);
          }
        } catch {}
        resolve();
      });
      socket.send(JSON.stringify({ type: "ping" }));
      pings++;
    })));
    await sleep(250);
  }

  for (const socket of sockets) socket.close();
  await sleep(100);

  return {
    requestedPlayers: playerCount,
    connected,
    authenticated,
    errors,
    establishmentMs: connectedDuration,
    pings,
    pongs,
    pingSuccessRate: pings ? pongs / pings : 0,
    p50Ms: percentile(latencies, 0.50),
    p95Ms: percentile(latencies, 0.95),
    p99Ms: percentile(latencies, 0.99),
  };
}

const results = [];
for (const players of levels) {
  const started = new Date().toISOString();
  const http = await httpLoad();
  const websocket = await wsLoad(players);
  results.push({ players, started, http, websocket });
  console.log(JSON.stringify(results.at(-1)));
}

console.log(JSON.stringify({
  event: "sustained_load_complete",
  baseUrl,
  durationMs,
  scenarios: results,
}));
