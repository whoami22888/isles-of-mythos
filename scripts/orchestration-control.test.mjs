import test, { after } from "node:test";
import assert from "node:assert/strict";
import { cpSync, mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { spawn, spawnSync } from "node:child_process";
import { join, relative, resolve } from "node:path";
import {
  ownershipCheck, buildEvidenceManifest, retryDecision, runBoundedCommand, fingerprint,
  validateAcceptance, validateEvidenceManifest, validateLedger, runTask, claimTask, processIdentity,
} from "./orchestration-control.mjs";

mkdirSync(join(process.cwd(), "dist"), { recursive: true });
const tempRoot = mkdtempSync(join(process.cwd(), "dist", "orchestration-test-"));
after(() => rmSync(tempRoot, { recursive: true, force: true }));
const future = seconds => new Date(Date.now() + seconds * 1000).toISOString();
const task = override => ({
  id: "task-1", title: "Test task", kind: "generic", owner: "test-runner", paths: ["scripts/orchestration-control.mjs"],
  exclusiveActions: [], dependencies: [], status: "queued", idempotent: true, attempts: 0, maxAttempts: 3,
  createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(), deadlineAt: future(30), revision: 1, history: [], ...override,
});

test("validates a bounded ledger and rejects over-budget or duplicate tasks", () => {
  assert.equal(validateLedger({ schemaVersion: 1, revision: 1, tasks: [task()] }).valid, true);
  assert.throws(() => validateLedger({ schemaVersion: 1, revision: 1, tasks: [task({ maxAttempts: 4 })] }), /maxAttempts/);
  assert.throws(() => validateLedger({ schemaVersion: 1, revision: 1, tasks: [task(), task()] }), /duplicate task id/i);
});

test("detects dependency cycles", () => {
  assert.throws(() => validateLedger({ schemaVersion: 1, revision: 1, tasks: [
    task({ id: "one", dependencies: ["two"] }), task({ id: "two", dependencies: ["one"] }),
  ] }), /cycle/i);
});

test("exclusive ownership conflicts block while path overlaps are advisory", () => {
  const active = task({ id: "active", status: "running", exclusiveActions: ["release-publication"] });
  const result = ownershipCheck([active], task({ id: "next", paths: ["scripts"], exclusiveActions: ["release-publication"] }));
  assert.equal(result.exclusiveConflicts.length, 1);
  assert.equal(result.pathWarnings.length, 1);
});

test("fingerprints ignore object key order", () => {
  assert.equal(fingerprint({ z: 3, a: 1 }), fingerprint({ a: 1, z: 3 }));
});

test("retry is explicit, idempotent, bounded and deadline-aware", () => {
  assert.equal(retryDecision(task(), "transient_network", { state: "changed" }).retry, true);
  assert.equal(retryDecision(task({ kind: "acceptance" }), "transient_network", {}).retry, false);
  assert.equal(retryDecision(task({ idempotent: false }), "transient_network", {}).reason, "task_not_declared_idempotent");
  assert.equal(retryDecision(task(), "validation_error", {}).reason, "failure_not_transient");
  assert.equal(retryDecision(task({ deadlineAt: new Date(Date.now() - 1000).toISOString() }), "transient_network", {}).reason, "deadline_expired");
  assert.equal(retryDecision(task({ attempts: 3 }), "transient_network", {}).reason, "attempt_budget_exhausted");
});

test("repeated state fingerprint stops retries", () => {
  const state = { exitCode: 75, message: "same error" };
  const stateHash = fingerprint(state);
  const result = retryDecision(task({ history: [{ fingerprint: stateHash, kind: "failed", at: new Date().toISOString() }] }), "transient_network", state);
  assert.equal(result.retry, false);
  assert.equal(result.reason, "repeated_state_fingerprint");
});

test("acceptance evidence requires exact SHA and successful mandatory checks", () => {
  const sha = "a".repeat(40);
  const evidence = {
    expectedSha: sha, actualSha: sha, requiredChecks: ["CI", "CodeQL"],
    checks: [
      { name: "CI", status: "completed", conclusion: "success", head_sha: sha },
      { name: "CodeQL", status: "completed", conclusion: "success", head_sha: sha },
    ],
    artifacts: { status: "validated", headSha: sha },
  };
  assert.equal(validateAcceptance(evidence).valid, true);
  assert.throws(() => validateAcceptance({ ...evidence, checks: evidence.checks.map(({ head_sha: _sha, ...check }) => check) }), /SHA/);
  assert.throws(() => validateAcceptance({ ...evidence, actualSha: "b".repeat(40) }), /differs from current HEAD/);
  assert.throws(() => validateAcceptance({ ...evidence, checks: [...evidence.checks, { name: "Perf", status: "completed", conclusion: "neutral" }], requiredChecks: ["CI", "Perf"] }), /not completed success/);
  assert.throws(() => validateAcceptance({ ...evidence, checks: [{ ...evidence.checks[0], head_sha: "b".repeat(40) }, evidence.checks[1]] }), /stale/);
});

test("manifest verifies SHA, run ID, required files and file digests", () => {
  const path = join(tempRoot, "performance-results.json");
  writeFileSync(path, '{"ok":true}\\n');
  const file = relative(process.cwd(), path);
  const sha = "c".repeat(40);
  const manifest = buildEvidenceManifest({ headSha: sha, runId: 12345, files: [{ path: file }] });
  assert.equal(validateEvidenceManifest(manifest, { expectedSha: sha, expectedRunId: 12345, requiredFiles: [file] }).valid, true);
  assert.throws(() => validateEvidenceManifest(manifest, { expectedSha: "d".repeat(40) }), /stale/);
  assert.throws(() => validateEvidenceManifest(manifest, { expectedSha: sha, expectedRunId: 1 }), /run ID mismatch/);
  writeFileSync(path, '{"ok":false}\\n');
  assert.throws(() => validateEvidenceManifest(manifest, { expectedSha: sha }), /changed/);
});

test("deadline controller terminates a long-running child", async () => {
  const result = await runBoundedCommand({
    command: process.execPath, args: ["-e", "setTimeout(() => {}, 5000)"], cwd: tempRoot,
    deadlineAt: future(0.15), maxAttempts: 1, forwardOutput: false,
  });
  assert.equal(result.status, "timed_out");
  assert.equal(result.reason, "deadline_killed_process");
});

test("loop detection prevents repeated transient failures", async () => {
  const result = await runBoundedCommand({
    command: process.execPath, args: ["-e", "process.stderr.write('same error');process.exit(75)"], cwd: tempRoot,
    deadlineAt: future(5), maxAttempts: 3, idempotent: true, taskKind: "generic",
    retryKind: "transient_network", retryExitCodes: [75], forwardOutput: false,
  });
  assert.equal(result.status, "failed");
  assert.equal(result.reason, "repeated_state_fingerprint");
  assert.equal(result.attempts, 2);
});

test("attempt budget caps changing transient failures at three", async () => {
  const countFile = join(tempRoot, "count.txt");
  const source = "const fs=require('node:fs');const p=" + JSON.stringify(countFile) +
    ";const n=Number(fs.existsSync(p)?fs.readFileSync(p,'utf8'):0)+1;fs.writeFileSync(p,String(n));process.stderr.write('try '+n);process.exit(75)";
  const result = await runBoundedCommand({
    command: process.execPath, args: ["-e", source], cwd: tempRoot, deadlineAt: future(5),
    maxAttempts: 3, idempotent: true, taskKind: "generic", retryKind: "transient_network",
    retryExitCodes: [75], forwardOutput: false,
  });
  assert.equal(result.reason, "attempt_budget_exhausted");
  assert.equal(result.attempts, 3);
  assert.equal(readFileSync(countFile, "utf8"), "3");
});


test("performance evidence manifest must be in the artifact upload, not only generated", () => {
  const fixture = join(tempRoot, "workflow-policy");
  mkdirSync(join(fixture, "server/src"), { recursive: true });
  mkdirSync(join(fixture, "client/src"), { recursive: true });
  cpSync(".github", join(fixture, ".github"), { recursive: true });
  for (const file of ["package.json", "docker-compose.yml"]) cpSync(file, join(fixture, file));
  const workflow = join(fixture, ".github/workflows/performance.yml");
  const content = readFileSync(workflow, "utf8");
  const uploadLine = "            acceptance-evidence-manifest.json\n";
  assert.ok(content.includes(uploadLine), "workflow must upload the manifest");
  const scan = () => spawnSync(process.execPath, [resolve("scripts/static-security-check.mjs")], { cwd: fixture, encoding: "utf8" });
  assert.equal(scan().status, 0);
  writeFileSync(workflow, content.replace(uploadLine, ""));
  const rejected = scan();
  assert.equal(rejected.status, 1);
  assert.match(rejected.stdout, /performance-evidence-upload/);
});


test("spawn callback failures wait for child termination before rejecting", async () => {
  let childPid;
  await assert.rejects(runBoundedCommand({
    command: process.execPath, args: ["-e", "setInterval(() => {}, 1000)"], cwd: tempRoot,
    deadlineAt: future(5), forwardOutput: false,
    onSpawn: pid => { childPid = pid; throw new Error("ledger write failed"); },
  }), /ledger write failed/);
  assert.ok(childPid);
  assert.throws(() => process.kill(childPid, 0), { code: "ESRCH" });
});

test("controller validation failures leave a blocked task rather than running", async () => {
  const path = join(tempRoot, "failed-controller.json");
  writeFileSync(path, JSON.stringify({ schemaVersion: 1, revision: 1, tasks: [task()] }));
  await assert.rejects(runTask(path, "task-1", null, [], null, []), /Concrete command/);
  const persisted = JSON.parse(readFileSync(path, "utf8")).tasks[0];
  assert.equal(persisted.status, "blocked");
  assert.equal(persisted.childPid, null);
  assert.equal(persisted.blockedReason, "controller_error");
});


test("CLI creates tasks with validated exclusive-action ownership", () => {
  const path = join(tempRoot, "exclusive-cli.json");
  const args = [resolve("scripts/orchestration-control.mjs"), "add-task", path,
    "--id", "exclusive-task", "--title", "Scoped task", "--kind", "generic",
    "--deadline-at", future(30), "--max-attempts", "1", "--idempotent", "false",
    "--exclusive-actions", "release-publication"];
  const created = spawnSync(process.execPath, args, { encoding: "utf8" });
  assert.equal(created.status, 0, created.stderr);
  assert.deepEqual(JSON.parse(readFileSync(path, "utf8")).tasks[0].exclusiveActions, ["release-publication"]);
  const invalid = spawnSync(process.execPath, [...args.slice(0, -1), "INVALID ACTION"], { encoding: "utf8" });
  assert.equal(invalid.status, 1);
  assert.match(invalid.stderr, /Invalid exclusive action/);
});


test("exclusive claims recheck the live ledger inside the atomic transition", () => {
  const path = join(tempRoot, "exclusive-claims.json");
  const first = task({ id: "one", exclusiveActions: ["shared-operation"] });
  const second = task({ id: "two", exclusiveActions: ["shared-operation"] });
  writeFileSync(path, JSON.stringify({ schemaVersion: 1, revision: 1, tasks: [first, second] }));
  // Both callers have the original queued revision before either claims it.
  claimTask(path, first.id, first.revision);
  assert.throws(() => claimTask(path, second.id, second.revision), /Exclusive action conflict/);
  assert.equal(JSON.parse(readFileSync(path, "utf8")).tasks[1].status, "queued");
});


for (const exitNormally of [false, true]) {
test("descendant cleanup after " + (exitNormally ? "successful leader exit" : "deadline"), { skip: process.platform !== "linux" }, async () => {
  const pidFile = join(tempRoot, "descendant-" + exitNormally + ".pid");
  const descendant = "process.on('SIGTERM',()=>{});process.send('ready');process.disconnect();setInterval(()=>{},1000)";
  const leader = "const{spawn}=require('node:child_process');const c=spawn(process.execPath,['-e'," + JSON.stringify(descendant) +
    "],{stdio:['ignore','ignore','ignore','ipc']});c.once('message',()=>{require('node:fs').writeFileSync(" + JSON.stringify(pidFile) + ",String(c.pid));if(" + exitNormally + ")process.exit(0)});setInterval(()=>{},1000)";
  let childPid;
  const isRunning = pid => {
    try { return !/^[^)]*\) Z /.test(readFileSync("/proc/" + pid + "/stat", "utf8")); }
    catch (error) { if (error.code === "ENOENT") return false; throw error; }
  };
  try {
    const result = await runBoundedCommand({ command: process.execPath, args: ["-e", leader], cwd: tempRoot, deadlineAt: future(exitNormally ? 5 : 1), forwardOutput: false });
    assert.equal(result.status, exitNormally ? "succeeded" : "timed_out");
    childPid = Number(readFileSync(pidFile, "utf8"));
    const terminationDeadline = Date.now() + 1_000;
    while (isRunning(childPid) && Date.now() < terminationDeadline) await new Promise(resolve => setImmediate(resolve));
    assert.equal(isRunning(childPid), false, "descendant survived forced cleanup");
  } finally {
    if (childPid) { try { process.kill(childPid, "SIGKILL"); } catch {} }
  }
});
}



