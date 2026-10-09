#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const roots = ["server/src", "client/src"];
const workflowRoot = ".github/workflows";
const findings = { errors: [], reviews: [] };

function walk(root) {
  for (const name of readdirSync(root)) {
    const file = join(root, name);
    if (file.includes("/dist/") || file.includes("/node_modules/") || /\.test\.(ts|tsx|js|mjs)$/.test(file)) continue;
    if (statSync(file).isDirectory()) walk(file);
    else if (/\.(ts|tsx|js|mjs|cjs)$/.test(file)) scan(file);
  }
}

function add(list, category, file, line, text) {
  list.push(category + " " + relative(process.cwd(), file) + ":" + line + " " + text.trim().slice(0, 220));
}

function scan(file) {
  const lines = readFileSync(file, "utf8").split(/\r?\n/);
  lines.forEach((line, index) => {
    const n = index + 1;
    if (/\beval\s*\(|\bnew\s+Function\s*\(/.test(line)) add(findings.errors, "dynamic-code", file, n, line);
    if (/Number\s*\([^)]*(gold|doubloon|currency|balance)/i.test(line) || /parseFloat\s*\([^)]*(gold|doubloon|currency|balance)/i.test(line)) add(findings.errors, "economy-number-conversion", file, n, line);
    if (/-----BEGIN .*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}/.test(line)) add(findings.errors, "hard-coded-secret", file, n, line);
    if (/JWT_SECRET\s*[:=]\s*["'][^"']+["']/.test(line) && !/development-only-secret-change-me|test-only-jwt-secret-not-for-production|performance-test-secret/.test(line)) add(findings.errors, "hard-coded-jwt-secret", file, n, line);
    if (/app\.(get|post|put|patch|delete)\s*\(\s*["']\/(debug|internal|admin\/debug)/i.test(line)) add(findings.errors, "debug-endpoint", file, n, line);
    if (/(TODO|FIXME)/i.test(line) && /(security|critical|blocker|production)/i.test(line)) add(findings.errors, "production-blocker-comment", file, n, line);
    if (/\bas\s+any\b|:\s*any\b|<any>/.test(line)) add(findings.reviews, "explicit-any", file, n, line);
    if (/JSON\.parse\s*\(/.test(line)) add(findings.reviews, "json-parse-review", file, n, line);
    if (/\b(SELECT|INSERT|UPDATE|DELETE)\b/i.test(line) && /\$\{/.test(line)) add(findings.reviews, "sql-interpolation-review", file, n, line);
    if (/parseFloat\s*\(/.test(line) && /(price|amount|currency|balance|gold|doubloon)/i.test(line)) add(findings.reviews, "floating-economy-review", file, n, line);
  });
}

for (const root of roots) walk(root);

// Keep workflow security policy inside the required static-security gate.
if (!existsSync(workflowRoot)) {
  findings.errors.push("workflow-policy missing .github/workflows directory");
} else {
  for (const name of readdirSync(workflowRoot).sort()) {
    if (!/\.ya?ml$/i.test(name)) continue;
    const file = join(workflowRoot, name);
    const content = readFileSync(file, "utf8");
    const lines = content.split(/\r?\n/);
    lines.forEach((line, index) => {
      const n = index + 1;
      if (line.includes("\\${{")) add(findings.errors, "escaped-workflow-expression", file, n, line);
      const action = line.match(/^\s*uses:\s*([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)@([^\s#]+)(?:\s+#.*)?$/);
      if (action && !/^[0-9a-f]{40}$/i.test(action[2])) {
        add(findings.errors, "unpinned-workflow-action", file, n, line);
      }
    });
    if (!/^permissions:\s*$/m.test(content) || !/^  contents:\s*read\s*$/m.test(content)) {
      add(findings.errors, "workflow-permissions-policy", file, 1, "Workflow must explicitly grant contents: read at top-level permissions");
    }
  }
}

console.log("Static security scan: " + (findings.errors.length === 0 ? "PASS" : "FAIL"));
for (const item of findings.errors) console.log("ERROR " + item);
for (const item of findings.reviews.slice(0, 200)) console.log("REVIEW " + item);
if (findings.reviews.length > 200) console.log("REVIEW output truncated: " + (findings.reviews.length - 200) + " additional findings");
if (findings.errors.length) process.exit(1);
