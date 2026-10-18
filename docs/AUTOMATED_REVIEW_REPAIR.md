# Automated review and repair controller

The `Automated review and repair controller` workflow classifies pull-request
reviews, review comments, and failed pull-request checks against the exact
head SHA. It uses event-specific concurrency groups and deterministic event
keys so duplicate deliveries cannot run concurrently or be confused with a
different review, comment, workflow run, or head SHA.

The classifier is intentionally read-only. The separate dispatch workflow uses
the official pinned Codex CLI, validates a same-repository exact head, and is
manual-only. Existing CI, CodeQL, Codacy,
security, performance, Godot export, and visual-evidence workflows remain the
authoritative checks. Automatic repair and merging are fail-closed until an
approved Codex worker integration is installed and exercised end to end.

Activation requirements:

- Credentialed repair is disabled. Do not configure or expose an API key until
  a separately credentialed host broker and unprivileged container boundary
  are installed and adversarially tested.
- Supply a trusted actor allowlist and an exact-SHA GitHub API reader for
  checks, reviews, mergeability, and visual acceptance artifacts.
- A future broker must lock the OpenAI destination, revalidate the exact SHA,
  enforce a one-commit budget, validate a path allowlist, and push only from
  the trusted host after the container exits. The current workflow refuses
  before checkout, authentication, agent execution, or push.
- Prove one end-to-end run on a disposable PR before enabling repair or merge.

No workflow claims that automatic repair or automatic merging is operational.
Fork heads, missing SHA evidence, duplicate concurrent events, missing AI
approval, failed/stale checks, and missing visual acceptance are rejected.

The dispatch inputs require a same-repository PR number and exact head SHA.
Repair is manual workflow dispatch only, does not merge, and pushes only to
the validated non-`main` PR branch. Automatic repair must remain disabled until
an authenticated disposable-PR run proves diagnosis, targeted testing, push,
deduplication, fork rejection, and fail-closed behavior.
