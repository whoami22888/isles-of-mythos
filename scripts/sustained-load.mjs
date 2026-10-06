import { createHmac } from "node:crypto";
import { WebSocket } from "ws";
import pg from "pg";

const baseUrl = process.env.LOADTEST_BASE_URL ?? "http://127.0.0.1:3000";
const wsUrl = `${baseUrl.replace(/^http/, "ws")}/ws`;
const durationMs = Number(process.env.LOADTEST_DURATION_MS ?? 10000);
const httpRequests = Number(process.env.LOADTEST_HTTP_REQUESTS ?? 100);
const levels = [1, 50, 250, 1000];
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

