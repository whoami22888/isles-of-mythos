import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("PostgreSQL wait sampler starts and stops host/cgroup I/O telemetry", async () => {
  const source = await readFile(new URL("./sample-postgres-waits.mjs", import.meta.url), "utf8");
  assert.ok(source.includes('import { startHostIoTelemetry } from "./host-io-telemetry.mjs";'));
  assert.ok(source.includes("const hostIoTelemetry = await startHostIoTelemetry();"));
  assert.ok(source.includes("await Promise.all([db.end(), hostIoTelemetry.stop()]);"));
});
