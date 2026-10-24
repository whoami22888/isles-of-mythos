import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { eventKey, normalizeEvent, shouldProcess, repairPermission, mergeEligibility } from "./review-controller.mjs";

const sha = "a".repeat(40);
const base = { eventName: "pull_request_review", action: "submitted", delivery: "d1", repository: { full_name: "whoami22888/isles-of-mythos" }, pull_request: { number: 7, head: { sha } }, review: { id: 9 } };

test("normalizes review, comment and relevant CI events to an exact PR head", () => {
  assert.equal(normalizeEvent(base).kind, "review");
  assert.equal(normalizeEvent({ ...base, eventName: "pull_request_review_comment", action: "created", comment: { id: 3 } }).kind, "review_comment");
  assert.equal(normalizeEvent({ eventName: "workflow_run", action: "completed", workflow_run: { id: 4, event: "pull_request", conclusion: "failure", name: "CI", head_sha: sha, pull_requests: [{ number: 7 }] } }).kind, "ci_failure");
});

test("deduplicates the same delivery without conflating distinct events", () => {
  const first = shouldProcess(base);
  assert.equal(first.process, true);
  assert.equal(shouldProcess(base, new Set([eventKey(base)])).reason, "duplicate_event");
  assert.notEqual(eventKey(base), eventKey({ ...base, review: { id: 10 } }));
});

test("rejects malformed events, fork repair and untrusted actors", () => {
  assert.equal(normalizeEvent({ ...base, pull_request: { number: 7, head: { sha: "bad" } } }).reason, "missing_pr_or_exact_head_sha");
  assert.equal(repairPermission({ event: base, repository: "whoami22888/isles-of-mythos", headRepository: "someone/fork", actor: "codex", trustedActors: ["codex"] }).reason, "fork_head_not_writable");
  assert.equal(repairPermission({ event: base, repository: "whoami22888/isles-of-mythos", headRepository: "whoami22888/isles-of-mythos", actor: "random", trustedActors: ["codex"] }).reason, "actor_not_trusted");
});

test("merge eligibility requires exact SHA, green required checks, AI and visual gates", () => {
  const checks = [{ name: "CI", status: "completed", conclusion: "success", head_sha: sha }];
  const args = { headSha: sha, actualSha: sha, checks, requiredChecks: ["CI"], aiApproved: true, aiApprovalSha: sha, visualRequired: true, visualAccepted: true, visualAcceptanceSha: sha, mergeable: true };
  assert.deepEqual(mergeEligibility(args), { eligible: true, reason: "all_gates_passed" });
  assert.equal(mergeEligibility({ ...args, checks: [{ ...checks[0], head_sha: "b".repeat(40) }] }).reason, "required_check_not_green:CI");
  assert.equal(mergeEligibility({ ...args, visualAccepted: false }).reason, "visual_acceptance_missing_for_exact_sha");
});

const actualWorkflowRun = { eventName: "workflow_run", action: "completed", workflow_run: { id: 4, event: "pull_request", conclusion: "failure", name: "CI", head_sha: sha, pull_requests: [{ number: 7 }], run_attempt: 1 } };

test("normalizes real GitHub workflow_run and rejects irrelevant events", () => {
  const result = normalizeEvent(actualWorkflowRun);
  assert.equal(result.kind, "ci_failure");
  assert.equal(result.pullRequest, 7);
  assert.equal(result.headSha, sha);
  assert.equal(normalizeEvent({ ...actualWorkflowRun, workflow_run: { ...actualWorkflowRun.workflow_run, conclusion: "success" } }).reason, "event_not_relevant");
  assert.equal(normalizeEvent({ ...actualWorkflowRun, workflow_run: { ...actualWorkflowRun.workflow_run, event: "push" } }).reason, "run_not_for_pull_request");
  assert.equal(normalizeEvent({ ...actualWorkflowRun, workflow_run: { ...actualWorkflowRun.workflow_run, pull_requests: [] } }).reason, "missing_pr_or_exact_head_sha");
});

test("review edits and workflow attempts receive distinct event keys", () => {
  const edited = { ...base, delivery: undefined, action: "edited", review: { id: 9, updated_at: "2026-10-18T01:00:00Z", body: "first" } };
  assert.notEqual(eventKey(edited), eventKey({ ...edited, review: { ...edited.review, body: "changed" } }));
  assert.notEqual(eventKey(actualWorkflowRun), eventKey({ ...actualWorkflowRun, workflow_run: { ...actualWorkflowRun.workflow_run, run_attempt: 2 } }));
});

test("stale AI and visual approvals fail closed", () => {
  const checks = [{ name: "CI", status: "completed", conclusion: "success", head_sha: sha }];
  const args = { headSha: sha, actualSha: sha, checks, requiredChecks: ["CI"], aiApproved: true, aiApprovalSha: sha, visualRequired: true, visualAccepted: true, visualAcceptanceSha: sha, mergeable: true };
  assert.equal(mergeEligibility({ ...args, aiApprovalSha: "b".repeat(40) }).reason, "ai_review_not_approved_for_exact_sha");
  assert.equal(mergeEligibility({ ...args, visualAcceptanceSha: "b".repeat(40) }).reason, "visual_acceptance_missing_for_exact_sha");
  assert.equal(mergeEligibility({ ...args, aiApprovalSha: undefined }).eligible, false);
  assert.equal(mergeEligibility({ ...args, visualAcceptanceSha: undefined }).eligible, false);
});

test("unverified repair fails closed with read-only worker credentials", () => {
  const workflow = readFileSync(".github/workflows/automated-repair-dispatch.yml", "utf8");
  const controller = readFileSync(".github/workflows/automated-review-repair.yml", "utf8");
  assert.match(workflow, /Credentialed repair is disabled/);
  assert.doesNotMatch(workflow, /OPENAI_API_KEY|GITHUB_TOKEN|--full-auto|codex exec/);
  assert.doesNotMatch(workflow, /contents: write|pull-requests: write/);
  assert.match(workflow, /contents: read/);
  assert.match(workflow, /pull-requests: read/);
  assert.match(workflow, /same-repository PR head/);
  assert.match(workflow, /p\.repo !== repo \|\| p\.owner !== owner/);
  assert.match(controller, /Dispatch exact-SHA repair workflow/);
  assert.match(controller, /false &&/);
  assert.match(controller, /actions: write/);
  assert.match(controller, /Bot-authored review events cannot dispatch repair/);
  assert.match(controller, /github\.event\.review\.state == 'approved'/);
  assert.doesNotMatch(workflow, /CODEX_REPAIR_TOKEN|LIM_API_KEY/);
});
