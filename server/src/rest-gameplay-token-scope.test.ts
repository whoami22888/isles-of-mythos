import Fastify from "fastify";
import fastifyJwt from "@fastify/jwt";
import { describe, expect, it } from "vitest";
import type { Pool } from "pg";
import { registerCreatureResearchRoutes } from "./creature-research-routes.js";
import type { PlayerStore } from "./player.js";

const SECRET = "rest-scope-test-secret-0123456789abcdef0123";
const USER = "fc461aaf-9fe0-4f94-b090-0a6d72441711";

// Player REST routes must accept only player access tokens, like the WebSocket
// gate (isGameplayAccessToken). Admin and refresh JWTs are not gameplay sessions.
async function fixture() {
  let reachedStore = 0;
  const db = { query: () => { reachedStore++; return Promise.resolve({ rows: [], rowCount: 0 }); } } as unknown as Pool;
  const players = {
    ensureProfile: () => { reachedStore++; return Promise.resolve(); },
    runExclusive: (_id: string, fn: () => unknown) => { reachedStore++; return fn(); },
  } as unknown as PlayerStore;
  const app = Fastify();
  await app.register(fastifyJwt, { secret: SECRET });
  registerCreatureResearchRoutes(app, db, players);
  await app.ready();
  const sign = (claims: Record<string, unknown>) => app.jwt.sign({ sub: USER, username: "p", ...claims }, { expiresIn: "5m" });
  return { app, sign, reached: () => reachedStore };
}

describe("player REST routes reject non-gameplay tokens", () => {
  for (const url of ["/creature-research", "/creature-training"]) {
    it(`${url}: admin and refresh tokens get 401 before any store access`, async () => {
      const { app, sign, reached } = await fixture();
      for (const claims of [{ role: "admin", typ: "access" }, { role: "player", typ: "refresh" }, { role: "moderator" }]) {
        const res = await app.inject({ method: "GET", url, headers: { authorization: `Bearer ${sign(claims)}` } });
        expect(res.statusCode, JSON.stringify(claims)).toBe(401);
      }
      expect(reached()).toBe(0);
    });

    it(`${url}: a player access token passes the gate`, async () => {
      const { app, sign, reached } = await fixture();
      const res = await app.inject({ method: "GET", url, headers: { authorization: `Bearer ${sign({ role: "player", typ: "access" })}` } });
      expect(res.statusCode).not.toBe(401);
      expect(reached()).toBeGreaterThan(0);
    });
  }
});