test("recovery terminates a verified orphan and blocks re-execution", { skip: process.platform !== "linux" }, async () => {
  const child = spawn(process.execPath, ["-e", "setInterval(()=>{},1000)"], { detached: true, stdio: "ignore" });
  const closed = new Promise(resolve => child.once("close", resolve));
  const path = join(tempRoot, "orphan-task.json");
  try {
    writeFileSync(path, JSON.stringify({ schemaVersion: 1, revision: 1, tasks: [task({
      status: "running", childPid: child.pid, childIdentity: processIdentity(child.pid), controllerIdentity: null,
    })] }));
    await assert.rejects(runTask(path, "task-1", null, [], process.execPath, []), /Interrupted task/);
    const persisted = JSON.parse(readFileSync(path, "utf8")).tasks[0];
    assert.equal(persisted.status, "blocked");
    assert.equal(persisted.childPid, null);
    await closed;
    assert.throws(() => process.kill(child.pid, 0), { code: "ESRCH" });
  } finally {
    try { process.kill(-child.pid, "SIGKILL"); } catch {}
    await closed;
  }
});


for (const protection of ["active-controller", "wrong-identity", "protected-operation"]) {
  test("orphan recovery refuses " + protection, { skip: process.platform !== "linux" }, async () => {
    const child = spawn(process.execPath, ["-e", "setInterval(()=>{},1000)"], { detached: true, stdio: "ignore" });
    const closed = new Promise(resolve => child.once("close", resolve));
    const path = join(tempRoot, protection + ".json");
    try {
      const identity = processIdentity(child.pid);
      writeFileSync(path, JSON.stringify({ schemaVersion: 1, revision: 1, tasks: [task({
        status: "running", childPid: child.pid,
        childIdentity: protection === "wrong-identity" ? { ...identity, startTime: "wrong" } : identity,
        controllerIdentity: protection === "active-controller" ? processIdentity(process.pid) : null,
        kind: protection === "protected-operation" ? "migration" : "generic",
      })] }));
      await assert.rejects(runTask(path, "task-1", null, [], process.execPath, []), /controller is alive|identity is unverified|Protected orphan/);
      assert.doesNotThrow(() => process.kill(child.pid, 0));
      assert.equal(JSON.parse(readFileSync(path, "utf8")).tasks[0].status, "running");
    } finally {
      try { process.kill(-child.pid, "SIGKILL"); } catch {}
      await closed;
    }
  });
}


test("a live controller retains its claim between child processes", { skip: process.platform !== "linux" }, async () => {
  const path = join(tempRoot, "between-attempts.json");
  writeFileSync(path, JSON.stringify({ schemaVersion: 1, revision: 1, tasks: [task({
    status: "running", childPid: null, controllerIdentity: processIdentity(process.pid),
  })] }));
  await assert.rejects(runTask(path, "task-1", null, [], process.execPath, []), /controller is alive/);
  assert.equal(JSON.parse(readFileSync(path, "utf8")).tasks[0].status, "running");
});
