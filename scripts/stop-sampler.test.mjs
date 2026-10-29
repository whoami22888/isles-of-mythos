import { test } from "node:test";
import assert from "node:assert/strict";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { chmodSync, mkdtempSync, readFileSync, statSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const repo = resolve(import.meta.dirname, "..");
const sampleScript = join(repo, "scripts", "sample-metrics.sh");
const stopScript = join(repo, "scripts", "stop-sampler.sh");
const execFileAsync = promisify(execFile);
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

// A psql stand-in that is slow to return and then writes a line. If the sampler's shell is killed while this is
// still running, the line lands in the log after the stop completes: the late writer the evidence must not see.
const slowPsql = "#!/usr/bin/env bash\nsleep 2\necho LATE-PSQL-ROW\n";

test("stopping the sampler leaves the metrics log immutable once stop returns", async () => {
  const dir = mkdtempSync(join(tmpdir(), "sampler-"));
  const bin = join(dir, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "psql"), slowPsql);
  chmodSync(join(bin, "psql"), 0o755);

  // A stand-in for the server process: the sampler runs while this is alive.
  const server = spawn("sleep", ["120"], { stdio: "ignore" });
  writeFileSync(join(dir, "server.pid"), String(server.pid));
  const log = join(dir, "performance-system.log");
  const logFd = (await import("node:fs")).openSync(log, "w");

  const sampler = spawn("setsid", ["bash", sampleScript], {
    cwd: dir,
    stdio: ["ignore", logFd, logFd],
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, DATABASE_URL: "postgres://unused" },
  });
  writeFileSync(join(dir, "performance-sampler.pid"), String(sampler.pid));

  try {
    await sleep(500); // the sampler is now inside a slow psql call
    // Async, so Node reaps the killed sampler; a blocked event loop leaves it a zombie that kill -0 still sees.
    await execFileAsync("bash", [stopScript, join(dir, "performance-sampler.pid"), "10"], { cwd: dir });
    const sizeAtStop = statSync(log).size;
    await sleep(2_500); // long enough for a surviving psql to write its row
    const finalSize = statSync(log).size;
    assert.equal(finalSize, sizeAtStop, "log grew after the sampler was stopped");
    assert.equal(readFileSync(log, "utf8").includes("LATE-PSQL-ROW"), false);
  } finally {
    server.kill("SIGKILL");
    try { process.kill(sampler.pid, "SIGKILL"); } catch { /* already stopped */ }
  }
});
