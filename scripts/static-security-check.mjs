#!/usr/bin/env node
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const roots = ["server/src", "client/src"];
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
const workflowRoot=".github/workflows";
for(const name of readdirSync(workflowRoot).sort()){
 if(!/\.ya?ml$/i.test(name))continue;
 const file=join(workflowRoot,name),content=readFileSync(file,"utf8"),lines=content.split(/\r?\n/);
 lines.forEach((line,index)=>{
   const a=line.match(/^\s*(?:-\s*)?uses:\s*([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*)@([^\s#]+)(?:\s+#.*)?$/);
   if(a&&!/^[0-9a-f]{40}$/i.test(a[2]))add(findings.errors,"unpinned-workflow-action",file,index+1,line);
 });
 const topLevelPermissions=content.match(/^permissions:\s*\n((?:^  [A-Za-z0-9_-]+:\s*(?:read|write|none)\s*(?:#.*)?\n?)+)/m);
 if(!topLevelPermissions||!/^  contents:\s*read\s*(?:#.*)?$/m.test(topLevelPermissions[1]))add(findings.errors,"workflow-permissions-policy",file,1,"Workflow must declare top-level contents: read");
 if(content.includes(String.fromCharCode(92)+"${{"))add(findings.errors,"escaped-workflow-expression",file,1,"Workflow expressions must not be escaped with a backslash");
 if(["ci.yml","performance.yml","static-security.yml"].includes(name)){
   if(!/ref:\s*\$\{\{\s*github\.event\.pull_request\.head\.sha\s*\|\|\s*github\.sha\s*\}\}/.test(content))add(findings.errors,"workflow-exact-head-checkout",file,1,"Pull-request workflow must check out github.event.pull_request.head.sha");
   if(!/persist-credentials:\s*false/.test(content))add(findings.errors,"workflow-checkout-credentials",file,1,"Pull-request workflow checkout must disable persisted credentials");
 }
 const uncommentedWorkflow=lines.map(line=>line.replace(/^\s*#.*$/,"").replace(/\s+#.*$/,"")).join("\n");
const qualifiedPostgresRefs=[...uncommentedWorkflow.matchAll(/(?:^|[\s"'=])((?:[A-Za-z0-9.-]+\/)+postgres(?::[A-Za-z0-9._-]+|@sha256:[0-9a-f]{64})?)(?=$|[\s"'\\])/gim)];
for(const match of qualifiedPostgresRefs){
 const ref=match[1];
 if(!/@sha256:[0-9a-f]{64}$/i.test(ref)){
   const lineNumber=uncommentedWorkflow.slice(0,match.index).split("\n").length;
   add(findings.errors,"mutable-postgres-image",file,lineNumber,lines[lineNumber-1]||ref);
 }
}
}
for(const [i,rawLine] of readFileSync("docker-compose.yml","utf8").split(/\r?\n/).entries()){
 if(/^\s*#/.test(rawLine))continue;
 const line=rawLine.replace(/\s+#.*$/,"");
 const image=line.match(/^\s*image:\s*(["']?)([^"'#\s]+)\1\s*$/i);
 if(image&&/(?:^|\/)postgres(?=[:/@])/i.test(image[2])&&!/postgres-exporter/i.test(image[2])&&!/@sha256:[0-9a-f]{64}$/i.test(image[2]))add(findings.errors,"mutable-postgres-image","docker-compose.yml",i+1,rawLine);
}

 // Mandatory verification orchestration policy: cancelled or unbounded required checks
 // cannot provide trustworthy acceptance evidence.
 const requiredWorkflowControls = {
   "ci.yml": { cancel: false, timeout: 15 },
   "performance.yml": { cancel: false, timeout: 15 },
   "static-security.yml": { cancel: false, timeout: 5 },
   "codeql.yml": { timeout: 20 },
   "codacy.yml": { timeout: 15 },
 };
 for (const [workflow, policy] of Object.entries(requiredWorkflowControls)) {
   const path = join(workflowRoot, workflow);
   let content;
   try {
     content = readFileSync(path, "utf8");
   } catch {
     add(findings.errors, "required-workflow-missing", path, 1, "Required verification workflow is missing");
     continue;
   }
   if (policy.cancel === false && /^\s*cancel-in-progress:\s*true\s*$/m.test(content)) {
     add(findings.errors, "verification-cancellation-enabled", path, 1, "Mandatory verification runs must not be automatically cancelled");
   }
   if (policy.cancel === false && !/^\s*cancel-in-progress:\s*false\s*$/m.test(content)) {
     add(findings.errors, "verification-cancellation-policy-missing", path, 1, "Explicit cancel-in-progress: false is required for mandatory verification");
   }
   if (!new RegExp("^\\s*timeout-minutes:\\s*" + policy.timeout + "\\s*$", "m").test(content)) {
     add(findings.errors, "verification-timeout-policy", path, 1, "Expected job timeout-minutes: " + policy.timeout);
   }
 }


const rootPackage = JSON.parse(readFileSync("package.json", "utf8"));
if (rootPackage.scripts?.["test:orchestration"] !== "node --test scripts/orchestration-control.test.mjs") {
  add(findings.errors, "orchestration-test-script", "package.json", 1, "Root package must expose orchestration tests");
}
const ciWorkflow = readFileSync(join(workflowRoot, "ci.yml"), "utf8");
if (!ciWorkflow.includes("npm run test:orchestration")) {
  add(findings.errors, "orchestration-ci-hook", join(workflowRoot, "ci.yml"), 1, "CI must run orchestration-controller tests");
}
const performanceWorkflow = readFileSync(join(workflowRoot, "performance.yml"), "utf8");
for (const [name, content] of [["ci.yml", ciWorkflow], ["performance.yml", performanceWorkflow]]) {
  if (!/^\s*cache:\s*npm\s*$/m.test(content) || !/^\s*cache-dependency-path:\s*package-lock\.json\s*$/m.test(content)) {
    add(findings.errors, "npm-cache-policy", join(workflowRoot, name), 1, "Required build workflow must use lockfile-keyed npm cache");
  }
}
for (const [marker, description] of [
  ["EXPECTED_HEAD_SHA:", "Performance evidence must bind to exact expected HEAD"],
  ["git rev-parse HEAD", "Performance workflow must verify checked-out HEAD"],
  ["orchestration-control.mjs manifest", "Performance workflow must create a cryptographic manifest"],
  ["orchestration-control.mjs validate-manifest", "Performance workflow must validate its manifest"],
  ["acceptance-evidence-manifest.json", "Manifest must be included in uploaded artifact"],
]) {
  if (!performanceWorkflow.includes(marker)) add(findings.errors, "performance-evidence-integrity", join(workflowRoot, "performance.yml"), 1, description);
}
for (const name of Object.keys(requiredWorkflowControls)) {
  const path = join(workflowRoot, name);
  const content = readFileSync(path, "utf8");
  if (!/ref:\s*\$\{\{\s*github\.event\.pull_request\.head\.sha\s*\|\|\s*github\.sha\s*\}\}/.test(content)) {
    add(findings.errors, "workflow-exact-head-checkout", path, 1, "Required workflow must check out the exact PR/source SHA");
  }
  if (!/persist-credentials:\s*false/.test(content)) {
    add(findings.errors, "workflow-checkout-credentials", path, 1, "Required workflow checkout must disable persisted credentials");
  }
}

console.log("Static security scan: " + (findings.errors.length === 0 ? "PASS" : "FAIL"));
for (const item of findings.errors) console.log("ERROR " + item);
for (const item of findings.reviews.slice(0, 200)) console.log("REVIEW " + item);
if (findings.reviews.length > 200) console.log("REVIEW output truncated: " + (findings.reviews.length - 200) + " additional findings");
if (findings.errors.length) process.exit(1);
