import { Pool } from "pg";
import { config } from "./config.js";

export function createDbPool(): Pool {
  return new Pool({
    connectionString: config.databaseUrl,
    max: 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 3_000,
  });
}
