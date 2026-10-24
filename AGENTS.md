# Isles of Mythos agent guide

This file is a navigation layer. The linked project documents remain authoritative; do not copy their historical verification records into new claims.

## Read before editing

1. `full-game-prompt.PDF` (requirements source when available in the task context).
2. `.project/VERIFICATION-STANDARD.md` (exact-SHA evidence and change-record rules).
3. `CONTRIBUTING.md` and `TESTING.md` (scope, test order, and anti-loop rules).
4. `.project/AUTONOMOUS-BUILD-STATE.md`, the separate Notion Commercial Production Control Centre (Build Instructions, Harvest Parts, Progress and Audit), the legacy Master Project Index for its frozen decisions, and live GitHub state. Follow the commercial Godot architecture; do not substitute historical engine plans.

The canonical evidence-backed repair protocol is maintained in
`.project/AUTONOMOUS-BUILD-STATE.md`. Read and apply that section for every
authorised repair; this navigation file does not mechanically enforce it.

Gates 1–16 remain frozen. Step 5 remains blocked until the current independent Step 2 audit, migration deployment-history evidence for migrations 029 and 036, capture-probability/local-save reconciliation, and required owner authorization are all recorded; no generic or historical review substitutes for these prerequisites.

## Before a change

- Query live `main`, relevant PR HEADs, checks, reviews, and mergeability. Do not infer current state from README or Notion history.
- Inspect `git status` and keep imported or user-dirty checkouts untouched; use an isolated worktree for implementation.
- The Build Controller coordinates one GPT/Codex engineering team. Assign each task exactly one implementation owner and isolated write surfaces. The Integration/Auto-Fix Reviewer owns correction of findings or explicitly assigns a specialist; a distinct agent reviews the corrected final SHA. Roles do not create competing ownership or duplicate approval gates.
- Routine technical review uses an AI/GPT code review of the final exact SHA; a separate independent reviewer is not required by the owner. AI review must document actionable findings and their dispositions, and cannot substitute for mandated legal, security, owner, visual-quality, or repository controls.
- The owner authorises routine non-production development, PRs, and exact-SHA verified merges without repeated human approvals, subject to repository controls. Production releases/deployments, destructive or protected migrations (including 029/036), frozen-gate changes, paid environments, branch-protection/security weakening, and operations beyond available tool permissions remain protected and require separate authorization.
- Reuse test evidence only when the exact commit SHA is unchanged. Any new commit requires fresh exact-SHA evidence.

## Verification

Use the smallest useful loop: targeted tests → affected server/client tests → typecheck → lint → build. For a final PR HEAD, require the configured exact-SHA CI, security, performance, and AI-review gates. Record failures as evidence with root cause, bounded correction, and prevention lesson; do not weaken thresholds, tests, timeouts, or acceptance criteria.

Keep gameplay authority, transaction/idempotency guarantees, replay protections, and privacy boundaries intact. Diagnostic logs must not contain player, request, inventory, credential, or other sensitive identifiers.

## Reporting

Every material change record includes DATE/TIME, implementation owner, exact SHA, branch, files, purpose, root cause, fix, tests, exact workflow IDs/statuses, review status, risks, blockers, and next action. Update and read back the Notion checkpoint at milestones. If Notion is unavailable, record the pending update locally and continue independent authorized work.

## Lightweight model and task routing

- Routine bounded work (read-only inspection, documentation, focused tests, and simple verification) may use the lowest-cost model option explicitly exposed by the current Codex environment.
- Concurrency, security, data-integrity, and architecture work should use a stronger exposed model when available.
- After a failed diagnosis, escalate reasoning/model strength only when new evidence shows the problem is more complex; otherwise make one bounded correction and rerun the smallest affected check.
- Never assume model aliases, pricing, quotas, or `/model` commands. Never override the model of a task that is already running. Keep handoffs concise and do not duplicate active work.

## Autonomous build controller (owner-authorised, 2026-10-16)

