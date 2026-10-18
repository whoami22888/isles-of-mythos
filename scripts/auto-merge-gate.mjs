#!/usr/bin/env node
// Trusted-code-only, fail-closed PR integration gate.
const required = ["CI","Codacy Security Scan","CodeQL Advanced","Static Security Quality","Performance Acceptance"];
const shaPattern = /^[a-f0-9]{40}$/i;
const repo = process.env.GITHUB_REPOSITORY;
const token = process.env.GH_TOKEN;
const number = Number(process.env.PR_NUMBER);
const owner = process.env.GITHUB_REPOSITORY_OWNER;
if (!repo || !token || !owner || !Number.isSafeInteger(number) || number < 1) {
  console.log("No eligible PR selected"); process.exit(0);
}
async function api(path, options={}) {
  const response = await fetch("https://api.github.com/repos/" + repo + path, {
    ...options, headers: { accept:"application/vnd.github+json",authorization:"Bearer "+token,
      "x-github-api-version":"2022-11-28",...(options.headers||{}) }
  });
  if (!response.ok) throw Error("GitHub API "+path+" returned "+response.status);
  return response.json();
}
function reject(reason) { console.log("Not eligible: "+reason); process.exit(0); }
const pr = await api("/pulls/"+number);
if (pr.state!=="open" || pr.draft || pr.base?.ref!=="main" || !pr.mergeable ||
    pr.mergeable_state!=="clean" || pr.user?.login?.toLowerCase()!==owner.toLowerCase() ||
    pr.head?.repo?.full_name!==repo || !shaPattern.test(pr.head?.sha??"")) reject("PR state, author, repository, or mergeability");
const sha = pr.head.sha;
const runs = await api("/actions/runs?head_sha="+sha+"&per_page=100&event=pull_request");
for(const name of required) {
  const matching = runs.workflow_runs.filter(r=>r.name===name && r.head_sha===sha && r.event==="pull_request");
  if(!matching.length || matching.some(r=>r.status!=="completed" || r.conclusion!=="success"))
    reject("Required check is absent or not green: "+name);
}
const reviews = await api("/pulls/"+number+"/reviews?per_page=100");
const codex = reviews.find(r=>r.commit_id===sha && /codex-review-receipt:v1/.test(r.body||"") && /codex/i.test(r.user?.login||""));
if(!codex) reject("No Codex review receipt for final SHA");
const comments = await api("/pulls/"+number+"/comments?per_page=100");
if(comments.some(c=>c.commit_id===sha && /codex-code-review-finding:v1|\[P[012]\]/i.test(c.body||"")))
  reject("Open Codex review findings on final SHA");
const files = await api("/pulls/"+number+"/files?per_page=100");
if(files.length===100 || pr.changed_files>100) reject("PR too large to verify visual/file gates");
const visual = files.some(f=>/(^|\/)(godot|graphics|art|assets|renders|cinematics)(\/|$)|\.(tscn|tres|gd|png|jpg|jpeg|webp|mp4|glb|gltf)$/i.test(f.filename));
if(visual) {
  const comments2=await api("/issues/"+number+"/comments?per_page=100");
  if(!comments2.some(c=>c.user?.login?.toLowerCase()===owner.toLowerCase() && c.body?.includes("VISUAL-ACCEPTED: "+sha)))
    reject("Final-SHA visual acceptance missing");
}
const last=await api("/pulls/"+number);
if(last.head?.sha!==sha || !last.mergeable || last.mergeable_state!=="clean") reject("Changed head or merge state");
const result=await api("/pulls/"+number+"/merge",{
  method:"PUT",body:JSON.stringify({sha,merge_method:"squash",commit_title:last.title})
});
if(!result.merged) throw Error("Merge rejected without a successful result");
console.log("Merged PR "+number+" exact head "+sha+" -> "+result.sha);
