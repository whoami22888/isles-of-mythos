# IOM-04 authenticated research API — staged vertical slice

Status: **implementation and tests submitted; gameplay/mobile acceptance NOT VERIFIED until exact-SHA CI and independent review**.

Source: issue #169, original full-game-prompt.PDF, Notion Build Instructions, and AGENTS.md. Based on merged IOM-04 policy/persistence main commit `702df320ce860e1da20347f8d3ec6e0879019783`.

## HTTP contract

- `GET /creature-research`, bearer JWT required. Read-only list of nine published creature research skills; each displays this account's unlock state/XP/rank, prerequisite skills, active facility requirements, earned-material cost, and whether prerequisites/facilities are currently satisfied. `researchRequirementsMet` is **not** a guarantee of inventory affordability or successful completion; mutations must revalidate live state in a transaction.
- `POST /creature-research/unlock`, bearer JWT required. Body is exactly `{ "requestId": "unique-action-id", "skillId": "tracking" }`. The server takes ownership solely from verified JWT `sub`, refuses extra fields, verifies published skill IDs, enforces prerequisites and facility requirements through existing `CreatureResearchStore.unlock`, atomically deducts earned resources and saves the request response for retries.
- Ineligible/insufficient/conflicting actions: HTTP 409 with a bounded error code. Invalid input: HTTP 400; unauthorized: HTTP 401. Unclassified database/server errors bubble to the app's centralized handler.
- No endpoint grants training XP, creature commands, unlocks, premium purchases or flying. This is a prerequisite server API for later Godot Android UI.

## Verification contract

- New full PostgreSQL Fastify integration tests cover unauthenticated requests, owner ID tampering, visible catalogue, per-owner segregation, research cost, same-event replay, divergent-event collision, missing prerequisites, rollback on insufficient materials, retry after refill and invalid skill ID.
- Server migration `038`, old gameplay rules, protected `029/036`, and premium graphics are unchanged by this branch.
- Run focused `npm run test -w server -- src/creature-research-routes.integration.test.ts`, then complete repository lint/typecheck/tests/build and GitHub CI/security/Performance Acceptance exact head SHA and AI review. Do not merge based on partial checks.
- Actual mobile touch UI, earned lore/research-time progression, authoritative training sessions, taught commands, and flying mounts remain follow-on IOM-04/IOM-05 work. No Android gameplay or cinematic art verification claimed.
