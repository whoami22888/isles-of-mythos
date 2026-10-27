#!/usr/bin/env node
// Trusted-main, fail-closed Codex review/CI/visual integration gate.
// Runs with a short-lived GitHub token, never executing files from a pull-request head.
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const BASE_CHECKS = Object.freeze([
  "CI", "Codacy Security Scan", "CodeQL Advanced",
  "Static Security Quality", "Performance Acceptance"
]);
export const CODEX_REVIEWER = "chatgpt-codex-connector[bot]";
const SHA = /^[a-f0-9]{40}$/i;
const BLOCKING_CODEX_VERDICT = /(?:^|\n)\s*(?:>\s*)?(?:#{1,6}\s*)?(?:[-*]\s*)?(?:\*\*)?(?:(?:DISPOSITION|VERDICT|REVIEW STATUS|REVIEW RESULT|STATUS)\s*(?:\*\*)?\s*:\s*(?:\*\*)?\s*)?(?:CHANGES REQUIRED|FAIL(?:ED)?|REJECTED|P[012]\b)/im;
const PASSING_CODEX_VERDICT = /(?:^|\n)\s*(?:#{1,6}\s*)?(?:[-*]\s*)?(?:\*\*)?(?:DISPOSITION|VERDICT)\s*:\s*(?:PASS|APPROVED)(?:\*\*)?(?=\s|$)/im;
// Fail closed on any structured Codex decision field that is not unambiguously
// positive. This prevents novel negative statuses from contradicting a PASS
// receipt without requiring an ever-growing list of negative synonyms.
const CODEX_DECISION_FIELD = /(?:^|\n)\s*(?:>\s*)?(?:#{1,6}\s*)?(?:[-*]\s*)?(?:\*\*)?(?:DISPOSITION|VERDICT|REVIEW STATUS|REVIEW RESULT|STATUS)(?:\*\*)?\s*:\s*(?:\*\*)?\s*([^\r\n]+)/gim;
const POSITIVE_CODEX_DECISION = /^(?:PASS|APPROVED)(?:\*\*)?[.!]?$/i;
function hasContradictoryCodexDecision(body) {
  if (typeof body !== "string") return false;
  return [...body.matchAll(CODEX_DECISION_FIELD)].some(match =>
    !POSITIVE_CODEX_DECISION.test(match[1].trim()));
}
const ART_PROVENANCE_SCRIPTS = new Set([
  "scripts/validate_godot_assets.py",
  "scripts/test_godot_asset_validator.py",
  "scripts/test_godot_asset_fetcher.py",
  "scripts/fetch_verified_godot_assets.py"
]);
const STAGE_SCRIPTS = new Set([
  "scripts/stage_polyhaven_coast.py",
  "scripts/test_stage_polyhaven_coast.py"
]);
const IOM07_FRAME_PATHS = new Set([
  "client-godot/scripts/mobile_frame_metrics.gd",
  "client-godot/scenes/sculpted_terrain_preview.tscn",
  "client-godot/tests/mobile_frame_capture.gd",
  "client-godot/tests/mobile_frame_metrics_test.gd",
  "scripts/validate_iom07_frame_evidence.py",
  "scripts/test_validate_iom07_frame_evidence.py",
  ".github/workflows/iom07-mobile-frame-evidence.yml"
]);
const IOM07_COAST_PATHS = new Set([
  "client-godot/project.godot",
  "client-godot/scripts/mobile_frame_metrics.gd",
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
  "scripts/validate_iom07_coastal_profile.py",
  "scripts/test_validate_iom07_coastal_profile.py",
  "scripts/test_iom07_coastal_profile_workflow.py",
  ".github/workflows/iom07-moving-coastal-profile.yml"
]);
const IOM07_COAST_PATH_PREFIXES = Object.freeze([
  "client-godot/assets/external/"
]);

// All executed coastal-capture source and validator dependencies must trigger
// the dedicated workflow and be required by the protected merge gate.
const COASTAL_FX_PATHS = new Set([
  "client-godot/scenes/realistic_coastal_fx_slice.tscn",
  "client-godot/scenes/realistic_coastal_slice.tscn",
  "client-godot/scripts/coastal_ship_fx_controller.gd",
  "client-godot/scripts/ship_wake_effect.gd",
  "client-godot/shaders/ship_wake_foam.gdshader",
  "client-godot/scripts/ship_bow_spray_effect.gd",
  "client-godot/shaders/ship_bow_spray.gdshader",
  "client-godot/scripts/realistic_coastal_slice.gd",
  "client-godot/tests/coastal_ship_fx_integration_test.gd",
  "client-godot/tests/render_coastal_fx_sequence.gd",
  "client-godot/tests/coastal_ocean_integration_test.gd",
  "client-godot/tests/coastal_shore_heightfield_test.gd",
  "client-godot/scripts/coastal_shore_heightfield.gd",
  "client-godot/shaders/coastal_shore_sampler.gdshaderinc",
  "client-godot/shaders/ocean_surface.gdshader",
  ".github/workflows/iom-coastal-ship-fx.yml",
  "client-godot/project.godot",
  "client-godot/tests/realistic_coastal_slice_test.gd",
  "scripts/check_capture_continuity.py",
  "scripts/tests/test_capture_continuity.py"
]);
const COASTAL_FX_PREFIXES = Object.freeze(["client-godot/assets/external/"]);

const VISUAL_EVIDENCE_SCRIPTS = new Set([
  "scripts/graphics_quality_preflight.py",
  "scripts/test_graphics_quality_preflight.py",
  "scripts/stage_polyhaven_models.py",
  "scripts/test_stage_polyhaven_models.py",
  "scripts/stage_polyhaven_coast.py",
  "scripts/test_stage_polyhaven_coast.py"
]);

// Validation and provenance scripts define the evidence admitted by protected
// workflows. They require manual integration just like the workflows themselves.
const PROTECTED_EVIDENCE_SCRIPTS = new Set([
  ...ART_PROVENANCE_SCRIPTS,
  ...STAGE_SCRIPTS,
  ...VISUAL_EVIDENCE_SCRIPTS,
  "scripts/validate_iom07_frame_evidence.py",
  "scripts/test_validate_iom07_frame_evidence.py",
  "scripts/validate_iom07_coastal_profile.py",
  "scripts/test_validate_iom07_coastal_profile.py",
  "scripts/test_iom07_coastal_profile_workflow.py",
  "scripts/isles_graphics_gate.py",
  "scripts/test_isles_graphics_gate.py",
  "scripts/check_capture_continuity.py",
  "scripts/tests/test_capture_continuity.py"
]);

export function changedPaths(files) {
  if (!Array.isArray(files)) throw Error("Invalid changed-file collection");
  return files.flatMap(f => {
    if (!f?.filename) throw Error("Changed-file entry missing destination");
    if (f.status === "renamed") {
      if (!f.previous_filename) throw Error("Renamed file lacks source path");
      return [f.filename, f.previous_filename];
    }
    return [f.filename];
  });
}

// Automatic integration must never approve changes to its own evidence sources.
export function modifiesProtectedVerification(paths) {
  const guarded = new Set([
    "AGENTS.md", ".project/VERIFICATION-STANDARD.md",
    "docs/ART_DIRECTION_STANDARD.md",
    "docs/graphics/CINEMATIC_QUALITY_FLOOR.md",
    "docs/graphics/REAL_RENDER_DELIVERABLE_GATE.md",
    "docs/PLAYER_EXPERIENCE_QUALITY_STANDARD.md",
    "docs/VISUAL_REFERENCE_INDEX.md",
    "package.json", "package-lock.json",
    "scripts/static-security-check.mjs", "scripts/orchestration-control.mjs",
    "scripts/auto-merge-gate.mjs", "scripts/auto-merge-gate.test.mjs",
    "scripts/review-controller.mjs", "scripts/review-controller.test.mjs"
  ]);
  return paths.some(p => guarded.has(p) || PROTECTED_EVIDENCE_SCRIPTS.has(p) ||
    p.startsWith(".github/workflows/") ||
    p.startsWith(".github/actions/"));
}

export function applicableChecks(paths) {
  if (!Array.isArray(paths) || paths.some(p => typeof p !== "string")) throw Error("Invalid changed paths");
  const required = new Set(BASE_CHECKS);
  if (paths.some(p => p.startsWith("client-godot/") || p === ".github/workflows/godot-iom-00.yml"))
    required.add("IOM-00 Godot client");
  if (paths.some(p => p.startsWith("client-godot/") || VISUAL_EVIDENCE_SCRIPTS.has(p) ||
      p === ".github/workflows/godot-visual-evidence.yml"))
    required.add("Godot visual evidence");
  if (paths.some(p => p.startsWith("client-godot/assets/") ||
       ART_PROVENANCE_SCRIPTS.has(p) || p === ".github/workflows/godot-art-provenance.yml"))
    required.add("Godot external art provenance");
  if (paths.some(p => STAGE_SCRIPTS.has(p) || p === ".github/workflows/godot-stage-coast.yml"))
    required.add("Stage Poly Haven coastal PBR candidate");
  if (paths.some(p => IOM07_FRAME_PATHS.has(p) ||
      /^client-godot\/tests\/mobile_frame_[^/]*\.gd$/.test(p)))
    required.add("IOM-07 mobile frame evidence");
  if (paths.some(p => IOM07_COAST_PATHS.has(p) ||
      IOM07_COAST_PATH_PREFIXES.some(prefix => p.startsWith(prefix))))
    required.add("IOM-07 real moving coastal scene profiler");
  if (paths.some(p => COASTAL_FX_PATHS.has(p) ||
      COASTAL_FX_PREFIXES.some(prefix => p.startsWith(prefix))))
    required.add("IOM Coastal Ship FX Integration");
  return [...required];
}

export function visualRequired(paths) {
  return paths.some(p =>
    p.startsWith("client-godot/") ||
    /(^|\/)(graphics|art|assets|renders|cinematics)(\/|$)/i.test(p) ||
    /\.(gd|gdshader|shader|tscn|tres|svg|png|jpe?g|webp|mp4|mov|glb|gltf|blend|fbx)$/i.test(p)
  );
}

export function trustedCodexReceipt(review, sha) {
  const body = review?.body;
  if (typeof body !== "string") return false;
  // A bot receipt proves review occurred, not that its verdict passed.
  // A blocking verdict in the review body must not bypass inline-thread checks.
  // A negative verdict cannot be overridden by a separate positive receipt.
  return SHA.test(sha) &&
    review?.commit_id === sha &&
    review?.user?.login === CODEX_REVIEWER &&
    (review?.state === "COMMENTED" || review?.state === "APPROVED") &&
    /<!--\s*codex-review-receipt:v1\s*-->/.test(body) &&
    PASSING_CODEX_VERDICT.test(body) &&
    !hasContradictoryCodexDecision(body) &&
    !BLOCKING_CODEX_VERDICT.test(body);
}

// A positive receipt cannot override a contradictory active bot review on the
// same final SHA. A later blocking review may have no inline review thread.
export function codexReviewsPassed(reviews, sha) {
  if (!Array.isArray(reviews)) throw Error("Codex reviews missing");
  const current = reviews.filter(r => r?.user?.login === CODEX_REVIEWER &&
    r?.commit_id === sha && r?.state !== "DISMISSED");
  if (current.some(r => r.state === "CHANGES_REQUESTED" ||
      (typeof r.body === "string" &&
        (BLOCKING_CODEX_VERDICT.test(r.body) || hasContradictoryCodexDecision(r.body)))))
    return false;
  return current.some(r => trustedCodexReceipt(r, sha));
}

export function isCodexAuthor(login) {
  // REST and GraphQL expose the same GitHub App account with different bot suffixes.
  return login === CODEX_REVIEWER || login === "chatgpt-codex-connector";
}

function isBlockingCodexReview(review) {
  return review?.state === "CHANGES_REQUESTED" ||
    (typeof review?.body === "string" &&
      (BLOCKING_CODEX_VERDICT.test(review.body) || hasContradictoryCodexDecision(review.body)));
}

function hasAuthorizedCodexReviewDisposition(review, issueComments, owner) {
  if (review?.state === "DISMISSED") return true;
  const reviewId = review?.id;
  const reviewSha = review?.commit_id;
  const reviewedAt = Date.parse(review?.submitted_at ?? "");
  if ((typeof reviewId !== "number" && typeof reviewId !== "string") ||
      !SHA.test(reviewSha ?? "") || !Number.isFinite(reviewedAt)) return false;
  const disposition = new RegExp(
    "(?:^|\\r?\\n)<!--\\s*codex-review-disposition:v1\\s*-->\\r?\\n" +
    "CODEX-REVIEW-DISPOSITION:\\s*" + String(reviewId).replace(/[.*+?^${}()|[\\]\\\\]/g, "\\$&") +
    "\\s+RESOLVED\\s+" + reviewSha + "\\s*(?=\\r?$|\\r?\\n)", "m");
  return issueComments.some(comment => {
    const createdAt = Date.parse(comment?.created_at ?? "");
    return comment?.user?.login?.toLowerCase() === owner.toLowerCase() &&
      Number.isFinite(createdAt) && createdAt >= reviewedAt &&
      typeof comment?.body === "string" && disposition.test(comment.body);
  });
}

// PR-level reviews have no GitHub resolution state. An earlier non-inline
// negative Codex review remains blocking unless GitHub dismissed it or the
// repository owner posted a strict, review-id-and-SHA-bound disposition later.
export function hasUndispositionedBlockingCodexReview(reviews, issueComments, owner) {
  if (!Array.isArray(reviews)) throw Error("Codex reviews missing");
  if (!Array.isArray(issueComments)) throw Error("Issue comments missing");
  if (typeof owner !== "string" || !owner) throw Error("Repository owner missing");
  return reviews.some(review => isCodexAuthor(review?.user?.login) &&
    isBlockingCodexReview(review) &&
    !hasAuthorizedCodexReviewDisposition(review, issueComments, owner));
}

// Resolution is a property of a review thread, not of its original commit.
// A newer HEAD or an outdated diff position never disposes of a P0/P1/P2 finding.
export function hasBlockingCodexFinding(threads) {
  if (!Array.isArray(threads)) throw Error("Review threads missing");
  let blocking = false;
  for (const thread of threads) {
    if (typeof thread?.isResolved !== "boolean" ||
        !Array.isArray(thread?.comments?.nodes) ||
        thread.comments.pageInfo?.hasNextPage !== false ||
        thread.comments.nodes.length === 0)
      throw Error("Incomplete review-thread evidence");
    for (const comment of thread.comments.nodes) {
      if (typeof comment?.body !== "string" || typeof comment?.author?.login !== "string")
        throw Error("Incomplete review comment");
      if (!thread.isResolved && isCodexAuthor(comment.author.login) &&
          (/codex-code-review-finding:v1/.test(comment.body) ||
           /\bP[012]\b/i.test(comment.body)))
        blocking = true;
    }
  }
  return blocking;
}

// The GitHub REST review-comments endpoint has no isResolved field. Query
// complete GraphQL thread pages; any partial page, nested comment truncation,
// duplicate thread or API failure must prevent automatic integration.
export async function collectReviewThreads(readPage, maxPages = 20) {
  const threads = [];
  const seen = new Set();
  let after = null;
  for (let page = 0; page < maxPages; page++) {
    const connection = await readPage(after);
    if (!Array.isArray(connection?.nodes) ||
        typeof connection?.pageInfo?.hasNextPage !== "boolean")
      throw Error("Incomplete GitHub review-thread response");
    for (const thread of connection.nodes) {
      if (typeof thread?.id !== "string" || seen.has(thread.id) ||
          typeof thread.isResolved !== "boolean" ||
          !Array.isArray(thread.comments?.nodes) ||
          thread.comments.pageInfo?.hasNextPage !== false ||
          thread.comments.nodes.length === 0)
        throw Error("Incomplete or duplicate GitHub review thread");
      seen.add(thread.id);
      threads.push(thread);
    }
    if (!connection.pageInfo.hasNextPage) return threads;
    const cursor = connection.pageInfo.endCursor;
    if (typeof cursor !== "string" || !cursor || cursor === after)
      throw Error("Invalid review-thread pagination cursor");
    after = cursor;
  }
  throw Error("Review-thread pagination limit reached without complete evidence");
}

export function requiredRunsPassed(runs, requiredNames, sha) {
  for (const name of requiredNames) {
    const latest = runs.filter(r => r.name === name && r.head_sha === sha &&
      r.event === "pull_request").sort((a, b) => b.id - a.id)[0];
    if (!latest || latest.status !== "completed" || latest.conclusion !== "success")
      return { pass: false, reason: "required_check_missing_or_not_green:" + name };
  }
  return { pass: true };
}

// GitHub computes mergeability asynchronously. Retry *only* its transient
// unknown state; conflicts, dirty state and failed gates never get retried.
export async function resolveMergeability(readPr, wait = ms => new Promise(resolve => setTimeout(resolve, ms))) {
  let result;
  for (let attempt = 0; attempt < 3; attempt++) {
    result = await readPr();
    if (result?.mergeable !== null && result?.mergeable !== undefined &&
        result?.mergeable_state !== "unknown" && result?.mergeable_state != null)
      return result;
    if (attempt < 2) await wait((attempt + 1) * 1000);
  }
  return result; // fail-closed if GitHub never resolves.
}

async function main() {
  const repo = process.env.GITHUB_REPOSITORY;
  const token = process.env.GH_TOKEN;
  const owner = process.env.GITHUB_REPOSITORY_OWNER;
  const number = Number(process.env.PR_NUMBER);
  if (!repo || !token || !owner || !Number.isSafeInteger(number) || number < 1) {
    console.log("No eligible PR selected");
    return;
  }

  async function api(path, options = {}) {
    const response = await fetch("https://api.github.com/repos/" + repo + path, {
      ...options,
      headers: {
        accept: "application/vnd.github+json", authorization: "Bearer " + token,
        "x-github-api-version": "2022-11-28", ...(options.headers || {})
      }
    });
    if (!response.ok) throw Error("GitHub API " + path + " returned HTTP " + response.status);
    return response.json();
  }

  async function graphql(query, variables) {
    const response = await fetch("https://api.github.com/graphql", {
      method: "POST",
      headers: {
        accept: "application/vnd.github+json", authorization: "Bearer " + token,
        "x-github-api-version": "2022-11-28", "content-type": "application/json"
      },
      body: JSON.stringify({ query, variables })
    });
    if (!response.ok) throw Error("GitHub GraphQL returned HTTP " + response.status);
    const result = await response.json();
    if (result.errors?.length || !result.data)
      throw Error("GitHub GraphQL review-thread query incomplete");
    return result.data;
  }

  // No success inference from a truncated first page: incomplete evidence fails closed.
  async function pages(path, field = null, maxPages = 10) {
    const all = [];
    for (let n = 1; n <= maxPages; n++) {
      const sep = path.includes("?") ? "&" : "?";
      const data = await api(path + sep + "per_page=100&page=" + n);
      const batch = field ? data?.[field] : data;
      if (!Array.isArray(batch)) throw Error("Unexpected paginated GitHub response: " + path);
      all.push(...batch);
      if (batch.length < 100) return all;
    }
    throw Error("Pagination limit reached without complete evidence: " + path);
  }

  function reject(reason) { console.log("Not eligible: " + reason); }
  const pr = await resolveMergeability(() => api("/pulls/" + number));
  if (pr.state !== "open" || pr.draft || pr.base?.ref !== "main" ||
      !pr.mergeable || pr.mergeable_state !== "clean" ||
      ![owner.toLowerCase(), CODEX_REVIEWER.toLowerCase()].includes(pr.user?.login?.toLowerCase()) ||
      pr.head?.repo?.full_name !== repo || !SHA.test(pr.head?.sha ?? "")) {
    reject("PR state, provenance or GitHub mergeability");
    return;
  }

  const sha = pr.head.sha;
  const files = await pages("/pulls/" + number + "/files");
  if (files.length !== pr.changed_files || files.some(f => !f.filename)) {
    reject("Changed-file list does not match GitHub PR metadata");
    return;
  }
  const paths = changedPaths(files);
  if (modifiesProtectedVerification(paths)) {
    reject("Protected workflow, verification policy or gate changed: manual owner integration required");
    return;
  }
  const required = applicableChecks(paths);
  const runs = await pages("/actions/runs?head_sha=" + sha + "&event=pull_request", "workflow_runs");
  const checks = requiredRunsPassed(runs, required, sha);
  if (!checks.pass) { reject(checks.reason); return; }

  const reviews = await pages("/pulls/" + number + "/reviews");
  const issueComments = await pages("/issues/" + number + "/comments");
  // Dismissed receipts and self-authored imitation text are never eligible.
  if (!codexReviewsPassed(reviews, sha)) {
    reject("Missing or contradicted trusted Codex receipt for final SHA");
    return;
  }
  if (hasUndispositionedBlockingCodexReview(reviews, issueComments, owner)) {
    reject("Undispositioned blocking Codex PR review from any commit");
    return;
  }

  const [repoOwner, repoName] = repo.split("/");
  const reviewThreadQuery = "query($owner:String!,$name:String!,$number:Int!,$after:String) {" +
    " repository(owner:$owner,name:$name) { pullRequest(number:$number) {" +
    " reviewThreads(first:100,after:$after) { pageInfo { hasNextPage endCursor }" +
    " nodes { id isResolved comments(first:100) {" +
    " pageInfo { hasNextPage } nodes { author { login } body } } } } } } }";
  const threads = await collectReviewThreads(async after => {
    const data = await graphql(reviewThreadQuery, {
      owner: repoOwner, name: repoName, number, after
    });
    return data?.repository?.pullRequest?.reviewThreads;
  });
  if (hasBlockingCodexFinding(threads)) {
    reject("Unresolved actionable Codex finding from any PR commit");
    return;
  }

  if (visualRequired(paths)) {
    const exact = "VISUAL-ACCEPTED: " + sha;
    if (!issueComments.some(c => c.user?.login?.toLowerCase() === owner.toLowerCase() &&
        c.body?.split(/\r?\n/).some(line => line.trim() === exact))) {
      reject("Final-SHA visual acceptance missing");
      return;
    }
  }

  // Exact-SHA compare-and-swap merge; never select a moving branch by ref.
  const current = await resolveMergeability(() => api("/pulls/" + number));
  if (current.head?.sha !== sha || current.state !== "open" || !current.mergeable ||
      current.mergeable_state !== "clean") {
    reject("Head or mergeability changed during verification");
    return;
  }
  const merged = await api("/pulls/" + number + "/merge", {
    method: "PUT",
    body: JSON.stringify({ sha, merge_method: "squash", commit_title: current.title })
  });
  if (!merged.merged) throw Error("GitHub rejected the merge");
  console.log("Merged PR " + number + " final HEAD " + sha + " into " + merged.sha);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch(error => { console.error("Fail-closed gate error:", error.message); process.exitCode = 1; });
}
