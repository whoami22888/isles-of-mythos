# Autonomous build state — 2026-10-16

Reconcile live GitHub state at session start. This is a dated observation, not a claim that subsequent commits or checks passed.

## Authority and recovery

- Load AGENTS.md, this file, .project/VERIFICATION-STANDARD.md, CONTRIBUTING.md and TESTING.md before changes.
- Requirements: original full-game-prompt.PDF; commercial Notion Build Instructions/Harvest Parts/Progress/Audit; legacy Master Index for frozen Gates 1–16 and Step 5 prerequisites.
- Godot 4.7.2 GDScript Mobile Android ARM64 client; existing Fastify/WebSocket/PostgreSQL server owns gameplay/economy/persistence. No speculative ENet or duplicated authority.
- Routine non-production source, PR and verified merge operations are owner-authorized. No production deployment, paid provider, protected migration 029/036 execution, destructive operation or frozen-gate bypass.
- Active session supports subagents and git worktrees. Two read-only audit workers were confirmed; the controller is the only current writer. Record each future claim below before editing shared paths.
- No recurring controller/scheduler is exposed by current tools. A historical claim of an hourly controller is unverified; do not create a duplicate or promise work beyond a live session. Durable task ID: `01a13b62-4eb5-7138-bc70-aea4d2ccc08e` was read and is inProgress in this session; do not send self-follow-ups. Codex Tasks list_environments returned an empty data list on 2026-10-16, so new remote task/environment provisioning is unavailable through that connector. Local subagents/worktrees remain available.
- Networked git/gh commands require a narrowly approved sandbox escalation in this session. Repository read/write and normal guarded merge were demonstrated; branch-protection administration and Actions settings access are not assumed. Never change protections or expose credentials.

## Live repository observation

Observed 2026-10-16: main `73ff4c72d837639fdf16eb4dc4a999457e3edb49`, merge of PR #137. Post-merge evidence observed 2026-10-16: CI38858329359 and Performance38858329401 pending; CodeQL38858329376, Codacy38858329377 and StaticSecurity38858329385 PASS. Do not label this SHA fully verified until all required checks complete.

Historical/source evidence observed 2026-10-16:

| Target | Exact SHA | CI | Performance | CodeQL | Codacy | Static Security |
| --- | --- | --- | --- | --- | --- | --- |
| Prior main / PR136 merge | `33cc18d407751fbac6d055c1a805d5ed0b8ad19c` | 38756298945 PASS | 38756299375 PASS | 38756299030 PASS | 38756299359 PASS | 38756299159 PASS |
| PR137 final head | `8e9fdbc022196440b5e0295522d1a525ba9ec0ee` | 38755099641 PASS | 38755099673 PASS | 38755099450 PASS | 38755099327 PASS | 38755099516 PASS |

PR137 independently reviewed and merged with expected-HEAD protection. These results do not verify its merge SHA or this documentation candidate.

## Claims and dependency-ready queue

| Task | Owner / paths | Branch / dependency | Acceptance / next action |
| --- | --- | --- | --- |
| PR137 rollback preservation | Integration Reviewer; crafting/resource gathering/tests; complete | Merged 73ff4c7; head 8e9fdbc | Preserve primary error; evict broken client after failed rollback. Four focused regressions and exact-head gates passed; verify post-merge checks. |
| PR138 controller reconciliation | Build Controller; AGENTS.md, this file, VERIFICATION-STANDARD.md | Existing PR138 branch control/autonomous-build-state-20261016; local control/reconcile-build-controller | Fix ownership conflict and missing evidence IDs. Pre-push docs consistency/diff checks, final exact-SHA CI/security/performance and distinct review. Do not duplicate this PR. |
| CI architecture | CI/CD reviewer, read-only | Seven existing workflows | Two duplicated Node/Postgres bootstraps; validation jobs otherwise distinct. Extraction optional, not a reason to rerun/duplicate suites. Current contents:read default and scoped scan/summary writes are appropriate. |
| Contextual repair/controller | Controller | Actual task/permission/scheduler capabilities required | No runnable recurring repair controller proven. Inspect task status, then use supported bounded task lifecycle; never pretend Actions performs AI repair by itself. |
| IOM01 provenance | Harvest specialist, read-only | Frozen H01–H11 pins, licensing and exact approved acquisition invocation | H01 camera is small; exclude authoritative player/inventory/autoload closure. H09 pack needs archive digest/roster. H10 embedded licence names another pack; H02 lacks per-model provenance. No unreviewed admission. |
| Game continuation | Client/Gameplay owner assigned before edits | IOM00 shell merged; IOM01 closure before dependent IOM02–07 work | Actual Android launch/physical-device evidence, complete world/camera/gameplay UI/onboarding remain unverified. A debug APK or green server CI is not game completeness. No phone testing currently authorized by active work order. |

