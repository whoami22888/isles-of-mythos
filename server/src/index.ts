import { buildApp } from "./app.js";
import { config } from "./config.js";
import { log } from "./logger.js";

// Anti-cheat detection state is shared through Redis only when REDIS_URL is configured explicitly; evidence is
// always persisted to PostgreSQL in the running server.
const app = await buildApp({
  antiCheatRedisUrl: process.env.REDIS_URL?.trim() ? config.redisUrl : undefined,
  persistAntiCheatEvidence: true,
});

try {
  await app.listen({ host: config.host, port: config.port });
  log("server_started", { host: config.host, port: config.port });
} catch (error) {
  log("server_start_failed", {
    message: error instanceof Error ? error.message : String(error),
  });
  process.exitCode = 1;
}
