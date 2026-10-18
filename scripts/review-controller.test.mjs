import test from "node:test";
import assert from "node:assert/strict";
import { eventKey, normalizeEvent, shouldProcess, repairPermission, mergeEligibility } from "./review-controller.mjs";

const sha = "a".repeat(40);
const base = { eventName: "pull_request_review", action: "submitted", delivery: "d1", repository: { full_name: "whoami22888/isles-of-mythos" }, pull_request: { number: 7, head: { sha } }, review: { id: 9 } };

test("normalizes review, comment and relevant CI events to an exact PR head", () => {
  assert.equal(normalizeEvent(base).kind, "review");
  assert.equal(normalizeEvent({ ...base, eventName: "pull_request_review_comment", action: "created", comment: { id: 3 } }).kind, "review_comment");
  assert.equal(normalizeEvent({ eventName: "workflow_run", action: "completed", workflow_run: { id: 4, event: "pull_request", conclusion: "failure", name: "CI" }, pullRequestNumber: 7, headSha: sha }).kind, "ci_failure");
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
  const args = { headSha: sha, actualSha: sha, checks, requiredChecks: ["CI"], aiApproved: true, visualRequired: true, visualAccepted: true, mergeable: true };
  assert.deepEqual(mergeEligibility(args), { eligible: true, reason: "all_gates_passed" });
  assert.equal(mergeEligibility({ ...args, checks: [{ ...checks[0], head_sha: "b".repeat(40) }] }).reason, "required_check_not_green:CI");
  assert.equal(mergeEligibility({ ...args, visualAccepted: false }).reason, "visual_acceptance_missing");
});