PR136 attack replay fix is merged; do not reimplement. Open PR125 orchestration, PR121 movement and draft PR119 tracing need overlap/staleness reconciliation before any merge. Movement authority already exists.

## Unresolved evidence and protected boundaries

- Historical Performance38727971023 at main `3a559b13d129cf42842b4e3c1cd4afab36010e36` FAILED: 250-player gameplay p95 157.114805ms >150ms. Preserve the failure. Later exact-SHA runs passed, but transaction stall cause remains unproven; PR135 adds numeric pool/begin/commit/rollback timings, not a latency fix. No blind reroll, weaker threshold or durability workaround.
- Preserve both player matrices (1/50/250/1000; 10/50/100/500/1000), domain workloads (500 guild, 250 naval, 250 boss, 5000 bases), durable evidence and current SLOs. Reconcile the 20Hz requirement against actual configured cadence and measured evidence without silently rewriting acceptance.
- Step 5 remains BLOCKED pending exact Step 2 independent audit acceptance, migration029/036 deployment provenance, capture health formula/save-load reconciliation and protected owner authorization. No generic AI review substitutes.
- Verification groups only: Build & Integrity; Functionality & Integration; Data & Transaction Safety. Record limitations and nonblocking warnings; reuse evidence only for an unchanged exact SHA.

## Commercial checkpoints

- Build Instructions: <https://app.notion.com/p/3fa3fab3c26681d5a87fe776982e9895>
- Harvest Parts: <https://app.notion.com/p/3fa3fab3c266811dbd7bd1d7b636723f>
- Progress & Revision Notes: <https://app.notion.com/p/3fa3fab3c2668153b493e21f913ecfdf>
- Audit: <https://app.notion.com/p/3fa3fab3c26681f88f13f27db2ade308>

Update at meaningful milestones from fresh evidence; read back Notion writes. A pending Notion update must not block safe independent development. Do not persist tokens, identifiers, signed download URLs or private payloads here.


## Repair checkpoint — 2026-10-16 (supersedes live-status assumptions above)

- Verified main `e66683a9a30e3313773ccea1e7b07ad89d363c37` is PR139's guarded merge. Its own CI38863757677, Performance38863757674, CodeQL38863757683, Codacy38863757748 and Static38863757659 all PASS. Previous main f24d7426 also completed all five gates; historical failure38727971023 remains FAIL, stall cause unproven.
- PR140 source `0fc42ffcf3699e3fa759f789531c75f10f77b4c6`: projectile lifetime/local cooldown start at successful authorization rather than before DB wait. Deterministic clock regression reproduced zero damage before fix; 47 affected tests plus final focused regression PASS; lint/typecheck/build/static PASS. Independent exact-head review and repository Codex review found no blockers. CI38864379207, CodeQL38864379169, Codacy38864379098, Static38864379262 PASS; Performance38864379085 pending at this checkpoint. Do not merge until final acceptance passes.
- Existing PR125, branch `control/v2-orchestration-ci-enforcement`, reconciled onto this main by Codex Lead, sole writer of its workflow/controller paths. Preserve ordered required workflow runs with supported `cancel-in-progress:false` / `queue:max` (100-pending platform cap), bounded security scan jobs and SHA/run/file-bound manifests. Generic local controller is not a scheduler or AI repair service.
- PR125 verified root causes repaired: missing manifest upload masked by a whole-workflow marker check; missing required check SHA accepted; callback failure rejected before child cleanup; controller errors left running state; undefined exclusive-action regex; exclusive claims checked outside lock; leader exit cancelled descendant cleanup. Focused regressions failed before correction and now 17/17 PASS; syntax/static/diff checks PASS, root lint/typecheck/build PASS. Independent final patch audit has no unresolved bounded finding; final commit binding and configured GitHub gates required after push. No acceptance/SLO/test/protection weakening.
- PR119 tracing is superseded by richer main instrumentation; PR121 movement coverage already exists and is stronger on main. No stale PR merge or duplicate implementation. Leave closure to evidence-backed PR reconciliation.
- Next: verify PR140/125 final exact-head checks/reviews, guarded integration, then own-main checks. IOM01 source archive/importer and source-admission/provenance evidence remain external/owned-work blockers; do not duplicate GPT's asset branch. Step5 remains protected/BLOCKED. No deployment, paid service, protected migration, physical-device or full-game completeness claim.


