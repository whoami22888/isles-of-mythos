# Automated review and repair controller

The `Automated review and repair controller` workflow classifies pull-request
reviews, review comments, and failed pull-request checks against the exact
head SHA. It uses event-specific concurrency groups and deterministic event
keys so duplicate deliveries cannot run concurrently or be confused with a
different review, comment, workflow run, or head SHA.

The classifier is intentionally read-only. The separate dispatch workflow has
no untrusted checkout and is only a guarded activation placeholder. Existing CI, CodeQL, Codacy,
security, performance, Godot export, and visual-evidence workflows remain the
authoritative checks. Automatic repair and merging are fail-closed until an
approved Codex worker integration is installed and exercised end to end.

Activation requirements:

- Configure a repository or environment secret named `CODEX_REPAIR_TOKEN`.
- Replace the guarded dispatch step with the approved, pinned Codex action or
  worker integration after security review; no arbitrary repository variable
  is executed as a shell command.
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
