import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  BASE_CHECKS, CODEX_REVIEWER, changedPaths, modifiesProtectedVerification, applicableChecks, visualRequired,
  trustedCodexReceipt, hasBlockingCodexFinding, requiredRunsPassed
} from "./auto-merge-gate.mjs";

const sha = "a".repeat(40);
const receipt = { commit_id: sha, state: "COMMENTED",
  user: { login: CODEX_REVIEWER }, body: "<!-- codex-review-receipt:v1 -->" };
const run = name => ({ name, head_sha: sha, event: "pull_request", id: 5,
  status: "completed", conclusion: "success" });

test("only current-SHA, active, exact trusted Codex bot review counts", () => {
  assert.equal(trustedCodexReceipt(receipt, sha), true);
  for (const counterfeit of [
    { ...receipt, user: { login: "attacker-codex" } },
    { ...receipt, user: { login: "codex-review-bot" } },
    { ...receipt, state: "DISMISSED" },
    { ...receipt, state: "PENDING" },
    { ...receipt, commit_id: "b".repeat(40) },
    { ...receipt, body: "Review submitted" }
  ]) assert.equal(trustedCodexReceipt(counterfeit, sha), false);
});

test("final-head actionable finding always blocks; stale SHA does not", () => {
  const finding = { commit_id: sha, user: { login: CODEX_REVIEWER },
    body: "<!-- codex-code-review-finding:v1 -->" };
  assert.equal(hasBlockingCodexFinding([finding], sha), true);
  assert.equal(hasBlockingCodexFinding([{ ...finding, commit_id: "b".repeat(40) }], sha), false);
  assert.equal(hasBlockingCodexFinding([{ ...finding, user: { login: "attacker-codex" } }], sha), false);
  // GitHub reanchors old comments to the current head but preserves the original commit.
  assert.equal(hasBlockingCodexFinding([{
    ...finding, commit_id: sha, original_commit_id: "b".repeat(40)
  }], sha), false);
  assert.equal(hasBlockingCodexFinding([{
    ...finding, commit_id: "b".repeat(40), original_commit_id: sha
  }], sha), true);
});

test("Godot client edits require client build and visual evidence", () => {
  const checks = applicableChecks(["client-godot/project.godot", "client-godot/shaders/ocean.gdshader"]);
  assert.ok(checks.includes("IOM-00 Godot client"));
  assert.ok(checks.includes("Godot visual evidence"));
  assert.equal(visualRequired(["client-godot/project.godot"]), true);
  assert.equal(visualRequired(["client-godot/shaders/ocean.gdshader"]), true);
  assert.equal(visualRequired(["docs/graphics/QUALITY.md"]), true);
  assert.equal(visualRequired(["art/logo.svg"]), true);
  assert.equal(visualRequired(["server/src/health.ts"]), false);
});

test("art provenance and coastal staging checks follow their path filters", () => {
  const provenance = applicableChecks(["client-godot/assets/water.png"]);
  assert.ok(provenance.includes("IOM-00 Godot client"));
  assert.ok(provenance.includes("Godot visual evidence"));
  assert.ok(provenance.includes("Godot external art provenance"));
  assert.ok(applicableChecks(["scripts/fetch_verified_godot_assets.py"]).includes("Godot external art provenance"));
  assert.ok(applicableChecks(["scripts/test_stage_polyhaven_coast.py"]).includes("Stage Poly Haven coastal PBR candidate"));
  assert.deepEqual(applicableChecks(["server/src/health.ts"]), BASE_CHECKS);
});

test("pending or stale required workflow cannot be accepted", () => {
  assert.deepEqual(requiredRunsPassed(BASE_CHECKS.map(run), BASE_CHECKS, sha), { pass: true });
  const pending = [...BASE_CHECKS.map(run), { ...run("CI"), id: 6, status: "in_progress" }];
  assert.equal(requiredRunsPassed(pending, BASE_CHECKS, sha).pass, false);
  assert.equal(requiredRunsPassed([{ ...run("CI"), head_sha: "b".repeat(40) }], ["CI"], sha).pass, false);
  assert.equal(requiredRunsPassed([], ["IOM-00 Godot client"], sha).pass, false);
  assert.equal(requiredRunsPassed([{ ...run("CI"), event: "push" }], ["CI"], sha).pass, false);
});

test("workflow reviews and required Godot completions trigger trusted-main reconciliation", () => {
  const policy = readFileSync(".github/workflows/verified-codex-auto-merge.yml", "utf8");
  assert.match(policy, /Godot external art provenance/);
  assert.match(policy, /IOM-00 Godot client/);
  assert.match(policy, /Godot visual evidence/);
  assert.match(policy, /Stage Poly Haven coastal PBR candidate/);
  assert.match(policy, /pull_request_review_comment:/);
  assert.match(policy, /github\.event\.repository\.default_branch/);
  assert.match(policy, /persist-credentials:\s*false/);
  assert.match(policy, /^  contents:\s*read$/m);
});

test("renames retain the source path for Godot, provenance and visual gates", () => {
  const paths = changedPaths([{ filename: "docs/water.txt", previous_filename: "client-godot/assets/water.png", status: "renamed" }]);
  assert.ok(paths.includes("client-godot/assets/water.png"));
  assert.ok(applicableChecks(paths).includes("IOM-00 Godot client"));
  assert.ok(applicableChecks(paths).includes("Godot visual evidence"));
  assert.ok(applicableChecks(paths).includes("Godot external art provenance"));
  assert.equal(visualRequired(paths), true);
  assert.throws(() => changedPaths([{ filename: "docs/water.txt", status: "renamed" }]), /source path/);
});

test("changes to required workflows or gate policy always need manual verification", () => {
  for (const file of [".github/workflows/ci.yml", ".github/workflows/verified-codex-auto-merge.yml",
      ".github/workflows/godot-visual-evidence.yml", "scripts/static-security-check.mjs",
      "package.json", "AGENTS.md", ".project/VERIFICATION-STANDARD.md"])
    assert.equal(modifiesProtectedVerification([file]), true, file);
  assert.equal(modifiesProtectedVerification(["server/src/index.ts"]), false);
});

test("owner visual-acceptance comment can retrigger trusted-main merge reconciliation", () => {
  const policy = readFileSync(".github/workflows/verified-codex-auto-merge.yml", "utf8");
  assert.match(policy, /issue_comment:/);
  assert.match(policy, /github\.event\.issue\.pull_request != null/);
  assert.match(policy, /github\.event\.comment\.user\.login == github\.repository_owner/);
  assert.match(policy, /VISUAL-ACCEPTED:/);
  assert.match(policy, /github\.event\.issue\.number/);
});
