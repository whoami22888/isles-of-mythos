# PR #248 repair evidence

- Date: 2026-11-01 UTC; implementation owner: Codex, single writer.
- Branch: `codex/github-mention-controller-task-complete-#235-under-protect`.
- Original PR HEAD: `609fbdede13d5ecde83307f4b0465a523145cf15`.
- Integrated main: `818a491d233179276874c0c4cf182863e8f82e26`.
- Purpose/root cause: replace repository-wide ignored-file deletion and caller-relative execution; guard the required engine version; reconcile newer workflows with missing branch test files.
- Fix: apply the owner-supplied local validator; merge main, restoring vendor guard and vertical-slice tests without replacing or weakening test gates.

## Build & Integrity

- PASS: `bash -n scripts/local-validate.sh`, `git diff --check`, vendor-lock test and validator, 12 workflow-matrix tests and workflow-matrix validator.
- PASS: all 10 `res://tests/*.gd` references in the Godot client workflow resolve to existing files.
- Lint/typecheck: FAIL in this local dependency installation; `ioredis` is absent and associated TypeScript resolution errors follow. No dependency declarations changed.
- Engine execution: BLOCKED. Installed Godot is 4.6.3; the supplied guard rejects it before cleanup. Godot 4.7.2 import/export is NOT VERIFIED locally.

## Functionality & Integration

- PASS: temporary shell fixture invoked from `/tmp`, with stubbed Godot/Python commands, confirms repository anchoring and removal of only `.godot`/`.import` caches. This is shell behavior evidence, not real engine execution.
- PASS: `GODOT_BIN=/usr/bin/false` invocation from `/tmp` rejects incompatible version.
- PASS: provenance validator reports 106 registered asset files.
- `npm test`: FAIL overall; client 9 files/69 tests pass; server 42 files fail and 40 pass, with 9 failed/326 passed/7 skipped tests. Missing `ioredis` and denied PostgreSQL connections are observed local blockers.

## Data & Transaction Safety

- PASS: shell fixture preserves `.env`, dependency sentinel, external asset bytes and asset manifest.
- Database transactional/runtime validation: NOT VERIFIED; PostgreSQL connections denied in local sandbox. No migrations, database configuration, credentials or gameplay code changed by this repair.

## Review and follow-up

- Prior failing exact-original-head workflow runs: CI `41272893986` (missing vendor test); Godot `41272893961` (missing vertical-slice smoke test).
- Final SHA and fresh check IDs must be read from GitHub after the repair push; old results do not verify the repair.
- Independent final-SHA review, mandatory CI/security/performance and Godot 4.7.2 checks remain required before merge. No merge or deployment authorized by this record.
- The owner-supplied substring engine check is retained verbatim; it is not a strict parser of official version strings.
- Notion checkpoint pending: no Notion tool is available in this session.
