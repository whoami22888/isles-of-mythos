import { Pool } from "pg";
import { config } from "./config.js";

export function createDbPool(): Pool {
  return new Pool({
    connectionString: config.databaseUrl,
    // Gameplay mutations use one transaction connection plus a reload query.
    // The 50-player acceptance workload otherwise queues mutations behind ten
    // connections and breaches the frozen 150 ms gameplay p95 SLO.
    max: config.databasePoolMax,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 3_000,
  });
}
