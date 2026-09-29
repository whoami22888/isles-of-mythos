# Gate 7 — Phase 7 Crafting & Economy

Status: ACTIVE
Baseline: 1343a8eeaa62ba78a0068b6d9049a26fd23e6201 (Gate 6 verified current HEAD)
Authoritative specification: full-game-prompt.PDF, Phase 7 — CRAFTING & ECONOMY

## Required Phase 7 systems

- Recipes
- Crafting
- Resources
- Currency
- Shops
- Trading

## Task map

| ID | Requirement | Owner | Dependencies | Acceptance evidence |
|---|---|---|---|---|
| G7-01 | Recipe data model | Primary implementation block | Gate 6 inventory/resource contracts | Data-driven recipes with validation tests |
| G7-02 | Crafting transactions | Primary implementation block | G7-01, authoritative inventory/resource state | Atomic consume/produce behaviour with failure rollback tests |
| G7-03 | Resource economy | Primary implementation block | Gate 6 storage/inventory | Authoritative resource definitions and safe quantities; no client minting |
| G7-04 | Currency | Primary implementation block | G7-03, database | Integer-safe authoritative Gold Doubloons ledger/balance; transactional mutations |
| G7-05 | Shops | Primary implementation block | G7-02/G7-04 | Server-calculated catalogue/pricing and atomic purchases |
| G7-06 | Trading | Primary implementation block | G7-03/G7-04 | Server-authoritative validated transfers with replay/concurrency protection |
| G7-07 | Protocol/client integration | Primary implementation block | G7-01..G7-06 | Bounded requests, authoritative responses, regression tests |
| G7-08 | Security/concurrency audit | Controller | G7-01..G7-07 | Independent code-path audit and targeted abuse/race/replay tests |
| G7-09 | Final verification | Controller | G7-08 | Full tests, typecheck, lint, build, CI, final HEAD verification |

## PDF constraints carried into this gate

- Recipes are data-driven.
- Inventory operations are transactional.
- Currency uses integer/database-safe representations; never JavaScript floating point for authoritative currency.
- Authoritative state remains server-controlled.
- Client input is untrusted.
- No client-authoritative currency, inventory, purchases or trading.
- No fake, placeholder or simulated authoritative behaviour.
- Phase 8+ systems remain outside this gate except minimal interfaces required by Phase 7.

## Workflow

BUILD → TARGETED TESTS → INTEGRATION → REGRESSION → FULL TEST → TYPECHECK → LINT → BUILD → CI → INDEPENDENT AUDIT → FINAL HEAD VERIFICATION

A failure must be traced to root cause. No blind retry loops or gate restart.
