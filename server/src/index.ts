import { buildApp } from "./app.js";
import { config } from "./config.js";
import { log } from "./logger.js";

const app = await buildApp();

try {
  await app.listen({ host: config.host, port: config.port });
  log("server_started", { host: config.host, port: config.port });
} catch (error) {
  log("server_start_failed", {
    message: error instanceof Error ? error.message : String(error),
  });
  process.exitCode = 1;
}
