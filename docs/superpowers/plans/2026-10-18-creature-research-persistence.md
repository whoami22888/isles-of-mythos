# IOM-04 Research Persistence — implementation slice

> **For agentic workers:** Use Superpowers test-driven-development and executing-plans or subagent-driven-development for each dependency-ready next task.

**Goal:** Persist earned research unlocks, player practice and individual creature training exactly once per server-confirmed event.

**Architecture:** The additive `038_creature_research_progression.js` migration creates skill, per-creature training and idempotency tables. `CreatureResearchStore` serializes each user's transactions through the player profile row, checks existing `creature-mastery.ts` research prerequisites, spends only gathered inventory materials using the audited `runEconomyMutation`, and saves a replay response in the same transaction. Creature practice requires prior trainer research, ownership and full taming. It does not expose any client-granted XP endpoint.

**Scope / branch:** Based on the isolated PR #172 policy branch. Does not touch protected migrations 029/036 or currently active graphics files. Research prices are provisional earnable balancing values. No live migration execution, full flight controls or premium render acceptance claimed.

## Acceptance
- [x] Confirm first focused tests fail for missing request/award validation.
- [x] Implement input validation; rerun local focused tests and compile.
- [x] Add durable migration and atomic `CreatureResearchStore` source.
- [x] Add PostgreSQL integration regressions: prerequisite gates, research cost debit, replay after store re-instantiation, collision, player XP replay, creature training and ownership, zero-material rollback.
- [ ] GitHub CI executes migrations, PostgreSQL integration tests, full lint/typecheck/build.
- [ ] Independent review verifies transaction locking, economy ledger, SQL correctness, recovery after rollback, privileges, data retention and tests at exact SHA.
- [ ] Follow-on: bind verified in-game research completion/commands to the store, award XP only from authoritative game events and introduce client UI. Do not call this a playable skill feature before these steps.

## Verification boundaries
**Build & Integrity:** local TypeScript compile with a temporary `pg` declaration shim, migration `node --check`; CI definitive.
**Functionality & Integration:** local Node negative tests passed; real PostgreSQL flow defined in repository tests, unverified until CI.
**Data & Transaction Safety:** replay and economy code reviewed against existing `runEconomyMutation`; integration tests are the acceptance check. No production migration deployment.


## Integration checkpoint after parent policy merge

- Policy PR #172 merged by squash to main `5eeec53b653b22acdb39f6407d8550f8db444ed4`; verified its Git tree equals the reviewed policy HEAD tree `6efc22d3cef87ccb1f833875eb408eb8eaaa8569`.
- Persistence branch reconciled that exact tree with a two-parent integration commit `77f0ae91d359fb946f2b4cee35f33de8fe8de80e`, preserving the five-file persistence-only diff and retargeting PR #176 to main.
- The original PR-targeted CodeQL and Codacy workflows specify `pull_request.branches: [main]`; no CodeQL/Codacy runs were observed on the retargeted HEAD because earlier commits/PR creation occurred while the base was the policy feature branch. This content update after retarget produces a new real source SHA and enables those required workflows; previous successful checks are historical, not transferable.
- Initial persistence lint/typecheck failure was a redundant `as PlayerSkills` assertion. Fixed in `bd34f13a95f8664bc2a39657ad67023cf17501a3`, with full CI `39042496767` subsequently successful; later merged-tree CI `39042801890` also successful.
- Independent CodeRabbit manual review of persistence was rate-limited and must not be recorded as passed. Do not repetitively invoke within rate limit. Keep draft and no release/merge until exact new HEAD required CI/security/performance and completed actionable AI review.
