import argon2 from "argon2";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { Pool } from "pg";
import { config } from "./config.js";

interface RegisterBody {
  username: string;
  email: string;
  password: string;
}

interface LoginBody {
  identifier: string;
  password: string;
}

interface UserRow {
  id: string;
  username: string;
  email: string;
  password_hash: string;
}

const credentialsSchema = {
  type: "object",
  additionalProperties: false,
  required: ["username", "email", "password"],
  properties: {
    username: { type: "string", minLength: 3, maxLength: 32, pattern: "^[A-Za-z0-9_]+$" },
    email: { type: "string", minLength: 5, maxLength: 254, format: "email" },
    password: { type: "string", minLength: 12, maxLength: 128 },
  },
} as const;

function normalizeUsername(username: string): string {
  return username.trim().toLowerCase();
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function invalidCredentials(reply: FastifyReply) {
  return reply.code(401).send({
    error: "UNAUTHORIZED",
    message: "Invalid credentials",
  });
}

async function signAccessToken(
  reply: FastifyReply,
  user: Pick<UserRow, "id" | "username">,
): Promise<string> {
  return reply.jwtSign(
    { sub: user.id, username: user.username },
    { expiresIn: "15m" },
  );
}

export async function registerAuthRoutes(app: FastifyInstance, db: Pool): Promise<void> {
  await app.register(import("@fastify/jwt"), {
    secret: config.jwtSecret,
    sign: {
      algorithm: "HS256",
      expiresIn: "15m",
    },
    verify: {
      algorithms: ["HS256"],
    },
  });

  app.post<{ Body: RegisterBody }>(
    "/auth/register",
    {
      config: {
        rateLimit: {
          max: 10,
          timeWindow: "1 minute",
        },
      },
      schema: {
        tags: ["authentication"],
        body: credentialsSchema,
        response: {
          201: {
            type: "object",
            required: ["accessToken", "user"],
            properties: {
              accessToken: { type: "string" },
              user: {
                type: "object",
                required: ["id", "username", "email"],
                properties: {
                  id: { type: "string", format: "uuid" },
                  username: { type: "string" },
                  email: { type: "string", format: "email" },
                },
              },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const username = normalizeUsername(request.body.username);
      const email = normalizeEmail(request.body.email);

      const existing = await db.query<{ id: string }>(
        "SELECT id FROM users WHERE username = $1 OR email = $2 LIMIT 1",
        [username, email],
      );

      if (existing.rowCount !== 0) {
        return reply.code(409).send({
          error: "CONFLICT",
          message: "Username or email is already registered",
        });
      }

      const passwordHash = await argon2.hash(request.body.password, {
        type: argon2.argon2id,
      });

      try {
        const result = await db.query<Pick<UserRow, "id" | "username" | "email">>(
          "INSERT INTO users (username, email, password_hash) VALUES ($1, $2, $3) RETURNING id, username, email",
          [username, email, passwordHash],
        );

        const user = result.rows[0];
        const accessToken = await signAccessToken(reply, user);

        return reply.code(201).send({ accessToken, user });
      } catch (error) {
        if (isUniqueViolation(error)) {
          return reply.code(409).send({
            error: "CONFLICT",
            message: "Username or email is already registered",
          });
        }
        throw error;
      }
    },
  );

  app.post<{ Body: LoginBody }>(
    "/auth/login",
    {
      config: {
        rateLimit: {
          max: 10,
          timeWindow: "1 minute",
        },
      },
      schema: {
        tags: ["authentication"],
        body: {
          type: "object",
          additionalProperties: false,
          required: ["identifier", "password"],
          properties: {
            identifier: { type: "string", minLength: 3, maxLength: 254 },
            password: { type: "string", minLength: 1, maxLength: 128 },
          },
        },
      },
    },
    async (request, reply) => {
      const identifier = request.body.identifier.trim().toLowerCase();
      const result = await db.query<UserRow>(
        "SELECT id, username, email, password_hash FROM users WHERE username = $1 OR email = $1 LIMIT 1",
        [identifier],
      );

      const user = result.rows[0];
      if (!user || !(await argon2.verify(user.password_hash, request.body.password))) {
        return invalidCredentials(reply);
      }

      const accessToken = await signAccessToken(reply, user);
      return { accessToken, user: { id: user.id, username: user.username, email: user.email } };
    },
  );

  app.get(
    "/auth/me",
    {
      schema: {
        tags: ["authentication"],
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply) => {
      try {
        await request.jwtVerify();
      } catch {
        return invalidCredentials(reply);
      }

      const result = await db.query<Pick<UserRow, "id" | "username" | "email">>(
        "SELECT id, username, email FROM users WHERE id = $1 LIMIT 1",
        [request.user.sub],
      );

      const user = result.rows[0];
      if (!user) {
        return invalidCredentials(reply);
      }

      return { user };
    },
  );
}

function isUniqueViolation(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: unknown }).code === "23505"
  );
}
