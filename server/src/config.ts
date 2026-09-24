const DEFAULT_PORT = 3000;
const DEFAULT_CORS_ORIGIN = "http://localhost:5173";

function parsePort(value: string | undefined): number {
  if (value === undefined || value.trim() === "") return DEFAULT_PORT;
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("SERVER_PORT must be an integer between 1 and 65535");
  }
  return port;
}

function parseEnvironment(value: string | undefined): "development" | "test" | "production" {
  const environment = value ?? "development";
  if (environment === "development" || environment === "test" || environment === "production") {
    return environment;
  }
  throw new Error("ENVIRONMENT must be development, test, or production");
}

function parseCorsOrigin(value: string | undefined, environment: "development" | "test" | "production"): string {
  if (value && value.trim() !== "") return value.trim();
  if (environment === "production") {
    throw new Error("CORS_ORIGIN is required in production");
  }
  return DEFAULT_CORS_ORIGIN;
}

const environment = parseEnvironment(process.env.ENVIRONMENT);

if (environment === "production" && !process.env.JWT_SECRET) {
  throw new Error("JWT_SECRET is required in production");
}

export const config = {
  host: process.env.SERVER_HOST ?? "0.0.0.0",
  port: parsePort(process.env.SERVER_PORT),
  environment,
  databaseUrl: process.env.DATABASE_URL ?? "postgres://postgres:postgres@localhost:5432/isles",
  redisUrl: process.env.REDIS_URL ?? "redis://localhost:6379",
  jwtSecret: process.env.JWT_SECRET ?? "development-only-secret-change-me",
  corsOrigin: parseCorsOrigin(process.env.CORS_ORIGIN, environment),
  websocketMaxPayloadBytes: 64 * 1024,
} as const;
