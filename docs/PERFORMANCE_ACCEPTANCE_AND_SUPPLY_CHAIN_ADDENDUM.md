# Performance Acceptance and Container Supply-Chain Addendum
Revision: 2026-10-12. Applies to Master Build Prompt sections 93–94 and PR #99.

## Preserve the load matrix
Retain the existing player matrix: 1, 50, 250 and 1,000 concurrent players. Add, do not substitute:
- Large guild battle: at least 500 player identities and 500 persisted actions.
- Large naval battle: at least 250 successful ship-to-ship actions and persisted combat events. Seed authoritative cannonball inventory for each attacker; require successful ammunition consumption and persisted combat events for all 250 actions.
- World boss: at least 250 distinct contributors and persisted contributions.
- Thousands of player bases: at least 5,000 persisted bases and indexed owner lookups with p50/p95/p99 latency.

## Persisted gameplay evidence
Every baseline scenario must record HTTP counts/errors/latencies, WebSocket connected/authenticated counts, ping/pong results, latency percentiles and bytes sent/received. It must also prove durable `gameplayCraft` (action, recipe, transaction ID, persisted inventory/transaction) and `gameplayMutation` (action, resource/node/item/quantity, persisted inventory and resource depletion). Missing, malformed or false evidence is a hard failure. Domain scenarios must validate persisted counts, not merely list endpoints or synthetic labels.

Record server tick, CPU, memory and network evidence. Enforce the owner-approved latency SLOs: HTTP and WebSocket gameplay p95 ≤150 ms and p99 ≤300 ms; server tick p95 ≤40 ms and p99 ≤50 ms. HTTP latency samples must hit `/world/chunks`, not `/health`. WebSocket gameplay p95/p99 must use actual craft and gather-resource request/response times; authentication and ping/pong RTT are separate diagnostic metrics and are not substitutes for gameplay latency. Each cohort records `min(players, 100) × 2` gameplay action samples. Tick p95/p99 must be calculated from instrumented Prometheus histogram buckets and required by the report validator. No numeric throughput threshold is approved. Headless CI does not establish physical-device FPS, frame time or GPU timing; those remain open until the section 94 Android/iOS device matrix runs.

## Workflow security
Pin every remote GitHub Action to a verified 40-character commit SHA. Each workflow must declare explicit top-level least-privilege permissions. Sanitize untrusted issue text and pass it as quoted data; do not treat it as AI instructions or executable shell. Missing report artifacts are a hard failure. Static checks must distinguish the PostgreSQL database image from unrelated images such as postgres-exporter.

## PostgreSQL supply chain
The previously recorded Docker Official Image digest `sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24` is immutable but not security-cleared by that fact alone; the prior Docker Hub metadata review reported 104 vulnerabilities. Candidate replacement:

`cgr.dev/chainguard/postgres@sha256:1a417cf464d938b1b1182411416401215af7fbc88395d9b90f7c805e96d639a7`

This is PostgreSQL 18.6, a major-version change from PostgreSQL 17. The current image metadata review reports one medium-severity CVE; the exact-digest automated scan remains authoritative. Do not accept the major-version change unless migrations, integration tests, regression tests, backup/restore and all required CI checks pass against this exact image. At runtime, record both `SHOW server_version` and `SHOW server_version_num`; fail unless the numeric version is in `[180000, 190000)`, and retain the version file as a workflow artifact and in the performance report.

Before acceptance, CI must verify the exact registry/index digest and assert via the raw OCI index that the expected linux/amd64 and linux/arm64 manifest digests are children of that exact index. For EACH child platform digest, verify the image signature, SLSA provenance and signed SPDX SBOM attestation using identity `https://github.com/chainguard-images/images/.github/workflows/release.yaml@refs/heads/main` and issuer `https://token.actions.githubusercontent.com`; verification of the index or one platform alone is insufficient. Run a vulnerability scan that fails on HIGH/CRITICAL findings (unfixed issues excluded). Retain inspection, signature, provenance, SPDX SBOM and generated CycloneDX SBOM/vulnerability artifacts. Review monthly and expedite security updates through a reviewed PR; resolve the new digest and rerun all evidence gates. Never silently move a digest or substitute a tag.

## Merge and recordkeeping
Reconcile PRs to current main; run CI, Performance Acceptance and Static Security Quality on the exact resulting PR HEAD; obtain independent review and required approval; merge only when repository rules allow; then verify checks on the exact merge commit. Record SHA, run IDs, artifact links, review decision and merge/post-merge SHAs in the Master Project Index. Gates 1–16 remain frozen.
