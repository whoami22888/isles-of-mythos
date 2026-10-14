#!/usr/bin/env node
import { createHash, randomUUID } from "node:crypto";
import { closeSync, existsSync, lstatSync, mkdirSync, openSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";

const terminal = new Set(["succeeded", "failed", "cancelled", "timed_out"]);
const statuses = new Set(["queued", "running", "blocked", ...terminal]);
const retryKinds = new Set(["transient_network", "runner_unavailable", "rate_limited"]);
const neverRetry = new Set(["acceptance", "migration", "deployment", "release", "production_write"]);
const shaRE = /^[0-9a-f]{40}$/i;
const slugRE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const tailLimit = 4096;

function need(ok, message) { if (!ok) throw new Error(message); }
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
}
export function fingerprint(state) {
  return createHash("sha256").update(JSON.stringify(canonical(state))).digest("hex");
}
function taskPath(value) {
  need(typeof value === "string" && value.length > 0 && !isAbsolute(value) && !/^[a-z]:/i.test(value), "Task paths must be relative");
  const value2 = value.replace(/\\/g, "/").replace(/\/+$/, "") || ".";
  need(!value2.split("/").includes("..") && !/[*?{}[\]]/.test(value2), "Task path must be explicit and contained");
  return value2;
}
function overlap(a, b) {
  const left = taskPath(a).toLowerCase();
  const right = taskPath(b).toLowerCase();
  return left === "." || right === "." || left === right || left.startsWith(right + "/") || right.startsWith(left + "/");
}
export function ownershipCheck(tasks, candidate) {
  const active = tasks.filter(task => task.id !== candidate.id && ["running", "blocked"].includes(task.status));
  const exclusiveConflicts = [];
  const pathWarnings = [];
  for (const owner of active) {
    for (const action of candidate.exclusiveActions ?? []) {
      if ((owner.exclusiveActions ?? []).includes(action)) exclusiveConflicts.push({ taskId: owner.id, action });
    }
    for (const path of candidate.paths ?? []) for (const otherPath of owner.paths ?? []) {
      if (overlap(path, otherPath)) pathWarnings.push({ taskId: owner.id, path, overlapsPath: otherPath });
    }
  }
  return { exclusiveConflicts, pathWarnings };
}
export function validateLedger(ledger) {
  need(ledger?.schemaVersion === 1 && Number.isInteger(ledger.revision) && ledger.revision >= 1, "Unsupported task-ledger schema/revision");
  need(Array.isArray(ledger.tasks), "Task list is missing");
  const ids = new Set();
  for (const task of ledger.tasks) {
    need(typeof task.id === "string" && task.id.trim() && !ids.has(task.id), "Missing or duplicate task id");
    ids.add(task.id);
    need(typeof task.title === "string" && task.title.trim(), "Task title is required: " + task.id);
    need(statuses.has(task.status), "Invalid task status: " + task.id);
    need(typeof task.kind === "string" && task.kind && typeof task.owner === "string" && task.owner, "Task kind/owner is required: " + task.id);
    need(Number.isInteger(task.revision) && task.revision >= 1, "Invalid task revision: " + task.id);
    need(Number.isInteger(task.maxAttempts) && task.maxAttempts >= 1 && task.maxAttempts <= 3, "maxAttempts must be 1..3: " + task.id);
    need(Number.isInteger(task.attempts) && task.attempts >= 0 && task.attempts <= task.maxAttempts, "Attempt budget exceeded: " + task.id);
    for (const key of ["createdAt", "updatedAt", "deadlineAt"]) need(typeof task[key] === "string" && Number.isFinite(Date.parse(task[key])), "Invalid " + key + ": " + task.id);
    need(Date.parse(task.deadlineAt) > Date.parse(task.createdAt) && Date.parse(task.updatedAt) >= Date.parse(task.createdAt), "Invalid task timestamps: " + task.id);
    need(typeof task.idempotent === "boolean", "Task idempotent flag is required: " + task.id);
    need(Array.isArray(task.paths) && Array.isArray(task.exclusiveActions) && Array.isArray(task.dependencies), "Task scopes/dependencies must be arrays: " + task.id);
    task.paths.forEach(taskPath);
    need(new Set(task.paths).size === task.paths.length, "Duplicate path claim: " + task.id);
    task.exclusiveActions.forEach(action => need(typeof action === "string" && slugRE.test(action), "Invalid exclusive action: " + task.id));
    need(new Set(task.exclusiveActions).size === task.exclusiveActions.length, "Duplicate exclusive action: " + task.id);
    need(task.dependencies.every(dep => typeof dep === "string" && dep !== task.id) && new Set(task.dependencies).size === task.dependencies.length, "Invalid dependencies: " + task.id);
    const history = task.history ?? [];
    need(Array.isArray(history) && history.length <= task.maxAttempts && history.length <= task.attempts, "Invalid history length: " + task.id);
    for (const entry of history) need(/^[0-9a-f]{64}$/i.test(entry?.fingerprint ?? "") && typeof entry.kind === "string" && Number.isFinite(Date.parse(entry.at)), "Invalid attempt record: " + task.id);
    if (task.completedAt !== undefined) need(terminal.has(task.status) && Number.isFinite(Date.parse(task.completedAt)), "Invalid completedAt: " + task.id);
  }
  const dependencyMap = new Map(ledger.tasks.map(task => [task.id, task.dependencies]));
  for (const [id, dependencies] of dependencyMap) for (const dep of dependencies) need(dependencyMap.has(dep), "Unknown dependency " + dep + " for " + id);
  const visiting = new Set();
  const visited = new Set();
  function visit(id) {
    if (visiting.has(id)) throw new Error("Dependency cycle includes " + id);
    if (visited.has(id)) return;
    visiting.add(id);
    for (const dep of dependencyMap.get(id) ?? []) visit(dep);
    visiting.delete(id);
    visited.add(id);
  }
  for (const id of dependencyMap.keys()) visit(id);
  return { valid: true, revision: ledger.revision, taskCount: ledger.tasks.length };
}
export function retryDecision(task, failureKind, state, now = Date.now()) {
  const nowMs = typeof now === "string" ? Date.parse(now) : now;
  need(Number.isFinite(nowMs), "Invalid retry decision time");
  const stateHash = fingerprint(state);
  const result = (retry, reason) => ({ retry, reason, fingerprint: stateHash });
  if (neverRetry.has(task.kind)) return result(false, "non_retryable_task_class");
  if (!task.idempotent) return result(false, "task_not_declared_idempotent");
  if (!retryKinds.has(failureKind)) return result(false, "failure_not_transient");
  if (!Number.isInteger(task.attempts) || task.attempts >= task.maxAttempts) return result(false, "attempt_budget_exhausted");
  if (!Number.isFinite(Date.parse(task.deadlineAt)) || nowMs >= Date.parse(task.deadlineAt)) return result(false, "deadline_expired");
  if ((task.history ?? []).some(item => item.fingerprint === stateHash)) return result(false, "repeated_state_fingerprint");
  return result(true, "bounded_transient_retry");
}
function relativeEvidencePath(path) {
  need(typeof path === "string" && path && !isAbsolute(path), "Evidence path must be relative");
  const absolute = resolve(process.cwd(), path);
  const rel = relative(process.cwd(), absolute);
  need(rel && rel !== ".." && !rel.startsWith(".." + sep), "Evidence path escapes repository");
  return rel.split(sep).join("/");
}
function appendTail(current, chunk) {
  const value = current + chunk.toString("utf8");
  return value.length <= tailLimit ? value : value.slice(-tailLimit);
}
function signalTree(child, signal) {
  try {
    if (process.platform !== "win32" && child.pid) process.kill(-child.pid, signal);
    else child.kill(signal);
  } catch (error) { if (error?.code !== "ESRCH") throw error; }
}
async function runOne({ command, args, cwd, deadlineAt, forwardOutput, onSpawn }) {
  const deadline = Date.parse(deadlineAt);
  if (!Number.isFinite(deadline) || deadline <= Date.now()) return { status: "timed_out", exitCode: null, signal: null, errorCode: null, stdoutTail: "", stderrTail: "", durationMs: 0 };
  const started = Date.now();
  let child, timedOut = false, stdoutTail = "", stderrTail = "", spawnError = null, deadlineTimer, escalationTimer;
  return await new Promise((resolvePromise, rejectPromise) => {
    try {
      child = spawn(command, args, { cwd, env: process.env, shell: false, detached: process.platform !== "win32", stdio: ["ignore", "pipe", "pipe"] });
    } catch (error) {
      resolvePromise({ status: "spawn_error", exitCode: null, signal: null, errorCode: error?.code ?? "SPAWN_FAILED", stdoutTail: "", stderrTail: "", durationMs: Date.now() - started });
      return;
    }
    child.stdout.on("data", chunk => { stdoutTail = appendTail(stdoutTail, chunk); if (forwardOutput) process.stdout.write(chunk); });
    child.stderr.on("data", chunk => { stderrTail = appendTail(stderrTail, chunk); if (forwardOutput) process.stderr.write(chunk); });
    child.on("error", error => { spawnError = error; });
    deadlineTimer = setTimeout(() => {
      timedOut = true;
      try { signalTree(child, "SIGTERM"); } catch {}
      escalationTimer = setTimeout(() => { try { signalTree(child, "SIGKILL"); } catch {} }, 1000);
      escalationTimer.unref?.();
    }, Math.max(1, deadline - started));
    deadlineTimer.unref?.();
    try { if (onSpawn) onSpawn(child.pid); } catch (error) { try { signalTree(child, "SIGTERM"); } catch {} rejectPromise(error); return; }
    child.on("close", (exitCode, signal) => {
      clearTimeout(deadlineTimer);
      if (escalationTimer) clearTimeout(escalationTimer);
      resolvePromise({ status: timedOut ? "timed_out" : (spawnError ? "spawn_error" : "completed"), exitCode, signal, errorCode: spawnError?.code ?? null, stdoutTail, stderrTail, durationMs: Date.now() - started });
    });
  });
}
export async function runBoundedCommand({ command, args = [], cwd = process.cwd(), deadlineAt, maxAttempts = 1, initialAttempts = 0, idempotent = false, taskKind = "generic", history = [], retryKind = null, retryExitCodes = [], forwardOutput = true, onAttemptStart, onSpawn, onAttempt }) {
  need(typeof command === "string" && command, "Concrete command required");
  need(Array.isArray(args) && args.every(value => typeof value === "string"), "Command arguments must be strings");
  need(Number.isInteger(maxAttempts) && maxAttempts >= 1 && maxAttempts <= 3, "maxAttempts must be 1..3");
  need(Number.isInteger(initialAttempts) && initialAttempts >= 0 && initialAttempts <= maxAttempts, "Invalid initial attempt count");
  need(Number.isFinite(Date.parse(deadlineAt)), "Absolute deadline required");
  need(Array.isArray(retryExitCodes) && retryExitCodes.every(code => Number.isInteger(code) && code >= 0 && code <= 255), "Invalid retry exit codes");
  if (initialAttempts > 0 && (!idempotent || neverRetry.has(taskKind))) return { status: "blocked", reason: "unsafe_resume_requires_idempotence", attempts: initialAttempts };
  const absCwd = resolve(cwd);
  const relCwd = relative(process.cwd(), absCwd);
  need(relCwd === "" || (relCwd !== ".." && !relCwd.startsWith(".." + sep)), "Command cwd must be inside repository");
  const seen = [...history];
  let last = null, attempts = initialAttempts;
  for (let index = initialAttempts; index < maxAttempts; index++) {
    if (Date.now() >= Date.parse(deadlineAt)) return { status: "timed_out", reason: "deadline_expired_before_attempt", attempts, last };
    const attemptNumber = index + 1;
    if (onAttemptStart) await onAttemptStart(attemptNumber);
    const outcome = await runOne({ command, args, cwd: absCwd, deadlineAt, forwardOutput, onSpawn });
    attempts = attemptNumber;
    const state = { command, args, exitCode: outcome.exitCode, signal: outcome.signal, errorCode: outcome.errorCode, stderrTail: outcome.stderrTail.trim().slice(-2000) };
    const stateHash = fingerprint(state);
    const entry = { fingerprint: stateHash, kind: outcome.status === "timed_out" ? "timed_out" : (outcome.exitCode === 0 ? "succeeded" : "failed"), at: new Date().toISOString(), exitCode: outcome.exitCode, signal: outcome.signal, errorCode: outcome.errorCode, durationMs: outcome.durationMs };
    const repeated = seen.some(item => item.fingerprint === stateHash);
    last = { status: outcome.status, exitCode: outcome.exitCode, signal: outcome.signal, errorCode: outcome.errorCode, fingerprint: stateHash, durationMs: outcome.durationMs };
    if (onAttempt) await onAttempt(entry, last);
    if (outcome.status === "timed_out") return { status: "timed_out", reason: "deadline_killed_process", attempts, last };
    if (outcome.status === "spawn_error") return { status: "failed", reason: "process_spawn_error", attempts, last };
    if (outcome.exitCode === 0) return { status: "succeeded", reason: "exit_code_zero", attempts, last };
    if (repeated) return { status: "failed", reason: "repeated_state_fingerprint", attempts, last };
    const decision = retryExitCodes.includes(outcome.exitCode) && retryKind
      ? retryDecision({ kind: taskKind, idempotent, maxAttempts, attempts: attemptNumber, deadlineAt, history: seen }, retryKind, state, Date.now())
      : { retry: false, reason: "failure_not_configured_for_retry" };
    if (!decision.retry) return { status: "failed", reason: decision.reason, attempts, last };
    seen.push(entry);
  }
  return { status: "failed", reason: "attempt_budget_exhausted", attempts, last };
}
function pidAlive(pid) {
  if (!Number.isInteger(pid) || pid < 1) return false;
  try { process.kill(pid, 0); return true; } catch (error) { return error?.code === "EPERM"; }
}
function atomicWrite(path, data) {
  const file = resolve(path);
  mkdirSync(dirname(file), { recursive: true });
  const temp = file + ".tmp-" + process.pid + "-" + randomUUID();
  writeFileSync(temp, JSON.stringify(data, null, 2) + "\n", { flag: "wx" });
  renameSync(temp, file);
}
function withLock(path, fn) {
  const file = resolve(path), lockPath = file + ".lock";
  let fd;
  try { fd = openSync(lockPath, "wx"); } catch (error) {
    if (error?.code === "EEXIST") {
      let state;
      try { state = JSON.parse(readFileSync(lockPath, "utf8")); } catch {}
      if (Number.isFinite(Date.parse(state?.createdAt)) && Date.now() - Date.parse(state.createdAt) > 120000 && !pidAlive(state.pid)) {
        try { unlinkSync(lockPath); } catch {}
        try { fd = openSync(lockPath, "wx"); } catch {}
      }
    }
    if (fd === undefined) throw new Error("Task ledger is locked; refusing to spin or overwrite another writer");
  }
  try { writeFileSync(fd, JSON.stringify({ pid: process.pid, createdAt: new Date().toISOString() })); closeSync(fd); return fn(file); }
  finally { try { unlinkSync(lockPath); } catch {} }
}
function loadLedger(path, create = false) {
  const file = resolve(path);
  if (!existsSync(file) && create) return { schemaVersion: 1, revision: 0, tasks: [] };
  const ledger = JSON.parse(readFileSync(file, "utf8"));
  validateLedger(ledger);
  return ledger;
}
function mutateLedger(path, fn) {
  return withLock(path, file => {
    const ledger = loadLedger(file, true);
    const result = fn(ledger);
    ledger.revision++;
    validateLedger(ledger);
    atomicWrite(file, ledger);
    return result;
  });
}
function mutateTask(path, id, expectedRevision, fn) {
  return mutateLedger(path, ledger => {
    const index = ledger.tasks.findIndex(task => task.id === id);
    need(index >= 0, "Task not found: " + id);
    const current = ledger.tasks[index];
    need(current.revision === expectedRevision, "Task revision changed; reload before update: " + id);
    const next = fn({ ...current, history: [...(current.history ?? [])] });
    next.revision = current.revision + 1;
    next.updatedAt = new Date().toISOString();
    ledger.tasks[index] = next;
    return { ...next, history: [...(next.history ?? [])] };
  });
}
export function buildEvidenceManifest({ headSha, runId, files }) {
  need(typeof headSha === "string" && shaRE.test(headSha), "Manifest requires exact 40-character SHA");
  need((typeof runId === "string" && runId.length > 0) || (Number.isSafeInteger(runId) && runId > 0), "Manifest requires workflow run ID");
  need(Array.isArray(files) && files.length > 0, "Manifest requires files");
  const entries = files.map(item => {
    const path = relativeEvidencePath(item.path);
    need(!lstatSync(path).isSymbolicLink(), "Symlinks are not valid evidence: " + path);
    const info = statSync(path);
    need(info.isFile() && info.size > 0, "Evidence file is missing/empty: " + path);
    return { path, sizeBytes: info.size, sha256: createHash("sha256").update(readFileSync(path)).digest("hex") };
  }).sort((a, b) => a.path.localeCompare(b.path));
  need(new Set(entries.map(item => item.path)).size === entries.length, "Duplicate evidence path");
  return { schemaVersion: 1, status: "validated", headSha: headSha.toLowerCase(), runId: String(runId), createdAt: new Date().toISOString(), files: entries };
}
function relativeEvidencePath(path) {
  need(typeof path === "string" && path && !isAbsolute(path), "Evidence path must be relative");
  const absolute = resolve(process.cwd(), path);
  const rel = relative(process.cwd(), absolute);
  need(rel && rel !== ".." && !rel.startsWith(".." + sep), "Evidence path escapes repository");
  return rel.split(sep).join("/");
}
export function validateEvidenceManifest(manifest, { expectedSha, expectedRunId, requiredFiles } = {}) {
  need(manifest?.schemaVersion === 1 && manifest.status === "validated", "Evidence manifest is not validated");
  need(typeof expectedSha === "string" && shaRE.test(expectedSha) && manifest.headSha?.toLowerCase() === expectedSha.toLowerCase(), "Evidence SHA is stale or invalid");
  if (expectedRunId !== undefined) need(String(manifest.runId) === String(expectedRunId), "Evidence run ID mismatch");
  need(Array.isArray(manifest.files) && manifest.files.length > 0, "Evidence manifest is empty");
  const paths = new Set();
  for (const item of manifest.files) {
    const path = relativeEvidencePath(item.path);
    need(!paths.has(path), "Duplicate manifest entry: " + path);
    paths.add(path);
    need(!lstatSync(path).isSymbolicLink(), "Symlink evidence rejected: " + path);
    const info = statSync(path);
    need(info.isFile() && info.size === item.sizeBytes && info.size > 0, "Evidence size changed: " + path);
    need(createHash("sha256").update(readFileSync(path)).digest("hex") === item.sha256, "Evidence digest changed: " + path);
  }
  for (const path of requiredFiles ?? []) need(paths.has(relativeEvidencePath(path)), "Required file is absent from manifest: " + path);
  return { valid: true, headSha: manifest.headSha.toLowerCase(), fileCount: manifest.files.length };
}
export function validateAcceptance({ expectedSha, actualSha, checks, requiredChecks, artifacts }) {
  need(typeof expectedSha === "string" && shaRE.test(expectedSha) && typeof actualSha === "string" && shaRE.test(actualSha), "Invalid acceptance SHA");
  need(expectedSha.toLowerCase() === actualSha.toLowerCase(), "Acceptance evidence SHA differs from current HEAD");
  need(Array.isArray(checks) && Array.isArray(requiredChecks) && requiredChecks.length > 0, "Required check evidence missing");
  const byName = new Map();
  for (const check of checks) {
    need(typeof check?.name === "string" && !byName.has(check.name), "Invalid or duplicate check evidence");
    byName.set(check.name, check);
  }
  for (const name of requiredChecks) {
    const check = byName.get(name);
    need(check?.status === "completed" && check.conclusion === "success", "Required check is not completed success: " + name);
    if (check.head_sha !== undefined) need(check.head_sha.toLowerCase() === expectedSha.toLowerCase(), "Required check SHA is stale: " + name);
  }
  need(artifacts?.status === "validated" && artifacts.headSha?.toLowerCase() === expectedSha.toLowerCase(), "Evidence artifact manifest is missing or stale");
  return { valid: true, headSha: expectedSha.toLowerCase(), checkCount: requiredChecks.length };
}
function parseOptions(args, allowed) {
  const options = {};
  while (args.length && args[0] !== "--") {
    const key = args.shift();
    need(allowed.includes(key), "Unknown option: " + key);
    const value = args.shift();
    need(value !== undefined && value !== "", "Missing option value: " + key);
    options[key] = value;
  }
  return options;
}
function help() {
  console.log("Commands: validate-ledger, add-task, transition-task, run-task, manifest, validate-manifest, validate-acceptance");
}
async function runTask(path, id, retryKind, retryCodes, executable, commandArgs) {
  const ledger = loadLedger(path);
  let task = ledger.tasks.find(item => item.id === id);
  need(task, "Task not found: " + id);
  if (task.status === "running") {
    if (pidAlive(task.childPid)) throw new Error("Task child is alive; duplicate execution refused");
    mutateTask(path, id, task.revision, current => ({ ...current, status: "blocked", childPid: null, blockedReason: "interrupted_controller_or_child" }));
    throw new Error("Interrupted task marked blocked; inspect before explicitly requeueing");
  }
  need(task.status === "queued", "Only queued tasks may run");
  if (!task.dependencies.every(dep => ledger.tasks.find(item => item.id === dep)?.status === "succeeded")) {
    mutateTask(path, id, task.revision, current => ({ ...current, status: "blocked", blockedReason: "dependencies_not_succeeded" }));
    throw new Error("Dependencies incomplete; task marked blocked");
  }
  const ownership = ownershipCheck(ledger.tasks, task);
  need(!ownership.exclusiveConflicts.length, "Exclusive action conflict: " + JSON.stringify(ownership.exclusiveConflicts));
  for (const warning of ownership.pathWarnings) console.error("PATH OVERLAP WARNING " + JSON.stringify(warning));
  if (Date.now() >= Date.parse(task.deadlineAt)) {
    mutateTask(path, id, task.revision, current => ({ ...current, status: "timed_out", completedAt: new Date().toISOString(), lastResult: { reason: "deadline_expired_before_start" } }));
    throw new Error("Task deadline expired before execution");
  }
  need(task.attempts < task.maxAttempts, "Task attempt budget exhausted");
  if (task.attempts > 0 && (!task.idempotent || neverRetry.has(task.kind))) {
    mutateTask(path, id, task.revision, current => ({ ...current, status: "blocked", blockedReason: "unsafe_retry_requires_new_task" }));
    throw new Error("Unsafe retry refused; task marked blocked");
  }
  task = mutateTask(path, id, task.revision, current => ({ ...current, status: "running", childPid: null, blockedReason: undefined }));
  let currentTask = task;
  const result = await runBoundedCommand({
    command: executable, args: commandArgs, cwd: process.cwd(), deadlineAt: task.deadlineAt,
    maxAttempts: task.maxAttempts, initialAttempts: task.attempts, idempotent: task.idempotent,
    taskKind: task.kind, history: task.history ?? [], retryKind, retryExitCodes: retryCodes,
    forwardOutput: true,
    onAttemptStart: async count => {
      currentTask = mutateTask(path, id, currentTask.revision, current => ({ ...current, status: "running", attempts: count, childPid: null }));
    },
    onSpawn: pid => {
      currentTask = mutateTask(path, id, currentTask.revision, current => ({ ...current, childPid: pid ?? null }));
    },
    onAttempt: async entry => {
      currentTask = mutateTask(path, id, currentTask.revision, current => ({ ...current, childPid: null, history: [...(current.history ?? []), entry] }));
    },
  });
  const finalState = result.status === "succeeded" ? "succeeded" : result.status === "timed_out" ? "timed_out" : result.status === "blocked" ? "blocked" : "failed";
  currentTask = mutateTask(path, id, currentTask.revision, current => ({
    ...current, status: finalState, childPid: null,
    ...(terminal.has(finalState) ? { completedAt: new Date().toISOString() } : { completedAt: undefined }),
    lastResult: { status: result.status, reason: result.reason, attempts: result.attempts, exitCode: result.last?.exitCode ?? null, signal: result.last?.signal ?? null, fingerprint: result.last?.fingerprint ?? null },
  }));
  console.log(JSON.stringify({ id, status: currentTask.status, revision: currentTask.revision, result: currentTask.lastResult }, null, 2));
  if (finalState !== "succeeded") process.exitCode = 1;
}
const args = process.argv.slice(2);
const command = args.shift();
try {
  if (!command || command === "--help" || command === "-h") help();
  else if (command === "validate-ledger") {
    need(args.length === 1, "Usage: validate-ledger <ledger.json>");
    console.log(JSON.stringify(validateLedger(loadLedger(args[0]))));
  } else if (command === "add-task") {
    const path = args.shift();
    need(path, "Ledger path required");
    const options = parseOptions(args, ["--id", "--title", "--kind", "--deadline-at", "--max-attempts", "--idempotent", "--owner", "--paths", "--exclusive-actions", "--depends-on"]);
    need(args.length === 0, "Unexpected task arguments");
    for (const key of ["--id", "--title", "--kind", "--deadline-at", "--max-attempts", "--idempotent"]) need(options[key] !== undefined, "Missing option " + key);
    need(["true", "false"].includes(options["--idempotent"]), "idempotent must be true or false");
    const createdAt = new Date().toISOString();
    const task = {
      id: options["--id"], title: options["--title"], kind: options["--kind"], owner: options["--owner"] ?? "local-controller",
      paths: (options["--paths"] ?? "").split(",").filter(Boolean).map(taskPath),
      exclusiveActions: (options["--exclusive-actions"] ?? "").split(",").filter(Boolean),
      dependencies: (options["--depends-on"] ?? "").split(",").filter(Boolean),
      status: "queued", idempotent: options["--idempotent"] === "true", attempts: 0,
      maxAttempts: Number(options["--max-attempts"]), createdAt, updatedAt: createdAt,
      deadlineAt: options["--deadline-at"], revision: 1, history: [],
    };
    need(Number.isInteger(task.maxAttempts) && task.maxAttempts >= 1 && task.maxAttempts <= 3, "max-attempts must be 1..3");
    need(Number.isFinite(Date.parse(task.deadlineAt)) && Date.parse(task.deadlineAt) > Date.parse(createdAt), "deadline-at must be a future ISO time");
    task.exclusiveActions.forEach(action => need(actionSlug.test(action), "Invalid exclusive action: " + action));
    const created = mutateLedger(path, ledger => {
      need(!ledger.tasks.some(other => other.id === task.id), "Task already exists: " + task.id);
      task.dependencies.forEach(dep => need(ledger.tasks.some(other => other.id === dep), "Unknown dependency: " + dep));
      const ownership = ownershipCheck(ledger.tasks, task);
      need(!ownership.exclusiveConflicts.length, "Exclusive action conflict: " + JSON.stringify(ownership.exclusiveConflicts));
      task.pathWarnings = ownership.pathWarnings;
      ledger.tasks.push(task);
      return { task, warnings: ownership.pathWarnings };
    });
    if (created.warnings.length) console.error("PATH OVERLAP WARNINGS " + JSON.stringify(created.warnings));
    console.log(JSON.stringify(created.task));
  } else if (command === "transition-task") {
    need(args.length === 3, "Usage: transition-task <ledger.json> <id> <new-status>");
    const [path, id, target] = args;
    need(statuses.has(target), "Unknown task status");
    const ledger = loadLedger(path);
    const task = ledger.tasks.find(item => item.id === id);
    need(task, "Task not found");
    const transitions = {
      queued: new Set(["blocked", "cancelled", "timed_out"]),
      running: new Set(["blocked", "cancelled", "timed_out"]),
      blocked: new Set(["queued", "cancelled"]),
      succeeded: new Set(), failed: new Set(), cancelled: new Set(), timed_out: new Set(),
    };
    need(transitions[task.status].has(target), "Disallowed transition: " + task.status + " -> " + target);
    if (task.status === "running" && pidAlive(task.childPid)) throw new Error("Cannot transition while task process is alive");
    if (target === "queued") {
      need(task.attempts < task.maxAttempts && task.idempotent && !neverRetry.has(task.kind), "Unsafe requeue; create a new task");
      need(task.dependencies.every(dep => ledger.tasks.find(item => item.id === dep)?.status === "succeeded"), "Dependencies incomplete");
    }
    const updated = mutateTask(path, id, task.revision, current => ({
      ...current, status: target, childPid: null,
      ...(terminal.has(target) ? { completedAt: new Date().toISOString() } : { completedAt: undefined }),
    }));
    console.log(JSON.stringify({ id, status: updated.status, revision: updated.revision }));
  } else if (command === "run-task") {
    need(args.length >= 4, "Usage: run-task <ledger.json> <id> [--retry-kind K] [--retry-exit-codes N,N] -- <command> [args...]");
    const path = args.shift(), id = args.shift();
    const options = parseOptions(args, ["--retry-kind", "--retry-exit-codes"]);
    need(args.shift() === "--", "Command must follow explicit -- separator");
    const executable = args.shift();
    need(executable, "Command executable required");
    const retryKind = options["--retry-kind"] ?? null;
    if (retryKind !== null) need(retryKinds.has(retryKind), "Unapproved transient retry kind");
    const retryCodes = (options["--retry-exit-codes"] ?? "").split(",").filter(Boolean).map(Number);
    need(retryCodes.every(code => Number.isInteger(code) && code >= 0 && code <= 255), "Invalid retry exit code");
    await runTask(path, id, retryKind, retryCodes, executable, args);
  } else if (command === "manifest") {
    const options = {}, files = [];
    while (args.length) {
      const key = args.shift();
      if (["--sha", "--run-id", "--out"].includes(key)) {
        const value = args.shift(); need(Boolean(value), "Missing value for " + key); options[key] = value;
      } else if (key.startsWith("-")) throw new Error("Unknown option: " + key);
      else files.push(key);
    }
    need(options["--sha"] && options["--run-id"] && options["--out"] && files.length > 0, "Invalid manifest arguments");
    const manifest = buildEvidenceManifest({ headSha: options["--sha"], runId: options["--run-id"], files: files.map(path => ({ path })) });
    validateEvidenceManifest(manifest, { expectedSha: options["--sha"], expectedRunId: options["--run-id"], requiredFiles: files });
    writeFileSync(options["--out"], JSON.stringify(manifest, null, 2) + "\n", { flag: "wx" });
    console.log(JSON.stringify({ status: manifest.status, headSha: manifest.headSha, runId: manifest.runId, fileCount: manifest.files.length }));
  } else if (command === "validate-manifest") {
    need(args.length >= 1, "Usage: validate-manifest <manifest.json> --sha <sha> --run-id <id> --required <file,file>");
    const path = args.shift(), options = {};
    while (args.length) {
      const key = args.shift();
      if (["--sha", "--run-id", "--required"].includes(key)) {
        const value = args.shift(); need(Boolean(value), "Missing option " + key); options[key] = value;
      } else throw new Error("Unknown option: " + key);
    }
    need(options["--sha"] && options["--run-id"] && options["--required"], "SHA, run ID and required files are mandatory");
    console.log(JSON.stringify(validateEvidenceManifest(JSON.parse(readFileSync(path, "utf8")), {
      expectedSha: options["--sha"], expectedRunId: options["--run-id"],
      requiredFiles: options["--required"].split(",").filter(Boolean),
    })));
  } else if (command === "validate-acceptance") {
    need(args.length === 1, "Usage: validate-acceptance <evidence.json>");
    console.log(JSON.stringify(validateAcceptance(JSON.parse(readFileSync(args[0], "utf8")))));
  } else throw new Error("Unknown command: " + command);
} catch (error) {
  console.error("orchestration-control failure: " + (error instanceof Error ? error.message : String(error)));
  process.exitCode = 1;
}
