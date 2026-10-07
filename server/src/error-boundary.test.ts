import { describe, expect, it } from "vitest";
import type { Pool } from "pg";
import { buildApp } from "./app.js";

const unavailableQuery = () =>
  Promise.reject(new Error("DATABASE_UNAVAILABLE"));

function unavailableDb(): Pool {
  return {
    query: unavailableQuery,
  } as unknown as Pool;
}

describe("external boundary error handling", () => {
  it("returns 401 for an unauthenticated shop request", async () => {
    const app = await buildApp({ db: unavailableDb() });
    try {
      const response = await app.inject({
        method: "POST",
        url: "/shop/purchase",
        payload: { itemId: "resource.wood", quantity: 1 },
      });

      expect(response.statusCode).toBe(401);
      expect(response.json()).toMatchObject({
        error: "UNAUTHORIZED",
        message: "Invalid credentials",
      });
    } finally {
      await app.close();
    }
  });

  it("returns a structured readiness failure when the database is unavailable", async () => {
    const app = await buildApp({ db: unavailableDb() });
    try {
      const response = await app.inject({
        method: "GET",
        url: "/ready",
      });

      expect(response.statusCode).toBe(503);
      expect(response.json()).toMatchObject({
        status: "not_ready",
        database: "unavailable",
      });
    } finally {
      await app.close();
    }
  });

  it("returns a safe 500 response for an unhandled HTTP failure", async () => {
    const app = await buildApp({ db: unavailableDb() });
    app.get("/__error-boundary-test", () => {
      throw new Error("DATABASE_UNAVAILABLE");
    });
    try {
      const response = await app.inject({
        method: "GET",
        url: "/__error-boundary-test",
      });

      expect(response.statusCode).toBe(500);
      expect(response.json()).toEqual({
        error: "INTERNAL_SERVER_ERROR",
        message: "Internal server error",
      });
    } finally {
      await app.close();
    }
  });

  it("rejects malformed request data at the HTTP boundary", async () => {
    const app = await buildApp({ db: unavailableDb() });
    try {
      const response = await app.inject({
        method: "POST",
        url: "/auth/register",
        payload: {
          username: "invalid",
          email: "not-an-email",
          password: "short",
        },
      });

      expect(response.statusCode).toBe(400);
    } finally {
      await app.close();
    }
  });
});
