import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { posix as path } from "node:path";

const diskFields = ["reads", "readsMerged", "sectorsRead", "readMs", "writes", "writesMerged", "sectorsWritten", "writeMs", "inProgress", "ioMs", "weightedIoMs", "discards", "discardsMerged", "sectorsDiscarded", "discardMs", "flushes", "flushMs"];
const ioFields = new Set(["rbytes", "wbytes", "rios", "wios", "dbytes", "dios"]);
const unavailable = reason => ({ status: "unavailable", reason });
const integer = value => {
  if (!/^\d+$/.test(value)) throw new Error("invalid_integer");
  return BigInt(value).toString();
};
const reasonOf = (error, fallback = "read_error") => error?.code || fallback;

export function parseDiskstats(text) {
  const result = {};
  for (const line of text.trim().split(/\r?\n/)) {
    if (!line) continue;
    const [majorText, minorText, name, ...values] = line.trim().split(/\s+/);
    const major = Number(majorText), minor = Number(minorText);
    if (!Number.isSafeInteger(major) || major < 0 || !Number.isSafeInteger(minor) || minor < 0 || !name || values.length < 11 || values.length > diskFields.length) throw new Error("invalid_diskstats_row");
    const id = major + ":" + minor;
    if (result[id]) throw new Error("duplicate_diskstats_device");
    const counters = {}, gauges = {};
    values.forEach((raw, index) => {
      const key = diskFields[index], value = integer(raw);
      if (key === "inProgress") gauges.inProgress = value;
      else counters[key] = value;
    });
    result[id] = { name, major, minor, counters, gauges };
  }
  if (!Object.keys(result).length) throw new Error("empty_diskstats");
  return result;
}

export function parsePressure(text) {
  const result = {};
  for (const line of text.trim().split(/\r?\n/)) {
    if (!line) continue;
    const [scope, ...pairs] = line.split(/\s+/);
    if (!["some", "full"].includes(scope) || result[scope]) throw new Error("invalid_pressure_scope");
    const values = {};
    for (const pair of pairs) {
      const [key, raw] = pair.split("=");
      if (key === "total") values.totalUs = integer(raw);
      else if (["avg10", "avg60", "avg300"].includes(key)) {
        const value = Number(raw);
        if (!Number.isFinite(value) || value < 0) throw new Error("invalid_pressure_average");
        values[key] = value;
      }
    }
    if (!["avg10", "avg60", "avg300", "totalUs"].every(key => key in values)) throw new Error("incomplete_pressure_scope");
    result[scope] = values;
  }
  if (!result.some) throw new Error("missing_pressure_some");
  return result;
}

export function parseCgroupIoStat(text) {
  const result = {};
  for (const line of text.trim().split(/\r?\n/)) {
    if (!line) continue;
    const [device, ...pairs] = line.split(/\s+/);
    if (!/^\d+:\d+$/.test(device) || result[device] || !pairs.length) throw new Error("invalid_cgroup_io_row");
    const counters = {};
    for (const pair of pairs) {
      const [key, raw] = pair.split("=");
      if (ioFields.has(key)) counters[key] = integer(raw);
    }
    if (!Object.keys(counters).length) throw new Error("missing_cgroup_io_counters");
    result[device] = counters;
  }
  if (!Object.keys(result).length) throw new Error("empty_cgroup_io_stat");
  return result;
}

export function parseUnifiedCgroupPath(text) {
  const line = text.split(/\r?\n/).find(value => value.startsWith("0::"));
  if (!line) return null;
  const value = path.normalize(line.slice(3).trim());
  return value.startsWith("/") ? value : null;
}