## Unified Step5 / commercial queue — 2026-10-16

Owner: Codex Lead (sole writer); CI and independent audit workers remain read-only. Current source main `3c8938b97c38ada6fadcf42ac5c57790325567da` is guarded PR140 merge; CI38880297312, CodeQL38880297489, Codacy38880297322, Static38880297355 PASS, Performance38880297306 pending at observation. Do not substitute PR140's passed Performance38864379085 for merge acceptance.

| Work package | Status / dependency | Acceptance / next action |
| --- | --- | --- |
| Legacy Step2 | Source/focused criteria PASS; final main acceptance pending | Original independent criteria recovered from Notion2026-10-11; current server world/player/protocol30 and legacy client world/network29 tests PASS. Deterministic terrain/mills, safe coordinates, marker lifecycle and reef behavior retained. Godot world/chunk integration belongs to IOM02/03, not an added legacy Step2 approval gate. |
| Legacy Step5 combat | PARTIAL | Authoritative combat exists; PR140 fixes DB-wait flight expiry. Preserve transaction/cooldown/replay contracts. |
| Step5 capture | BLOCKED on precise requirement reconciliation | Current capture is deterministic <=25% health, not health/skill/item/rarity/level/status/environment probability. Original PDF/equation absent; do not invent balancing factors or claim complete. |
| Step5 save/load | Server authority resolved; file semantics PARTIAL | Approved commercial architecture makes PostgreSQL authoritative. Local files may hold settings/cache; never accept client progression/currency/inventory as authoritative. No requirement for a trusted local progress import may be inferred. |
| Step5 migration provenance | BLOCKED external evidence / protected actions | Need deployed full names029_trade_transaction_ids and036_pdf_92_93_mutation_idempotency with environment/run_on/release/checksum evidence. There are separate029_resource_gathering and036_guild_bank_idempotency files: numeric prefixes are ambiguous. Local/CI rows do not prove production. No protected migration execution authorized. |
| Simulation cadence | PARTIAL reconciliation | Server combat timer33ms differs from locked20Hz simulation wording; client50ms input does not prove20Hz server. Review exact specification and runtime metrics before changing cadence; preserve existing acceptance thresholds. |
| IOM00 | Shell/APK implemented; runtime PARTIAL | Keep pinnedGodot4.7.2/Mobile/AndroidARM64. Debug export does not prove physical-device gameplay. |
| IOM01 | BLOCKED source-admission closure | Reuse existing owned asset branch/package; exact archive/licence/dependency closure required, no duplicate importer or unapproved harvest. |
| IOM02 | Pending dependency-ready client slice | World/camera/LOD/streaming after admitted resources; original first-party minimal geometry may be assessed independently without inventing asset rights. |
| IOM03 | PARTIAL WebSocket seam | Authenticated authoritative command/ACK/chunk adapters and reconnect coverage; ENet only after real compatible gateway proof. |
| IOM04 | Pending Step5/IOM02/03 | Creature/capture/worker/gather/base presentation reuses Node authority, no duplicate server rules. |
| IOM05 | Pending IOM04 | Naval/guild UI + integrated30-minute onboarding and rewards; server-authoritative/idempotent. |
| IOM06 | Pending lawful server contracts | Purchases/liveops/config with explicit results and required owner/provider controls; no paid/deployment action. |
| IOM07 | BLOCKED until actual playable APK | Real Android stability/touch/network/durable-state/device acceptance, then approved release gates. |

PR125 current follow-up fixes exact-head review findings: finite commands terminate descendants after normal leader exit; Linux orphan recovery uses recorded PID/start-time/process-group identity, refuses active controllers even between child attempts, refuses unverified identities/protected operations, terminates verified nonproduction orphans and leaves blocked instead of re-executing. Controlled regressions reproduced both original failures;23 orchestration tests now PASS, root lint/typecheck/build/static/syntax/diff PASS. Fresh final-SHA independent/repository review and all configured gates required after push. This is a local finite controller, not a scheduled AI service. Unsupported legacy identities require manual reconciliation rather than unsafe PID killing.

