import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { config } from "./config.js";

function base64url(value: string): string {
  return Buffer.from(value).toString("base64url");
}

function signHs384(payload: Record<string, unknown>): string {
  const header = base64url(JSON.stringify({ alg: "HS384", typ: "JWT" }));
  const body = base64url(JSON.stringify(payload));
  const input = header + "." + body;
  const signature = createHmac("sha384", config.jwtSecret).update(input).digest("base64url");
  return input + "." + signature;
}

describe("security hardening", () => {
  it("rejects JWTs signed with an algorithm outside the configured HS256 allow-list", async () => {
    const app = await buildApp();

    try {
      const token = signHs384({
        sub: "00000000-0000-4000-8000-000000000001",
        username: "algorithm-test",
        exp: Math.floor(Date.now() / 1000) + 300,
      });

      const response = await app.inject({
        method: "GET",
        url: "/auth/me",
        headers: { authorization: `Bearer ${token}` },
      });

      expect(response.statusCode).toBe(401);
      expect(response.json()).toMatchObject({ error: "UNAUTHORIZED" });
    } finally {
      await app.close();
    }
  });

  it("does not pass unexpected authentication fields into the registration handler", async () => {
    const app = await buildApp();

    try {
      const response = await app.inject({
        method: "POST",
        url: "/auth/register",
        payload: {
          username: "security_schema_test_2",
          email: "security_schema_test_2@example.com",
          password: "Correct-Horse-Battery-9",
          role: "admin",
        },
      });

      expect(response.statusCode).toBe(201);
      const body = JSON.parse(response.payload) as { user?: Record<string, unknown> };
      expect(body).toMatchObject({
        user: expect.not.objectContaining({ role: expect.anything() }),
      });
    } finally {
      await app.close();
    }
  });
});
