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

// Exact path filters of .github/workflows/iom-world-content.yml and iom-coastal-ship-fx.yml. The gate must require
// a workflow whenever GitHub would have triggered it; tests assert this inventory against the workflow files.
export const WORLD_CONTENT_PATHS = Object.freeze(new Set([
  "client-godot/content/world_population.json",
  "client-godot/scripts/world_content_director.gd",
  "client-godot/tests/world_content_director_test.gd",
  "scripts/world_content.py",
  "scripts/harvest_world_lighting.py",
  "scripts/test_world_content.py",
  "scripts/test_harvest_world_lighting.py",
  ".github/workflows/iom-world-content.yml"
]));
export const COASTAL_FX_PATHS = Object.freeze(new Set([
  "client-godot/scenes/realistic_coastal_fx_slice.tscn",
  "client-godot/scenes/realistic_coastal_slice.tscn",
  "client-godot/scripts/coastal_ship_fx_controller.gd",
  "client-godot/scripts/ship_wake_effect.gd",
  "client-godot/shaders/ship_wake_foam.gdshader",
  "client-godot/scripts/ship_bow_spray_effect.gd",
  "client-godot/shaders/ship_bow_spray.gdshader",
  "client-godot/scripts/realistic_coastal_slice.gd",
  "client-godot/tests/coastal_cinematic_path_test.gd",
  "client-godot/tests/coastal_shader_compile_test.gd",
  "client-godot/tests/coastal_ship_controls_test.gd",
  "client-godot/tests/realistic_coastal_slice_test.gd",
  "client-godot/tests/coastal_ship_fx_integration_test.gd",
  "client-godot/tests/render_coastal_fx_sequence.gd",
  "client-godot/tests/coastal_ocean_integration_test.gd",
  "client-godot/tests/coastal_shore_heightfield_test.gd",
  "client-godot/scripts/coastal_shore_heightfield.gd",
  "client-godot/shaders/coastal_shore_sampler.gdshaderinc",
  "client-godot/shaders/ocean_surface.gdshader",
  "scripts/auto-merge-gate.mjs",
  ".github/workflows/iom-coastal-ship-fx.yml"
]));
const COASTAL_FX_PREFIX = "client-godot/assets/external/";

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
    "package.json", "package-lock.json",
    "scripts/static-security-check.mjs", "scripts/orchestration-control.mjs",
    "scripts/auto-merge-gate.mjs", "scripts/auto-merge-gate.test.mjs",
    "scripts/review-controller.mjs", "scripts/review-controller.test.mjs"
  ]);
  return paths.some(p => guarded.has(p) ||
    p.startsWith(".github/workflows/") ||
    p.startsWith(".github/actions/"));
}

export function applicableChecks(paths) {
  if (!Array.isArray(paths) || paths.some(p => typeof p !== "string")) throw Error("Invalid changed paths");
  const required = new Set(BASE_CHECKS);
  if (paths.some(p => p.startsWith("client-godot/") || p === ".github/workflows/godot-iom-00.yml"))
    required.add("IOM-00 Godot client");
  if (paths.some(p => p.startsWith("client-godot/") || p === ".github/workflows/godot-visual-evidence.yml"))
    required.add("Godot visual evidence");
  if (paths.some(p => p.startsWith("client-godot/assets/") ||
       ART_PROVENANCE_SCRIPTS.has(p) || p === ".github/workflows/godot-art-provenance.yml"))
    required.add("Godot external art provenance");
  if (paths.some(p => STAGE_SCRIPTS.has(p) || p === ".github/workflows/godot-stage-coast.yml"))
    required.add("Stage Poly Haven coastal PBR candidate");
  if (paths.some(p => WORLD_CONTENT_PATHS.has(p)))
    required.add("Isles world content and source harvest");
  if (paths.some(p => COASTAL_FX_PATHS.has(p) || p.startsWith(COASTAL_FX_PREFIX)))
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
  return SHA.test(sha) &&
    review?.commit_id === sha &&
    review?.user?.login === CODEX_REVIEWER &&
    (review?.state === "COMMENTED" || review?.state === "APPROVED") &&
    /<!--\s*codex-review-receipt:v1\s*-->/.test(review?.body ?? "");
}

// A Codex review with no findings is published as bot-authored *issue comments* (a summary that is edited in
// place, plus a receipt), not as a formal PR review object. Both must be exact-SHA and bot-authored.
// The "[bot]" login suffix is reserved for GitHub Apps; no ordinary account can hold this exact login.
const isCodexBotComment = c => c?.user?.login === CODEX_REVIEWER;
const SUMMARY_MARKER = /<!--\s*codex-review-state:v1\s*([\s\S]*?)\s*-->/;
const RECEIPT_COMMIT = /\*{0,2}Reviewed commit:\*{0,2}\s*`([0-9a-f]{10,40})`/i;

export function codexSummaryState(body) {
  const match = SUMMARY_MARKER.exec(body ?? "");
  if (!match) return null;
  try {
    // GitHub stores the braces as numeric character references inside the HTML comment.
    return JSON.parse(match[1].replaceAll("&#123;", "{").replaceAll("&#125;", "}"));
  } catch {
    return null;
  }
}

export function trustedCodexNoFindingsComments(comments, sha) {
  if (!SHA.test(sha) || !Array.isArray(comments)) return false;
  const lower = sha.toLowerCase();
  // Only the latest bot summary counts (it is edited in place per review); an earlier PASS must not be reused.
  // Select by marker first, then parse: a newer malformed summary must reject, never fall back to older evidence.
  const latest = comments.filter(c => isCodexBotComment(c) && SUMMARY_MARKER.test(c.body ?? ""))
    .sort((a, b) => (Date.parse(b.updated_at ?? b.created_at ?? "") || 0) -
      (Date.parse(a.updated_at ?? a.created_at ?? "") || 0))[0];
  const review = latest ? codexSummaryState(latest.body)?.code_review : undefined;
  const summary = review?.commit_sha?.toLowerCase() === lower && review.status === "completed" &&
    review.has_any_findings === false && review.has_unresolved_findings === false;
  const receipt = comments.some(c => {
    if (!isCodexBotComment(c) || !/<!--\s*codex-review-receipt:v1\s*-->/.test(c.body ?? "")) return false;
    const reviewed = RECEIPT_COMMIT.exec(c.body)?.[1]?.toLowerCase();
    return !!reviewed && lower.startsWith(reviewed);
  });
  return summary && receipt;
}

// Singular alias used by the owner-authored receipt tests.
export const trustedCodexNoFindingsComment = trustedCodexNoFindingsComments;

export function hasBlockingCodexFinding(comments, sha) {
  return comments.some(c => (c?.original_commit_id ?? c?.commit_id) === sha &&
    c.user?.login === CODEX_REVIEWER &&
    (/codex-code-review-finding:v1/.test(c.body ?? "") ||
     /\bP[012]\b/i.test(c.body ?? "")));
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
  // Dismissed receipts and self-authored imitation text are never eligible. Either a formal bot review receipt
  // or the bot's exact-SHA no-findings summary plus receipt comments must exist for the final SHA.
  if (!reviews.some(review => trustedCodexReceipt(review, sha)) &&
      !trustedCodexNoFindingsComments(issueComments, sha)) {
    reject("No active trusted Codex receipt for final SHA");
    return;
  }

  const comments = await pages("/pulls/" + number + "/comments");
  if (hasBlockingCodexFinding(comments, sha)) {
    reject("Unresolved final-SHA Codex finding: update code and re-review");
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