Cost policy: bounded task packets, one owner/path; reuse unchanged exact-SHA evidence, no duplicate full suites, only affected checks while iterating and mandatory final gates; routine read-only work uses exposed economical worker setting, security/recovery final review stronger. Record root cause/prevention once; Notion checkpoints at milestones do not block independent implementation. No finite session/scheduler capability is fabricated; no timer justifies a false completion claim.

## Fresh realistic coastal restart — 2026-10-17

- Branch/PR: `feat/iom-realistic-coastal-reset`, PR #163. Latest pushed head: `dd72d738f178bde41f4b574b5fc4bf1b6c68f482`.
- Root cause of visual rejection: the prior player-facing slice was primitive/palette-oriented and lacked a convincing ship/coastal composition. Historical scenes remain intact for functional tests; they are not visual acceptance evidence.
- Implemented: irregular authored terrain, CC0 Poly Haven coastal rocks, tropical tree GLTFs, CC0 Dutch ship focal point, shallow/deep water shader, bounded shoreline foam, warm mobile-safe lighting, gameplay camera, cinematic reveal/skip/reduced-motion hooks, and per-file provenance hashes.
- Local evidence: Godot 4.6.3 import and `realistic_coastal_slice_test.gd` PASS; existing island smoke and IOM-00 connection checks PASS; provenance validator PASS for 27 files. Required CI Godot 4.7.2/Android validation remains authoritative.
- Exact PR #163 checks currently running for `dd72d73`: CI, Codacy, CodeQL, Static Security, Godot import/export, and display-backed capture. Prior capture artifact download returned HTTP 403, so no pixel-level acceptance is claimed. Visual acceptance and merge remain BLOCKED until a downloadable capture is inspected and all exact-head gates plus independent review pass.
- Source limitation: no compliant creature asset is admitted yet. This does not block coastal environment work, but it blocks a complete game visual claim. `game-dev` CLI is unavailable (exit 127); no plugin receipt is claimed.

## Checkpoint — 2026-10-28 (owner: Claude, sole writer per PR)

Base: main `46296ef1efbbe9304361ac032d83226ef4a4d90e`. Exact-SHA CI for the PRs below is NOT yet recorded; update this section with run IDs once complete.

| PR | Branch | Head SHA | Purpose | Status |
| --- | --- | --- | --- | --- |
| #225 | `fix/anti-cheat-shared-durable-state` | `72db8763b017835f4c841dcfde0fc8a42823007b` | Anti-cheat root cause: detection state was per-process (cross-instance abuse never reached a threshold; restart erased evidence). Redis atomic bounded state, PostgreSQL append-only evidence (migration `039_anti_cheat_evidence`), diagnostic only, Redis failure degrades without changing authoritative outcomes. | CI/review pending. Local: server 411/411, new real PG+Redis suite 20/20. |
| #226 | `fix/auto-merge-gate-workflow-inventory` | `34faf218e5c5576c113221952b28b140cfb7ddda` | `applicableChecks()` omitted `Isles world content and source harvest` and `IOM Coastal Ship FX Integration`; inventory now asserted against the real workflow path filters. Touches protected gate files: manual owner integration required. | CI pending. Local: gate 14/14, orchestration 23/23. |

Overlap: PRs #218/#221/#222/#197/#191 also touch `server/src/app.ts`; trial merges clean except #221 (stale base `1ecdacc`, already conflicts with merged #219; needs rebase).

Not yet done: gathering-replay / forged-command / economy-concurrency acceptance tests against real handlers (acceptance items 1, 2, 5, 6, 8, 9).

Step 5 remains BLOCKED. Repo-side migration facts only (not production evidence): `029_trade_transaction_ids` introduced 6b22f9b (2026-10-07), `029_resource_gathering` 7f1626d (2026-10-07), `036_pdf_92_93_mutation_idempotency` ea2c8e8 (2026-10-08), `036_guild_bank_idempotency` 53d706b (2026-10-07). Deployment history (environment, run_on, release, checksum from the target `pgmigrations` table) is external and unavailable from this session; no protected migration was run. Capture formula, save/load reconciliation, the independent Step 2 audit and owner authorization are likewise unproven.
