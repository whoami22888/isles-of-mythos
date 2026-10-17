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
