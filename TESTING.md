# Testing

## Required verification chain
A phase is not verified until migrations, lint, typecheck, tests, production build and cleanup pass, with security/performance evidence where required.

## Debugging procedure
Use BUILD -> TEST -> INSPECT -> FIX -> RETEST -> VERIFY -> DOCUMENT -> CONTINUE. For every failure record exact failure, location, root cause, contributing factor, fix, regression risk and evidence.

## Anti-loop rule
Do not repeatedly rerun the same failure. Every retry requires new evidence or a targeted correction. Never increase a timeout merely to hide an unresolved synchronization or logic defect.

## Historical acceptance (not current)
Verified on 2026-10-10 at main SHA `30eef8b10d80363dc15b4256362d45b6b669019a`:
- CI #1128 / run [38055682984](https://github.com/whoami22888/isles-of-mythos/actions/runs/38055682984) — PASS.
- Performance Acceptance #345 / run [38055682961](https://github.com/whoami22888/isles-of-mythos/actions/runs/38055682961) — PASS.
- Static Security Quality #317 / run [38055682968](https://github.com/whoami22888/isles-of-mythos/actions/runs/38055682968) — PASS.
## Evidence rule
Passing tests prove only the behaviours they exercise. PDF post-Phase-16 architecture, scaling, mobile/GPU and production requirements remain separately classified until direct evidence exists.

## Controller acceptance requirements — 2026-10-12

Operational PostgreSQL candidate: \`cgr.dev/chainguard/postgres@sha256:1a417cf464d938b1b1182411416401215af7fbc88395d9b90f7c805e96d639a7\` (PostgreSQL 18.6, a major-version upgrade from 17). Acceptance must record both \`SHOW server_version\` and \`SHOW server_version_num\`, fail unless the numeric value is in \`[180000, 190000)\`, and retain \`postgres-server-version.txt\` in the report/artifacts. This does not waive migration, integration, regression, backup/restore or supply-chain checks.

For pull-request events, required workflows must explicitly check out \`github.event.pull_request.head.sha\` (falling back to \`github.sha\` for non-PR events), so the tested source matches the reported PR HEAD. The workflow changes implementing this policy still require fresh exact-head verification.

Pre-change main baseline: `c500cf7b6cbb967fd92d99bdc33b02536a5d0097`. Runs below are historical and do not verify a later PR head or merge:
- CI #1136 / [38116415103](https://github.com/whoami22888/isles-of-mythos/actions/runs/38116415103) — PASS.
- Performance Acceptance #353 / [38116415094](https://github.com/whoami22888/isles-of-mythos/actions/runs/38116415094) — PASS.
- Static Security Quality #325 / [38116415105](https://github.com/whoami22888/isles-of-mythos/actions/runs/38116415105) — PASS.
- CodeQL Advanced #4 / [38116415101](https://github.com/whoami22888/isles-of-mythos/actions/runs/38116415101) — PASS.
- Codacy Security Scan #2 / [38116415058](https://github.com/whoami22888/isles-of-mythos/actions/runs/38116415058) — PASS.

Preserve section 93's 1/50/250/1,000-player matrix and add 500-player guild battle, 250-action naval battle, 250-contributor world boss, and 5,000 persisted player bases. Every baseline scenario must prove durable `gameplayCraft` and `gameplayMutation`; missing evidence fails validation. Record HTTP/WebSocket latency, WebSocket bytes, server tick, CPU and memory. Physical-device FPS/frame-time/GPU metrics remain unverified until section 94's Android/iOS device matrix runs.

PostgreSQL acceptance requires an immutable exact-registry digest, verified signed SLSA provenance and SPDX SBOM attestation plus a locally generated CycloneDX SBOM, vulnerability scan evidence, artifact retention, monthly review and expedited reviewed security updates. Historical passing results do not satisfy these new checks.


**Compatibility warning:** this pin selects PostgreSQL 18.6, a major-version change from PostgreSQL 17. Do not accept it unless the exact-image migration, integration, regression and full CI chain passes.

## Anti-cheat shared-state tests (Redis + PostgreSQL)

`server/src/anti-cheat-shared-state.integration.test.ts` exercises the real Redis-backed detection store and the PostgreSQL evidence table (cross-instance aggregation, concurrency, restart persistence, Redis failure degradation, append-only/retention rules and bounded storage). It requires:

- PostgreSQL with all migrations applied (including `039_anti_cheat_evidence`), via `DATABASE_URL`.
- A reachable Redis at `REDIS_URL` (default `redis://127.0.0.1:6379`). The suite **fails** rather than skips when Redis is unreachable, so a missing service can never read as a pass. CI starts a digest-pinned Redis container for this purpose.

Detection state is diagnostic only. Hard gameplay validity checks run in the authoritative handlers and database transactions and must not depend on this store; Redis failure degrades detection to per-instance memory and never changes a mutation outcome.

Known test-hygiene limitation (pre-existing, reproduced on `46296ef`): several integration suites (guild, realm, invasion, request-ID) fail when the whole suite is run a second time against the *same* database because fixtures leak rows between runs. CI is unaffected (it starts from a fresh PostgreSQL service); locally, recreate the test database before each full run.
