import { Pool } from "pg";
import { config } from "./config.js";

export function createDbPool(): Pool {
  const isTest = config.environment === "test";
  return new Pool({
    connectionString: config.databaseUrl,
    max: isTest ? 4 : 10,
    idleTimeoutMillis: isTest ? 1000 : 30000,
    connectionTimeoutMillis: 3000,
    allowExitOnIdle: isTest,
  });
}
