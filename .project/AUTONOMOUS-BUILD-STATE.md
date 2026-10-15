# Autonomous build state — 2026-10-16

> Reconcile live state on each session. This snapshot is not a substitute for GitHub's current SHA or Notion evidence.

## Authority and controller
- One GPT + Codex non-production controller; one existing Codex Lead task: `01a13b62-4eb5-7138-bc70-aea4d2ccc08e`.
- Latest Codex turn failed with a usage-limit error; do not create duplicate Codex tasks or assume capacity is available.
- Active hourly Isles Autonomous Build Controller remains the single scheduled continuation.
- User-authorised routine branch, source, CI, test, review and verified PR merge operations, limited by connected tool scopes; no production deployment, paid environments, protected migrations 029/036, or frozen-gate changes.

## Reconciled repository
- Baseline main: `d341b14f31782c2b3da9bcbf90c560e97f4455bb` (read at checkpoint creation).
- PR #137 `fix/audit-rollback-error-preservation-20261015`, HEAD `00a68cd8c5586659a53e6de2f6ff0173a424dbc2`, draft. Five CI/security/performance workflows green at this HEAD; AI review and gathering rollback regression remain unresolved. GPT owns fixes.
- PR #136 `fix/attack-replay-evidence`, HEAD `d7b990e70066c371579922cc6f37dced47d5a615`. Reconfirm mergeability, exact-SHA checks and review immediately before any merge.
- PR #125 bounded verification orchestration; PR #121 P0 movement speedhack regressions; PR #119 performance tracing. No blind merge.
- Codex owns ongoing 250-player latency correction; main has since passed performance acceptance, but root-cause disposition must be reconciled with Codex evidence.
- Existing workflows: `.github/workflows/ci.yml`, `performance.yml`, `static-security.yml`, `codeql.yml`, `codacy.yml`, `godot-iom-00.yml`, `summary.yml`. Inspect before refactoring; do not duplicate suites.

## Dependency-aware execution queue
1. GPT — PR #137: add resource-gathering rollback failure regression; perform distinct AI review, check exact final SHA, merge only when green, verify resulting main.
2. GPT — reconcile PR #136 review/mergeability and exact-SHA evidence; merge only if all requirements pass and verify main.
3. Codex — continue its owned performance correction when quota available; do not concurrently edit Codex-owned files.
4. Controller/CI — inventory existing workflows, quantify redundant checks and split reusable workflow_call only when it demonstrably reduces duplication without weakening security.
5. Client/QA — Godot 4.7.2 Android ARM64 device build and actual phone smoke testing; do not claim physical-device validation without evidence.
6. Harvest/World — pinned source licence and asset provenance review; block unauthorized third-party asset import.
7. Controller — advance dependency-ready IOM gates with explicit owner, branch, tests, artifacts and updated Notion record.

## Verification rules
- Build & Integrity: lint, typecheck, compilation, dependencies, workflow integrity, security scanning.
- Functionality & Integration: client/server protocol, gameplay, reconnect, UX, smoke, replay and load behavior.
- Data & Transaction Safety: authoritative mutations, rollback, concurrency, persistence, idempotency, backup/restore.
- Performance matrices: 1/50/250/1000 and 10/50/100/500/1000 players. Scenarios: 500 guild-battle, 250 naval, 250 world-boss, 5000 persisted player bases. Require durable evidence, server tick p50/p95/p99 and 20 Hz cadence.

## Notion checkpoints
- Build Instructions: https://app.notion.com/p/3fa3fab3c26681d5a87fe776982e9895
- Harvest Parts: https://app.notion.com/p/3fa3fab3c266811dbd7bd1d7b636723f
- Progress & Revision Notes: https://app.notion.com/p/3fa3fab3c2668153b493e21f913ecfdf
- Audit: https://app.notion.com/p/3fa3fab3c26681f88f13f27db2ade308

Update this snapshot only from fresh evidence and preserve historical decisions in Git history and Notion.