export function parseCgroup2Mount(text) {
  for (const line of text.split(/\r?\n/)) {
    const split = line.indexOf(" - ");
    if (split < 0) continue;
    const left = line.slice(0, split).split(" "), right = line.slice(split + 3).split(" ");
    if (right[0] !== "cgroup2" || left.length < 5) continue;
    const decode = value => value.replace(/\\([0-7]{3})/g, (_m, octal) => String.fromCharCode(parseInt(octal, 8)));
    return { root: path.normalize(decode(left[3])), mountPoint: path.normalize(decode(left[4])) };
  }
  return null;
}

export function resolveCgroupDirectory(mount, cgroupPath) {
  if (!mount || typeof cgroupPath !== "string" || !cgroupPath.startsWith("/")) return null;
  const relative = path.relative(path.normalize(mount.root), path.normalize(cgroupPath));
  if (relative === ".." || relative.startsWith("../") || path.isAbsolute(relative)) return null;
  const base = path.normalize(mount.mountPoint), candidate = path.normalize(path.join(base, relative));
  return candidate === base || candidate.startsWith(base + "/") ? candidate : null;
}

const DEFAULT_POSTGRES_IMAGE_DIGEST = "sha256:fb42fe07f31379928ffb2fcb9acb903eb40e7e821b562f16809a45bc86097289";

function isExpectedPostgresImage(image, expectedDigest = DEFAULT_POSTGRES_IMAGE_DIGEST) {
  if (typeof image !== "string" || !/^sha256:[0-9a-f]{64}$/i.test(expectedDigest)) return false;
  const match = /(?:^|\/)postgres@sha256:([0-9a-f]{64})$/i.exec(image.trim());
  return Boolean(match && `sha256:${match[1].toLowerCase()}` === expectedDigest.toLowerCase());
}

export function parseDockerPostgresContainers(text, expectedDigest = DEFAULT_POSTGRES_IMAGE_DIGEST) {
  const rows = text.trim().split(/\r?\n/).filter(Boolean).map(line => {
    const [id, image = "", name = ""] = line.split("|");
    return { id, image, name };
  }).filter(row => /^[a-f0-9]{12,64}$/i.test(row.id) && /postgres/i.test(row.image + " " + row.name));
  if (!rows.length) return unavailable("postgres_container_not_found");
  const pinned = rows.filter(row => isExpectedPostgresImage(row.image, expectedDigest));
  if (pinned.length === 1) return { status: "available", containerId: pinned[0].id };
  return unavailable(pinned.length === 0 && rows.length === 1
    ? "postgres_image_not_digest_pinned"
    : "postgres_container_ambiguous");
}

export function parseDockerPostgresInspect(text, expectedId, expectedDigest = DEFAULT_POSTGRES_IMAGE_DIGEST) {
  const [actualId = "", image = "", pidText = ""] = text.trim().split("|");
  if (!/^[a-f0-9]{64}$/i.test(actualId) ||
      !/^[a-f0-9]{12,64}$/i.test(expectedId) ||
      !actualId.toLowerCase().startsWith(expectedId.toLowerCase())) {
    return unavailable("postgres_container_id_mismatch");
  }
  if (!isExpectedPostgresImage(image, expectedDigest)) return unavailable("postgres_image_not_digest_pinned");
  const pid = Number(pidText);
  return Number.isSafeInteger(pid) && pid > 0
    ? { status: "available", pid }
    : unavailable("postgres_container_not_running");
}

export function counterDelta(before, after) {
  if (before == null) return { value: null, reason: "baseline_unavailable" };
  const a = BigInt(before), b = BigInt(after);
  return b < a ? { value: null, reason: "counter_reset" } : { value: (b - a).toString() };
}
export const deltaMap = (before, after) => Object.fromEntries(Object.entries(after).map(([key, value]) => [key, counterDelta(before?.[key], value)]));
export const deltaDevices = (before, after) => Object.fromEntries(Object.entries(after).map(([id, values]) => [id, deltaMap(before?.[id], values)]));
export const deltaPressure = (before, after) => Object.fromEntries(Object.entries(after).map(([scope, values]) => [scope, counterDelta(before?.[scope]?.totalUs, values.totalUs)]));

