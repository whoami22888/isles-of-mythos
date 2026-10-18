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

export function hasBlockingCodexFinding(comments, sha) {
  return comments.some(c => c?.commit_id === sha &&
    (/codex-code-review-finding:v1/.test(c.body ?? "") ||
     (c.user?.login === CODEX_REVIEWER && /\bP[012]\b/i.test(c.body ?? ""))));
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
  const pr = await api("/pulls/" + number);
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
  const paths = files.map(f => f.filename);
  const required = applicableChecks(paths);
  const runs = await pages("/actions/runs?head_sha=" + sha + "&event=pull_request", "workflow_runs");
  const checks = requiredRunsPassed(runs, required, sha);
  if (!checks.pass) { reject(checks.reason); return; }

  const reviews = await pages("/pulls/" + number + "/reviews");
  // Dismissed receipts and self-authored imitation text are never eligible.
  if (!reviews.some(review => trustedCodexReceipt(review, sha))) {
    reject("No active trusted Codex receipt for final SHA");
    return;
  }

  const comments = await pages("/pulls/" + number + "/comments");
  if (hasBlockingCodexFinding(comments, sha)) {
    reject("Unresolved final-SHA Codex finding: update code and re-review");
    return;
  }

  if (visualRequired(paths)) {
    const issueComments = await pages("/issues/" + number + "/comments");
    const exact = "VISUAL-ACCEPTED: " + sha;
    if (!issueComments.some(c => c.user?.login?.toLowerCase() === owner.toLowerCase() &&
        c.body?.split(/\r?\n/).some(line => line.trim() === exact))) {
      reject("Final-SHA visual acceptance missing");
      return;
    }
  }

  // Exact-SHA compare-and-swap merge; never select a moving branch by ref.
  const current = await api("/pulls/" + number);
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
