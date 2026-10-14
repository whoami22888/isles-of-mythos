import test, { after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { join, relative } from "node:path";
import {
  ownershipCheck, buildEvidenceManifest, retryDecision, runBoundedCommand, fingerprint,
  validateAcceptance, validateEvidenceManifest, validateLedger,
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
  assert.throws(() => validateLedger({ schemaVersion: 1, revision: 1, tasks: [task(), task()] }), /Duplicate/);
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
