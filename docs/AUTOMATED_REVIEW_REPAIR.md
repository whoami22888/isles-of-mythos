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

- The supported integration is the official OpenAI Codex CLI release
  `rust-v0.163.0`, downloaded from the pinned OpenAI Codex release asset and
  verified by SHA-256. It is not a GitHub Action or a custom repair endpoint.
- Configure an environment-scoped secret named `OPENAI_API_KEY` in the
  `codex-repair` GitHub Actions environment. This is a dedicated OpenAI
  project API key consumed by `codex login --with-api-key`; do not use
  `LIM_API_KEY` or `CODEX_REPAIR_TOKEN`.
- Grant the repair environment narrowly scoped `contents: write` and
  `pull-requests: write` permissions, with protected-branch rules unchanged.
- Supply a trusted actor allowlist and an exact-SHA GitHub API reader for
  checks, reviews, mergeability, and visual acceptance artifacts.
- Prove one end-to-end run on a disposable PR before enabling repair or merge.

No workflow in this change claims that automatic repair or automatic merging
is operational. Fork heads, missing SHA evidence, duplicate concurrent events,
missing AI approval, failed/stale checks, and missing visual acceptance are
rejected. Persistent cross-run deduplication requires the approved worker's
durable event ledger; no untrusted PR cache is used.

The dispatch inputs require a same-repository PR number and exact head SHA.
Repair is manual workflow dispatch only, does not merge, and pushes only to
the validated non-`main` PR branch. Automatic repair must remain disabled until
an authenticated disposable-PR run proves diagnosis, targeted testing, push,
deduplication, fork rejection, and fail-closed behavior.
