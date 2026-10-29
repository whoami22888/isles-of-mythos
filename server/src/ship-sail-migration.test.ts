import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import pg from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

// Migration 040 up -> down -> up on a disposable database, so the rollback is proven rather than assumed.
// A scratch database keeps the shared integration database (used by parallel test files) untouched.
const ADMIN_URL = process.env.DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:5432/isles_test";
const scratchName = "isles_mig040_" + randomBytes(4).toString("hex");
const scratchUrl = (() => { const u = new URL(ADMIN_URL); u.pathname = "/" + scratchName; return u.toString(); })();
const bin = new URL("../../node_modules/.bin/node-pg-migrate", import.meta.url).pathname;
const run = (...args: string[]): string =>
  execFileSync(bin, [...args, "-m", "migrations"], { cwd: new URL("..", import.meta.url).pathname, env: { ...process.env, DATABASE_URL: scratchUrl }, encoding: "utf8" });

async function columnInfo(): Promise<Array<{ is_nullable: string; column_default: string | null; data_type: string }>> {
  const c = new pg.Client({ connectionString: scratchUrl });
  await c.connect();
  try {
    return (await c.query<{ is_nullable: string; column_default: string | null; data_type: string }>(
      "SELECT is_nullable, column_default, data_type FROM information_schema.columns WHERE table_name='player_ships' AND column_name='last_sailed_at'")).rows;
  } finally { await c.end(); }
}

describe("migration 040 player_ships.last_sailed_at", () => {
  beforeAll(async () => {
    const admin = new pg.Client({ connectionString: ADMIN_URL });
    await admin.connect();
    try { await admin.query(`CREATE DATABASE ${scratchName}`); } finally { await admin.end(); }
  });
  afterAll(async () => {
    const admin = new pg.Client({ connectionString: ADMIN_URL });
    await admin.connect();
    try { await admin.query(`DROP DATABASE IF EXISTS ${scratchName} WITH (FORCE)`); } finally { await admin.end(); }
  });

  it("applies up, rolls back down cleanly, and re-applies up", async () => {
    run("up");
    const up = await columnInfo();
    expect(up).toHaveLength(1);
    expect(up[0]).toMatchObject({ is_nullable: "NO", data_type: "timestamp with time zone" });
    expect(up[0].column_default).toMatch(/now\(\)/i);

    run("down", "1");
    expect(await columnInfo()).toHaveLength(0);

    run("up");
    expect(await columnInfo()).toHaveLength(1);
  }, 120_000);
});
