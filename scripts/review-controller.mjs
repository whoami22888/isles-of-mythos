#!/usr/bin/env node

import { createHash } from "node:crypto";

const shaRE = /^[0-9a-f]{40}$/i;
const allowedReviewActions = new Set(["submitted", "edited", "dismissed"]);
const allowedCommentActions = new Set(["created", "edited", "deleted"]);
const relevantConclusions = new Set(["failure", "timed_out", "cancelled", "action_required"]);

export function eventKey(event) {
  const source = {
    delivery: event?.delivery ?? event?.github?.eventId ?? null,
    event: event?.eventName ?? event?.github?.eventName ?? null,
    action: event?.action ?? null,
    repository: event?.repository?.full_name ?? event?.repository ?? null,
    pullRequest: event?.pull_request?.number ?? event?.pullRequestNumber ?? null,
    review: event?.review?.id ?? event?.reviewId ?? null,
    comment: event?.comment?.id ?? event?.commentId ?? null,
    run: event?.workflow_run?.id ?? event?.runId ?? null,
    sha: event?.pull_request?.head?.sha ?? event?.headSha ?? null,
  };
  return createHash("sha256").update(JSON.stringify(source)).digest("hex");
}

export function normalizeEvent(event) {
  const type = event?.eventName ?? event?.type ?? "";
  const action = event?.action ?? "";
  const pr = event?.pull_request ?? {};
  const headSha = pr?.head?.sha ?? event?.headSha ?? "";
  const number = pr?.number ?? event?.pullRequestNumber ?? null;
  const review = type === "pull_request_review" && allowedReviewActions.has(action);
  const comment = type === "pull_request_review_comment" && allowedCommentActions.has(action);
  const run = type === "workflow_run" && relevantConclusions.has(event?.workflow_run?.conclusion);
  if (!review && !comment && !run) return { relevant: false, reason: "event_not_relevant", key: eventKey(event) };
  if (!Number.isInteger(number) || !shaRE.test(headSha)) return { relevant: false, reason: "missing_pr_or_exact_head_sha", key: eventKey(event) };
  if (type === "workflow_run" && event?.workflow_run?.event !== "pull_request") return { relevant: false, reason: "run_not_for_pull_request", key: eventKey(event) };
  return { relevant: true, kind: review ? "review" : comment ? "review_comment" : "ci_failure", action, pullRequest: number, headSha, key: eventKey(event), workflow: event?.workflow_run?.name ?? null };
}

export function shouldProcess(event, seenKeys = new Set()) {
  const normalized = normalizeEvent(event);
  if (!normalized.relevant) return { process: false, ...normalized };
  if (seenKeys.has(normalized.key)) return { process: false, reason: "duplicate_event", ...normalized };
  return { process: true, ...normalized };
}

export function repairPermission({ event, repository, headRepository, actor, trustedActors = [] }) {
  const sameRepository = repository && headRepository && repository === headRepository;
  const trusted = trustedActors.includes(actor);
  const normalized = normalizeEvent(event);
  return { allowed: Boolean(normalized.relevant && sameRepository && trusted && normalized.headSha), reason: !normalized.relevant ? normalized.reason : !sameRepository ? "fork_head_not_writable" : !trusted ? "actor_not_trusted" : "repair_allowed" };
}

export function mergeEligibility({ headSha, actualSha, checks = [], requiredChecks = [], aiApproved = false, visualRequired = false, visualAccepted = false, mergeable = false }) {
  if (!shaRE.test(headSha) || headSha !== actualSha) return { eligible: false, reason: "exact_head_sha_mismatch" };
  if (!mergeable) return { eligible: false, reason: "github_reports_not_mergeable" };
  if (!aiApproved) return { eligible: false, reason: "ai_review_not_approved" };
  const checkMap = new Map(checks.map(check => [check.name, check]));
  for (const name of requiredChecks) {
    const check = checkMap.get(name);
    if (!check || check.head_sha !== headSha || check.status !== "completed" || check.conclusion !== "success") return { eligible: false, reason: "required_check_not_green:" + name };
  }
  if (visualRequired && !visualAccepted) return { eligible: false, reason: "visual_acceptance_missing" };
  return { eligible: true, reason: "all_gates_passed" };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const input = process.argv[2] ? JSON.parse(process.argv[2]) : {};
  process.stdout.write(JSON.stringify(normalizeEvent(input)) + "\n");
}
