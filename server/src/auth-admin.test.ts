import Fastify from "fastify";
import argon2 from "argon2";
import { describe, expect, it } from "vitest";
import type { Pool } from "pg";
import { registerAuthRoutes } from "./auth.js";

const ADMIN_ID = "e3057a50-9771-41ca-ac06-f2445ea77111";
const PLAYER_ID = "fc461aaf-9fe0-4f94-b090-0a6d72441711";
const PASSWORD = "Passphrase-For-Test-2026";

async function fixture() {
  const secret = await argon2.hash(PASSWORD, { type: argon2.argon2id });
  const users = [
    { id: ADMIN_ID, username: "approved_operator", email: "operator@example.test", password_hash: secret },
    { id: PLAYER_ID, username: "normal_player", email: "player@example.test", password_hash: secret },
  ];
  const query = (sql: string, values: unknown[]) => {
    if (sql.startsWith("SELECT id, username, email, password_hash")) {
      const user = users.find(u => u.username === values[0] || u.email === values[0]);
      return Promise.resolve({ rows: user ? [user] : [], rowCount: user ? 1 : 0 });
    }
    if (sql.startsWith("SELECT id, username, email FROM users WHERE id")) {
      const user = users.find(u => u.id === values[0]);
      return Promise.resolve({ rows: user ? [{ id: user.id, username: user.username, email: user.email }] : [], rowCount: user ? 1 : 0 });
    }
    if (sql.startsWith("SELECT id FROM users WHERE username")) {
      return Promise.resolve({ rows: [], rowCount: 0 });
    }
    if (sql.startsWith("INSERT INTO users")) {
      const user = { id: "a7c054b6-e5b7-4d4b-9d31-3d75f64286ce", username: values[0] as string, email: values[1] as string, password_hash: values[2] as string };
      users.push(user);
      return Promise.resolve({ rows: [{ id: user.id, username: user.username, email: user.email }], rowCount: 1 });
    }
    throw new Error("Unexpected SQL in auth fixture: " + sql);
  };
  const app = Fastify();
  await registerAuthRoutes(app, { query } as unknown as Pool, { adminUserIds: new Set([ADMIN_ID]) });
  return app;
}

describe("scoped player registration and admin authentication", () => {
  it("registers new players without elevating user-supplied roles", async () => {
    const app = await fixture();
    try {
      const attempt = await app.inject({ method: "POST", url: "/auth/register", payload: {
        username: "role_attack", email: "role_attack@example.test", password: PASSWORD, role: "admin",
      } });
      expect(attempt.statusCode).toBe(400);
      const created = await app.inject({ method: "POST", url: "/auth/register", payload: {
        username: "new_player", email: "new_player@example.test", password: PASSWORD,
      } });
      expect(created.statusCode).toBe(201);
      const token = created.json<{ accessToken: string }>().accessToken;
      expect(token).toBeTruthy();
      const adminMe = await app.inject({ method: "GET", url: "/auth/admin/me", headers: { authorization: "Bearer " + token } });
      expect(adminMe.statusCode).toBe(401);
    } finally { await app.close(); }
  });

  it("rejects ordinary players and bad passwords on the admin-only login", async () => {
    const app = await fixture();
    try {
      const user = await app.inject({ method: "POST", url: "/auth/admin/login", payload: { identifier: "normal_player", password: PASSWORD } });
      expect(user.statusCode).toBe(401);
      const wrong = await app.inject({ method: "POST", url: "/auth/admin/login", payload: { identifier: "approved_operator", password: "wrong" } });
      expect(wrong.statusCode).toBe(401);
      expect(user.json()).toMatchObject({ error: "UNAUTHORIZED" });
      expect(wrong.json()).toMatchObject({ error: "UNAUTHORIZED" });
    } finally { await app.close(); }
  });

  it("requires an admin-scoped JWT AND configured user UUID for admin access", async () => {
    const app = await fixture();
    try {
      const playerMode = await app.inject({ method: "POST", url: "/auth/login", payload: { identifier: "approved_operator", password: PASSWORD } });
      expect(playerMode.statusCode).toBe(200);
      const playerToken = playerMode.json<{ accessToken: string }>().accessToken;
      const playerMe = await app.inject({ method: "GET", url: "/auth/admin/me", headers: { authorization: "Bearer " + playerToken } });
      expect(playerMe.statusCode).toBe(401);

      const login = await app.inject({ method: "POST", url: "/auth/admin/login", payload: { identifier: "approved_operator", password: PASSWORD } });
      expect(login.statusCode).toBe(200);
      expect(login.json<{ role: string }>().role).toBe("admin");
      const adminToken = login.json<{ accessToken: string }>().accessToken;
      const adminMe = await app.inject({ method: "GET", url: "/auth/admin/me", headers: { authorization: "Bearer " + adminToken } });
      expect(adminMe.statusCode).toBe(200);
      expect(adminMe.json()).toMatchObject({ role: "admin", user: { id: ADMIN_ID } });
    } finally { await app.close(); }
  });

  it("fails closed when no administrator IDs are provisioned", async () => {
    const app = Fastify();
    const secret = await argon2.hash(PASSWORD);
    const query = () => Promise.resolve({ rows: [{ id: ADMIN_ID, username: "approved_operator", email: "operator@example.test", password_hash: secret }], rowCount: 1 });
    try {
      await registerAuthRoutes(app, { query } as unknown as Pool, { adminUserIds: new Set() });
      const result = await app.inject({ method: "POST", url: "/auth/admin/login", payload: { identifier: "approved_operator", password: PASSWORD } });
      expect(result.statusCode).toBe(401);
    } finally { await app.close(); }
  });
});
