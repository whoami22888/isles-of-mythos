import test from "node:test";
import assert from "node:assert/strict";
import {
  counterDelta, deltaDevices, deltaPressure, parseCgroup2Mount, parseCgroupIoStat,
  parseDiskstats, parseDockerPostgresContainers, parsePressure, parseUnifiedCgroupPath,
  resolveCgroupDirectory, startHostIoTelemetry,
} from "./host-io-telemetry.mjs";

test("diskstats uses major:minor identity and exact counters", () => {
  const value = parseDiskstats("8 0 sda 1 2 3 4 5 6 900719925474099312345 8 2 10 11 12 13 14 15 16 17");
  assert.equal(value["8:0"].name, "sda");
  assert.equal(value["8:0"].counters.sectorsWritten, "900719925474099312345");
  assert.equal(value["8:0"].gauges.inProgress, "2");
  assert.equal(value["8:0"].counters.flushMs, "17");
  assert.throws(() => parseDiskstats("8 0 sda 1 2"), /invalid_diskstats_row/);
});

test("pressure totals and cgroup I/O counters remain exact integers", () => {
  const pressure = parsePressure("some avg10=0.12 avg60=0.08 avg300=0.03 total=900719925474099312345\nfull avg10=0 avg60=0 avg300=0 total=12");
  assert.equal(pressure.some.totalUs, "900719925474099312345");
  assert.equal(pressure.full.avg10, 0);
  const io = parseCgroupIoStat("8:0 rbytes=900719925474099312345 wbytes=20 rios=3 wios=4 dbytes=0 dios=0");
  assert.equal(io["8:0"].rbytes, "900719925474099312345");
  assert.throws(() => parsePressure("some avg10=0 total=1"), /incomplete_pressure_scope/);
  assert.throws(() => parseCgroupIoStat("bad rbytes=1"), /invalid_cgroup_io_row/);
});

test("cgroup v2 mount and process paths resolve safely", () => {
  const mount = parseCgroup2Mount("29 23 0:26 /docker.slice /sys/fs/cgroup\\040v2 rw - cgroup2 cgroup rw");
  assert.deepEqual(mount, { root: "/docker.slice", mountPoint: "/sys/fs/cgroup v2" });
  assert.equal(parseUnifiedCgroupPath("0::/docker.slice/job/runner\n"), "/docker.slice/job/runner");
  assert.equal(resolveCgroupDirectory(mount, "/docker.slice/job/runner"), "/sys/fs/cgroup v2/job/runner");
  assert.equal(resolveCgroupDirectory(mount, "/user.slice/other"), null);
  assert.equal(parseUnifiedCgroupPath("2:cpu:/legacy"), null);
});

test("counter deltas preserve precision and report resets or missing baselines", () => {
  assert.deepEqual(counterDelta("900719925474099312345", "900719925474099312355"), { value: "10" });
  assert.deepEqual(counterDelta("100", "90"), { value: null, reason: "counter_reset" });
  assert.deepEqual(counterDelta(null, "90"), { value: null, reason: "baseline_unavailable" });
  assert.deepEqual(deltaDevices({ "8:0": { rbytes: "10" } }, { "8:0": { rbytes: "15" }, "8:16": { rbytes: "1" } }), {
    "8:0": { rbytes: { value: "5" } },
    "8:16": { rbytes: { value: null, reason: "baseline_unavailable" } },
  });
  assert.deepEqual(deltaPressure({ some: { totalUs: "10" } }, { some: { totalUs: "20" } }), { some: { value: "10" } });
});

test("Docker discovery refuses ambiguous PostgreSQL containers", () => {
  assert.deepEqual(parseDockerPostgresContainers("abc123456789|cgr.dev/chainguard/postgres@sha256:deadbeef|postgres"), {
    status: "available", containerId: "abc123456789",
  });
  assert.equal(parseDockerPostgresContainers("abc123456789|postgres:18|pg-a\ndef987654321|postgres:18|pg-b").reason, "postgres_container_ambiguous");
  assert.equal(parseDockerPostgresContainers("abc123456789|redis:7|redis").reason, "postgres_container_not_found");
});

test("unavailable cgroup sources are explicit and never reported as zero", async () => {
  const records = [];
  const files = new Map([
    ["/proc/self/mountinfo", "29 23 0:26 / /sys/fs/cgroup rw - cgroup2 cgroup rw"],
    ["/proc/self/cgroup", "0::/runner"],
    ["/proc/123/cgroup", "0::/postgres"],
    ["/proc/diskstats", "8 0 sda 1 2 3 4 5 6 7 8 0 10 11 12 13 14 15 16"],
    ["/proc/pressure/io", "some avg10=0 avg60=0 avg300=0 total=0\nfull avg10=0 avg60=0 avg300=0 total=0"],
  ]);
  const readText = async file => {
    if (files.has(file)) return files.get(file);
    const error = new Error("missing"); error.code = "ENOENT"; throw error;
  };
  const runCommand = (_command, args) => args[0] === "ps"
    ? { status: 0, stdout: "abc123456789|cgr.dev/chainguard/postgres@sha256:deadbeef|postgres" }
    : { status: 0, stdout: "123" };
  const sampler = await startHostIoTelemetry({
    emit: record => records.push(record), readText, runCommand,
    now: (() => { let value = 0; return () => ++value; })(),
    wallTime: () => "2026-11-22T00:00:00.000Z",
  });
  await sampler.stop();
  assert.equal(records.length, 1);
  assert.equal(records[0].host.diskstats.status, "available");
  assert.equal(records[0].cgroups.runner.ioStat.status, "unavailable");
  assert.equal(records[0].cgroups.runner.ioStat.reason, "ENOENT");
  assert.equal(records[0].cgroups.postgresService.ioPressure.status, "unavailable");
  assert.equal(records[0].cgroups.postgresService.ioPressure.reason, "ENOENT");
  assert.equal("current" in records[0].cgroups.runner.ioStat, false);
});
