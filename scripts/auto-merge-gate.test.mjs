import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  BASE_CHECKS, CODEX_REVIEWER, changedPaths, modifiesProtectedVerification, applicableChecks, visualRequired,
  trustedCodexReceipt, hasBlockingCodexFinding, requiredRunsPassed, resolveMergeability
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

test("IOM-07 profiler is required for every profiler source and evidence validator", () => {
  for (const path of ["client-godot/scripts/mobile_frame_metrics.gd",
      "client-godot/scenes/sculpted_terrain_preview.tscn",
      "client-godot/tests/mobile_frame_capture.gd",
      "client-godot/tests/mobile_frame_metrics_test.gd",
      "scripts/validate_iom07_frame_evidence.py",
      "scripts/test_validate_iom07_frame_evidence.py",
      ".github/workflows/iom07-mobile-frame-evidence.yml"])
    assert.ok(applicableChecks([path]).includes("IOM-07 mobile frame evidence"), path);
  for (const path of ["client-godot/scripts/mobile_frame_metrics.gd",
      "client-godot/shaders/coastal_shore_sampler.gdshaderinc",
      "client-godot/scripts/coastal_shore_heightfield.gd",
      "client-godot/tests/coastal_shore_heightfield_test.gd",
      "client-godot/tests/coastal_ocean_integration_test.gd",
      "client-godot/tests/coastal_ship_fx_integration_test.gd",
      "client-godot/tests/profile_moving_coastal_scene.gd",
      "client-godot/scripts/coastal_ship_fx_controller.gd",
      "client-godot/scripts/realistic_coastal_slice.gd",
      "client-godot/scripts/ship_wake_effect.gd",
      "client-godot/scripts/ship_bow_spray_effect.gd",
      "client-godot/scenes/realistic_coastal_fx_slice.tscn",
      "client-godot/shaders/ocean_surface.gdshader",
      "client-godot/project.godot",
      "client-godot/assets/external/polyhaven/coastal_cliff_01/coastal_cliff_01_1k.gltf",
      "client-godot/assets/external/polyhaven/dutch_ship_medium/textures/dutch_ship_medium_sails_diff_1k.jpg",
      "scripts/validate_iom07_coastal_profile.py",
      "scripts/test_validate_iom07_coastal_profile.py",
      "scripts/test_iom07_coastal_profile_workflow.py",
      ".github/workflows/iom07-moving-coastal-profile.yml"])
    assert.ok(applicableChecks([path]).includes("IOM-07 real moving coastal scene profiler"), path);
  assert.ok(applicableChecks(["client-godot/tests/mobile_frame_future_regression.gd"]).includes("IOM-07 mobile frame evidence"));
  assert.ok(!applicableChecks(["client-godot/tests/mobile_frame_nested/test.gd"]).includes("IOM-07 mobile frame evidence"));
  assert.ok(!applicableChecks(["client-godot/tests/mobile_frame_invalid.txt"]).includes("IOM-07 mobile frame evidence"));
  const shared = applicableChecks(["client-godot/scripts/mobile_frame_metrics.gd"]);
  assert.ok(shared.includes("IOM-07 mobile frame evidence"));
  assert.ok(shared.includes("IOM-07 real moving coastal scene profiler"));
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

test("both applicable IOM-07 profilers reject missing, failed, pending, cancelled, skipped and stale runs", () => {
  for (const name of ["IOM-07 mobile frame evidence", "IOM-07 real moving coastal scene profiler"]) {
    assert.deepEqual(requiredRunsPassed([run(name)], [name], sha), { pass: true });
    assert.equal(requiredRunsPassed([], [name], sha).pass, false);
    for (const bad of [
      { ...run(name), conclusion: "failure" },
      { ...run(name), status: "in_progress", conclusion: null },
      { ...run(name), status: "queued", conclusion: null },
      { ...run(name), conclusion: "cancelled" },
      { ...run(name), conclusion: "skipped" },
      { ...run(name), conclusion: "timed_out" },
      { ...run(name), conclusion: "neutral" },
      { ...run(name), head_sha: "b".repeat(40) }
    ]) assert.equal(requiredRunsPassed([bad], [name], sha).pass, false);
    assert.equal(requiredRunsPassed([{ ...run(name), event: "push" }], [name], sha).pass, false);
    assert.equal(requiredRunsPassed([run(name), { ...run(name), id: 6, status: "in_progress", conclusion: null }], [name], sha).pass, false);
  }
});

test("workflow reviews and required Godot completions trigger trusted-main reconciliation", () => {
  const policy = readFileSync(".github/workflows/verified-codex-auto-merge.yml", "utf8");
  assert.match(policy, /Godot external art provenance/);
  assert.match(policy, /IOM-00 Godot client/);
  assert.match(policy, /Godot visual evidence/);
  assert.match(policy, /Stage Poly Haven coastal PBR candidate/);
  assert.match(policy, /IOM-07 mobile frame evidence/);
  assert.match(policy, /IOM-07 real moving coastal scene profiler/);
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


test("unknown GitHub mergeability is retried at most three times", async () => {
  let calls = 0;
  const delays = [];
  const result = await resolveMergeability(async () => {
    calls++;
    return calls === 3
      ? { mergeable: true, mergeable_state: "clean" }
      : { mergeable: null, mergeable_state: "unknown" };
  }, async ms => { delays.push(ms); });
  assert.equal(calls, 3);
  assert.deepEqual(delays, [1000, 2000]);
  assert.equal(result.mergeable_state, "clean");
});

test("unknown mergeability never spins forever, real conflicts never retry", async () => {
  let calls = 0;
  const unresolved = await resolveMergeability(async () => {
    calls++;
    return { mergeable: null, mergeable_state: "unknown" };
  }, async () => {});
  assert.equal(calls, 3);
  assert.equal(unresolved.mergeable, null);
  calls = 0;
  const conflicting = await resolveMergeability(async () => {
    calls++;
    return { mergeable: false, mergeable_state: "dirty" };
  }, async () => { throw Error("Conflicts must not trigger retries"); });
  assert.equal(calls, 1);
  assert.equal(conflicting.mergeable, false);
});