async function readParsed(readText, file, parser) {
  try { return { status: "available", value: parser(await readText(file)) }; }
  catch (error) { return unavailable(reasonOf(error, "invalid_format")); }
}
function runDocker(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8", timeout: 1500, maxBuffer: 65536, windowsHide: true });
  return { status: result.status ?? 1, stdout: result.stdout || "", error: result.error };
}
function postgresPid(runCommand, explicitId, expectedDigest) {
  let id = explicitId;
  if (!id) {
    const listed = runCommand("docker", ["ps", "--no-trunc", "--format", "{{.ID}}|{{.Image}}|{{.Names}}"]);
    if (listed.status !== 0) return unavailable(reasonOf(listed.error, "docker_unavailable"));
    const found = parseDockerPostgresContainers(listed.stdout, expectedDigest);
    if (found.status !== "available") return found;
    id = found.containerId;
  }
  if (!/^[a-f0-9]{12,64}$/i.test(id)) return unavailable("invalid_container_id");
  const inspected = runCommand("docker", ["inspect", "--format", "{{.Id}}|{{.Config.Image}}|{{.State.Pid}}", id]);
  if (inspected.status !== 0) return unavailable(reasonOf(inspected.error, "docker_inspect_failed"));
  return parseDockerPostgresInspect(inspected.stdout, id, expectedDigest);
}

