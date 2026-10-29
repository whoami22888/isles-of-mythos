# Isles of Mythos — Manus Lead Controller Handover

**Status: PREPARED / NOT ACTIVATED.** Owner has selected Manus as intended lead coordination agent on 2026-10-27, but no authenticated Manus session, GitHub connector, running task, or working machine has been verified by this repository change. This document is a handover contract, **not** permission to claim an operational handover or disable the existing controller.

## 1. Mission and binding sources

Coordinate development of **Isles of Mythos: Sunken Tides** into a playable, premium stylized-realistic **mobile-first 3D strategy MMORPG** with secure server-owned state. Ships and piracy are features of the larger settlements, economy, research, creatures, guilds and territory-warfare game, not a replacement genre.

Repository: <https://github.com/whoami22888/isles-of-mythos>

At each task start read applicable `AGENTS.md`, `.project/VERIFICATION-STANDARD.md`, `CONTRIBUTING.md`, `TESTING.md`, `.project/AUTONOMOUS-BUILD-STATE.md`, and only additional code/docs/logs needed to complete the task. Include the master product brief `docs/MASTER_AI_DEVELOPMENT_SPECIFICATION.md` **when actually present on the checked-out branch** (proposed separately in PR #208 on 2026-10-27; do not assume merged). Verify live `main` SHA, active PR heads, ownership and current gate results; dated documents are not live status.

Source precedence: protected/frozen owner decisions and repository gates remain binding; current live source and implementation contracts control actual code. Resolve any conflict explicitly rather than silently replacing rules.

**Approved stack (do not replace):**
- Godot **4.7.2 Mobile Renderer**, **GDScript**, GLB/glTF, Android **ARM64**.
- Blender-authored high-quality geometry, rigs, animation, UVs and proper physically based rendering (PBR).
- Node.js/TypeScript/Fastify, authenticated WebSockets, PostgreSQL durable authority, Redis for approved ephemeral roles, server-owned mutation logic; approved **20 Hz target**.
- Gameplay mutation **p95 <=150 ms, p99 <=300 ms**, plus existing more-specific simulation/load gates.
- Older Phaser/TypeScript client material is legacy, not the target 3D engine; ENet/UDP remains a separately authorized option, not a presumed deployed replacement.

## 2. Controller charter

Manus is the **intended lead coordinator**, not an automatic replacement for the existing trusted exact-SHA reviews and verification controllers. Use its GitHub connector or an explicitly authorized isolated repo worktree to inspect issues/PRs, prepare task assignments, implement bounded changes, run relevant tests, record receipts and open PRs.

One implementation owner per workstream and disjoint write surfaces. Delegate only to **agents actually available** and report any inaccessible worker or tool rather than pretending orchestration exists.

Roles when available:
- **Controller/Integration:** live dependency queue, branch ownership, scoped PR reconciliation, blocker tracking.
- **Gameplay/Server:** transactions, replay protection, persistence, combat, resource economy, settlement/warfare systems.
- **Godot Client:** networking handoff, registration/login, player controls, streaming, touch UI and gameplay view.
- **Blender/Graphics:** authorised premium meshes/materials, sea/coastal integration and actual rendered motion.
- **QA/Performance/Security:** separate exact-head analysis, tests, SLOs, mobile evidence and release controls.

Do not run duplicate repairs on branches owned by an existing Codex/GPT/graphics/performance worker. Coordinate handoff of a specific writable scope before modifying it. Pause conflicting controller writes, not legitimate independently owned workstreams.

## 3. Hard graphics acceptance

Read:
- `docs/ART_DIRECTION_STANDARD.md`
- `docs/graphics/CINEMATIC_QUALITY_FLOOR.md`
- `docs/graphics/REAL_RENDER_DELIVERABLE_GATE.md`
- `docs/PLAYER_EXPERIENCE_QUALITY_STANDARD.md`

Approved reference is a real owner master held in ChatGPT Library at
`/isles-of-mythos/graphics-references/cinematic-quality-floor-2026-10-17.mp4`.
Its SHA-256 is
`713cd6e90c6f7d589a06eb3bd4b9b2d5ebeb9c0ff711b5de527a68460dfbcb05`.

**Manus cannot assume this Library path is accessible.** Obtain an owner-supplied file via authorized transfer, validate SHA-256, decode/inspect actual moving frames, and compare the relevant scenes. Do not claim visual-parity success from descriptions or contact sheets.

Every premium graphics change must supply legitimate commercial redistribution rights/source hashes, actual imported Godot 4.7.2 source scene and material dependency manifest, real engine PNGs for stills and sequential Godot-frame **MP4 motion footage** for animations, exact code/asset SHA, frame provenance, corresponding master-video comparisons, and relevant **physical Galaxy S23 Ultra measurements** for claims about Android acceptance. Never pass inferior, placeholder, synthetic or inaccessible outputs. Do not weaken graphics or performance gates to get a pass.

Build high-quality actual game assets, not promotional stills. Only import and generate assets with an identified shipping scene/use and verified rights. Reuse already admitted assets.

## 4. Build, tests, authority and merges

- Read `AGENTS.md` first, inspect exact current PR head, ownership and diff before edits; never write to dirty user worktrees.
- Reproduce confirmed failures, fix the smallest root cause, add focused regression tests, verify callers and dependencies, then run affected integration checks and applicable full workflow gates.
- Preserve frozen legacy Gates 1-16, protected Step 5 / migration 029 and 036 boundaries, authentication, transaction atomicity and privacy.
- Maintain the existing verification categories: **Build & Integrity**, **Functionality & Integration**, **Data & Transaction Safety**. Enforce added graphics, licensing, Android, security and performance gates when applicable.
- CI, CodeQL, Codacy, static security, performance and all applicable specialized workflows must be tied to the **final exact PR SHA**. No missing/failed/pending/skipped/stale test is accepted.
- **Final AI review must meet the actual repository trust contract**, including the trusted Codex review identity and receipt where configured. A Manus/Claude self-written approval or a changed check name is not a substitute. If Codex quota is exhausted, mark BLOCKED; do not bypass the gate. Any proposed change to review-provider policy is a distinct owner-authorized, fully tested governance workstream.
- Before authorized merges, require all exact-HEAD checks, no unresolved blocking findings, genuine reviewer receipts, and mergeability; after merge recheck `main` and record the final SHA.
- Production deployments, money/paid infrastructure, protected data migrations, destructive changes and weakening security/branch/review protections require separate explicit authorization.

## 5. Staged Manus activation — no duplicate controller

**Stage A: Read-only connection check.**
1. User connects Manus's **GitHub connector** for this repo (least privilege appropriate to intended tasks), and optionally its Windows **My Computer** app for approved local worktree/Blender/Godot access. Do not request credentials in chat, files or logs.
2. Confirm Manus can read exact `main` SHA and `AGENTS.md`, inspect open PRs/workflows, identify any currently active owner, and obtain the independent video master where graphics work is planned.
3. Publish a read-only handover receipt: current SHA, connected abilities, outstanding PR owners/gates, conflicts, eligible first workstream and unavailable requirements.
4. **Do not start a second autonomous scheduler or stop the existing one** until the owner can verify the new Manus controller's real task, scope, completion reporting and no overlap. If Manus lacks scheduling, operate as an on-demand controller rather than claiming continuous work.

**Stage B: Isolated first development task.**
1. Choose ONE dependency-ready blocker from live queue; preferably real Android boot → HTTPS/WSS login → authoritative gameplay handoff **or** one owner-assigned, premium Godot graphics defect, whichever has the required inputs.
2. Reconcile active branches and PRs before claiming ownership. Do not compete with an already active graphics owner, protected reviewer or CI writer.
3. Make one bounded change on an isolated branch; verify with real tests and, for graphics, real Godot stills/motion footage and relevant mobile measurements.
4. Create a PR only when a real change exists; document exact SHA and all incomplete evidence. Never use a dummy PR to simulate work.

**Stage C: Active controller handover.**
Only after Stage A connection and Stage B accepted demonstration may the owner explicitly retire/disable conflicting scheduled GPT/Codex *controller* actions. Existing CI/review gate tooling remains intact. Manus may then coordinate dependency-ready queues with a single writer per workstream. An unfinished, failed or blocked task returns to a checkpoint; do not spin, hide failures or repeatedly consume credits without new evidence.

## 6. Copy-ready initial Manus task

> Act as the proposed lead controller of `whoami22888/isles-of-mythos`. First perform Stage A of `docs/operations/MANUS_LEAD_CONTROLLER_HANDOFF.md` as a **read-only** audit. Read `AGENTS.md` and applicable project standards. Confirm the live default-branch SHA, open PRs and exact-SHA tests, competing owners and existing automation. Summarize what is connected and what is not. Identify the single highest-priority dependency-ready workstream and the exact checks it needs. Do not change repo files, change branch protections, deploy, pay for services, merge, start recurring controllers or claim graphics parity until after the handover audit identifies valid existing ownership and verifiable evidence. Once the read-only audit is complete, follow the repository's preauthorized, scoped routine-development process without duplicating any active owner's branch. Keep verification and authorized merge conditions unchanged.

## 7. Status/report format

Every workstream checkpoint records: timestamp (with timezone), implementation owner, repo/branch, **full final SHA**, changed paths, failure/root cause, correction, relevant commands and real outputs, CI workflow/run IDs with exact status, security/performance outcomes, independently recorded AI review, actual Godot artifact URLs/checksums and reference results if applicable, S23 Ultra measurements if applicable, unresolved blockers and next authorized action.

Use **PASS**, **FAIL**, **NOT VERIFIED**, **NOT IN SCOPE** precisely. **A successful GitHub workflow is not proof of gameplay, premium art or physical-device acceptance.**

---

This file is a **handover proposal**. Until a connected Manus task completes Stage A and its provenance is recorded, the existing controller stays the operational authority.