- At session start reconcile live main SHA, open PRs, checks, artifacts, Codex task, Notion gate records, and this file; persist the resulting queue in `.project/AUTONOMOUS-BUILD-STATE.md`.
- Execute dependency-ready IOM-00 through IOM-07 work continuously within available sessions. Reuse a scheduled controller only after verifying it exists; do not invent scheduling, create duplicate controllers, or assume capacity beyond actual limits.
- Logical owners: Controller, Client, Gameplay, Multiplayer, World/Content, Database, QA, Performance, Security, CI/CD, and Integration/Auto-Fix. Instantiate parallel agents only where supported; otherwise use isolated sequential workstreams. Each task records ID, owner, dependencies, branch, files, acceptance tests and final SHA.
- The Integration/Auto-Fix Reviewer owns confirmed review findings end-to-end or explicitly assigns a specialist: reproduce, root cause, minimal patch, regression, affected verification and evidence. Keep one writer per task and use a separate final reviewer; retain the active assignment when a session resumes.
- Before a push: inspect source, format, lint, typecheck, compile, and run affected unit/integration/gameplay/security/smoke checks that the approved environment supports. If a required local check cannot run, document it and do not represent the push as preverified; subsequent CI must prove the missing check before merge.
- Classify verification in exactly three groups: Build & Integrity; Functionality & Integration; Data & Transaction Safety. Preserve both approved player-load matrices, all four domain stress scenarios, durable evidence, 20 Hz tick cadence, and approved SLOs. Do not weaken thresholds, assertions, protections, or transaction safety.
- A PR may merge only when exact-final-HEAD mandatory CI, security, performance, applicable gameplay/data tests, and distinct AI review all pass, no blocking finding remains, and GitHub reports mergeable. Reconcile and verify the resulting main SHA after merge. Pending, skipped, cancelled, stale, missing or failed is not green.
- Review secrets and privacy leaks, authorization, gameplay exploits, player experience, reconnect behavior, resource leaks, hidden errors, idempotency, persistence, and concurrent transactions. All third-party source and assets require exact pinned provenance and compatible redistribution rights before import.
- Maintain pinned Godot 4.7.2 Android ARM64 GDScript, authoritative Fastify/PostgreSQL economy/gameplay, Redis ephemeral status and 20 Hz simulation. Preserve frozen Gates 1–16 and protected Step 5 capture/migration boundaries.
- GitHub Actions: prefer reusable workflow_call jobs only when they remove proven duplication; retain working checks, pinned actions, least-privilege job permissions, exact-SHA checkout, artifact evidence, bounded repair retries and no recursive auto-fix loops. No elevated token in untrusted PR jobs.
- Record every material correction, owner, commit SHA, check IDs, review, artifact and next task in Notion Build Instructions, Harvest Parts, Progress & Revision Notes, and Audit, and read back the writes. If unavailable, retain a repository checkpoint and report the precise blocker.

## Mandatory premium graphics directive

Before editing Godot art, importing assets, reviewing graphics, or approving a visual integration PR, read and enforce [`docs/ART_DIRECTION_STANDARD.md`](docs/ART_DIRECTION_STANDARD.md). Its 35/25/20/10/10 visual-review weights are proposed evaluation criteria, not measured results or substitutes for licensing, import, Android performance and independent-review gates. Follow its single-owner graphics agent roles, actual Godot screenshot evidence and explicit asset rejections. Preserve the server-authoritative architecture and use temporary low-poly meshes only as labeled scaffolding.

## Binding cinematic quality reference (owner-mandated 2026-10-17)

For every island, water, ship, environment, VFX, camera, trailer, demo, graphics PR or visual-quality claim, read and enforce [`docs/graphics/CINEMATIC_QUALITY_FLOOR.md`](docs/graphics/CINEMATIC_QUALITY_FLOOR.md) **in addition to** `docs/ART_DIRECTION_STANDARD.md`. The owner's exact video (SHA-256 `713cd6e90c6f7d589a06eb3bd4b9b2d5ebeb9c0ff711b5de527a68460dfbcb05`) and contact sheet are preserved in ChatGPT Library `/isles-of-mythos/graphics-references/`. **Nothing visibly lower quality than that reference may be accepted as premium final art**, regardless of green code CI. Review actual hash-checked reference playback alongside actual Godot-rendered scene footage; compare all applicable ship/rigging, coast/settlement, water/splashes, animation/camera, cannon/destruction and title categories. Fail closed when reference unavailable or parity not demonstrated; procedural scenes and generated concept videos are WIP only. Correct reference title-duplication artifact to `ISLES OF MYTHOS`. Preserve provenance, technical gates and measured Android performance separately; this rule does not authorize touching protected gameplay gates or deploying to production.

## Player-first uncompromising quality requirement (owner-mandated 2026-10-17)

Read and enforce [`docs/PLAYER_EXPERIENCE_QUALITY_STANDARD.md`](docs/PLAYER_EXPERIENCE_QUALITY_STANDARD.md) on ALL new game systems, graphics, story, gameplay, controls, onboarding, monetization, builds and milestone claims. Owner direction: make Isles of Mythos an exceptionally beautiful, enjoyable, responsive pirate world that players love, choose to return to and voluntarily spend on; **never substitute low-quality demos, procedural placeholders or superficial green tests for finished premium features**. The binding cinematic reference in `docs/graphics/CINEMATIC_QUALITY_FLOOR.md` remains the minimum applicable art quality. Before declaring milestones accepted, verify a genuine playable experience, player-facing value, technical and visual evidence, security/data safety and exact-SHA gates; no fabricated satisfaction/retention/revenue or mobile metrics. Pursue deep, sustainable replayability and clear, fair voluntary purchases, not manipulative addiction loops, hidden costs or pay-to-win pressure. Record deficiencies and continue targeted fixes without lowering established tests or protected gates.