export async function startHostIoTelemetry({
  intervalMs = 250,
  emit = record => process.stdout.write(JSON.stringify(record) + "\n"),
  readText = file => readFile(file, "utf8"),
  runCommand = runDocker,
  now = () => performance.now(),
  wallTime = () => new Date().toISOString(),
  postgresContainerId = process.env.POSTGRES_SERVICE_CONTAINER_ID,
  postgresImageDigest = process.env.POSTGRES_EXPECTED_IMAGE_DIGEST || DEFAULT_POSTGRES_IMAGE_DIGEST,
} = {}) {
  if (!Number.isInteger(intervalMs) || intervalMs < 100) throw new Error("intervalMs must be >= 100");
  if (!/^sha256:[0-9a-f]{64}$/i.test(postgresImageDigest)) throw new Error("postgresImageDigest must be a pinned sha256 digest");
  const started = now();
  const mountInfo = await readParsed(readText, "/proc/self/mountinfo", parseCgroup2Mount);
  const mount = mountInfo.status === "available" ? mountInfo.value : null;
  const runnerText = await readParsed(readText, "/proc/self/cgroup", parseUnifiedCgroupPath);
  const runnerPath = runnerText.status === "available" && runnerText.value ? resolveCgroupDirectory(mount, runnerText.value) : null;
  const runnerReason = runnerText.status !== "available" ? runnerText.reason : !runnerText.value ? "runner_cgroup_v2_not_found" : !mount ? "cgroup_v2_mount_not_found" : "runner_cgroup_outside_visible_mount";
  const processInfo = postgresPid(runCommand, postgresContainerId, postgresImageDigest);
  let postgresPath = null, postgresReason = processInfo.reason || "postgres_cgroup_not_resolved";
  if (processInfo.status === "available") {
    const group = await readParsed(readText, "/proc/" + processInfo.pid + "/cgroup", parseUnifiedCgroupPath);
    if (group.status === "available" && group.value) {
      postgresPath = resolveCgroupDirectory(mount, group.value);
      postgresReason = postgresPath ? null : mount ? "postgres_cgroup_outside_visible_mount" : "cgroup_v2_mount_not_found";
    } else postgresReason = group.status === "available" ? "postgres_cgroup_v2_not_found" : group.reason;
  }

  const previous = {}, lastElapsed = {};
  let busy = false, stopped = false, skipped = 0, pending = Promise.resolve(), timer;
  async function sample() {
    if (stopped) return;
    if (busy) { skipped += 1; return; }
    busy = true;
    pending = (async () => {
      const elapsedMs = now() - started;
      const [disk, host, runnerIo, runnerPressure, postgresIo, postgresPressure] = await Promise.all([
        readParsed(readText, "/proc/diskstats", parseDiskstats),
        readParsed(readText, "/proc/pressure/io", parsePressure),
        runnerPath ? readParsed(readText, path.join(runnerPath, "io.stat"), parseCgroupIoStat) : Promise.resolve(unavailable(runnerReason)),
        runnerPath ? readParsed(readText, path.join(runnerPath, "io.pressure"), parsePressure) : Promise.resolve(unavailable(runnerReason)),
        postgresPath ? readParsed(readText, path.join(postgresPath, "io.stat"), parseCgroupIoStat) : Promise.resolve(unavailable(postgresReason)),
        postgresPath ? readParsed(readText, path.join(postgresPath, "io.pressure"), parsePressure) : Promise.resolve(unavailable(postgresReason)),
      ]);
      const source = (result, delta, key) => result.status !== "available" ? result : {
        status: "available", current: result.value, delta,
        deltaIntervalMs: lastElapsed[key] === undefined ? null : Math.max(0, elapsedMs - lastElapsed[key]),
      };
      const diskCounters = disk.status === "available" ? Object.fromEntries(Object.entries(disk.value).map(([id, item]) => [id, item.counters])) : null;
      emit({
        type: "host_io_sample", schemaVersion: 1, at: wallTime(), elapsedMs, intervalMs, skippedSamples: skipped,
        host: {
          diskstats: source(disk, diskCounters ? deltaDevices(previous.disk, diskCounters) : null, "disk"),
          ioPressure: source(host, host.status === "available" ? deltaPressure(previous.host, host.value) : null, "host"),
        },
        cgroups: {
          runner: { status: runnerPath ? "available" : "unavailable", ...(runnerPath ? {
            ioStat: source(runnerIo, runnerIo.status === "available" ? deltaDevices(previous.runnerIo, runnerIo.value) : null, "runnerIo"),
            ioPressure: source(runnerPressure, runnerPressure.status === "available" ? deltaPressure(previous.runnerPressure, runnerPressure.value) : null, "runnerPressure"),
          } : { reason: runnerReason }) },
          postgresService: { status: postgresPath ? "available" : "unavailable", ...(postgresPath ? {
            ioStat: source(postgresIo, postgresIo.status === "available" ? deltaDevices(previous.postgresIo, postgresIo.value) : null, "postgresIo"),
            ioPressure: source(postgresPressure, postgresPressure.status === "available" ? deltaPressure(previous.postgresPressure, postgresPressure.value) : null, "postgresPressure"),
          } : { reason: postgresReason }) },
        },
      });
      if (diskCounters) { previous.disk = diskCounters; lastElapsed.disk = elapsedMs; }
      if (host.status === "available") { previous.host = host.value; lastElapsed.host = elapsedMs; }
      if (runnerIo.status === "available") { previous.runnerIo = runnerIo.value; lastElapsed.runnerIo = elapsedMs; }
      if (runnerPressure.status === "available") { previous.runnerPressure = runnerPressure.value; lastElapsed.runnerPressure = elapsedMs; }
      if (postgresIo.status === "available") { previous.postgresIo = postgresIo.value; lastElapsed.postgresIo = elapsedMs; }
      if (postgresPressure.status === "available") { previous.postgresPressure = postgresPressure.value; lastElapsed.postgresPressure = elapsedMs; }
      skipped = 0;
    })().catch(error => emit({ type: "host_io_sample_error", at: wallTime(), elapsedMs: now() - started, reason: reasonOf(error, "sample_error") })).finally(() => { busy = false; });
    await pending;
  }
  await sample();
  timer = setInterval(() => { void sample(); }, intervalMs);
  timer.unref?.();
  return { stop: async () => { if (stopped) return; stopped = true; clearInterval(timer); await pending; } };
}
