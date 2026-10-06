import { createHmac } from "node:crypto";
import { WebSocket } from "ws";

const baseUrl = process.env.LOADTEST_BASE_URL ?? "http://127.0.0.1:3000";
const wsUrl = `${baseUrl.replace(/^http/, "ws")}/ws`;
const durationMs = Number(process.env.LOADTEST_DURATION_MS ?? 10000);
const httpRequests = Number(process.env.LOADTEST_HTTP_REQUESTS ?? 100);
const levels = [1, 50, 250, 1000];
const secret = process.env.JWT_SECRET ?? "loadtest-secret";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function userIdFor(index) {
  const hex = createHmac("sha256", "isles-of-mythos-loadtest").update(String(index)).digest("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-8${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

function tokenFor(index) {
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({ sub: userIdFor(index), username: `loadtest_${index}`, iat: Math.floor(Date.now() / 1000) })).toString("base64url");
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

async function wsLoad(playerCount) {
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

            socket.once("message", (authRaw) => {
              try {
                const auth = JSON.parse(authRaw.toString());
                if (auth.type === "auth_ok") {
                  authenticated++;
                  latencies.push(performance.now() - started);
                } else {
                  errors++;
                }
              } catch {
                errors++;
              }
              remaining--;
              finish();
            });

            socket.send(JSON.stringify({ type: "auth", token: tokenFor(index) }));
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
    pings,
    pongs,
    pingSuccessRate,
    p50Ms: percentile(latencies, 0.5),
    p95Ms: percentile(latencies, 0.95),
    p99Ms: percentile(latencies, 0.99),
  };
}

const scenarios = [];

for (const players of levels) {
  const result = {
    players,
    http: await httpLoad(),
    websocket: await wsLoad(players),
  };
  if (result.http.errors !== 0) {
    throw new Error(`HTTP load failed at ${players} players: ${result.http.errors} errors`);
  }
  scenarios.push(result);
  console.log(JSON.stringify(result));
}

console.log(JSON.stringify({ event: "sustained_load_complete", durationMs, scenarios }));
