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


## Gate 7 Preflight — 2026-09-29

### Requirement reconciliation
- PDF Phase 7 explicitly requires: Recipes, Crafting, Resources, Currency, Shops, Trading.
- PDF resource economy defines Wood, Stone, Sand, Iron, Steel, Gold, Food, Fish, Crystal, Coral, Pearl, Ancient Relics, Dragon Scales, Mermaid Pearls, Arcane Dust; currency is Gold Doubloons; Triumph Badges are premium/achievement currency.
- PDF requires integer currencies, 64-bit-safe economic values including 500,000,000+, and explicitly forbids JavaScript floating-point authoritative currency calculations.
- PDF requires transactional inventory operations and atomic trading; duplicate items, negative quantities, currency overflow, item cloning and race conditions must be prevented.
- PDF requires data-driven recipes and server-authoritative economic state.

### Current repository findings
- player_profiles.gold is PostgreSQL bigint, suitable as the persistence type.
- PlayerState.gold and the current shop purchase path convert PostgreSQL bigint values to JavaScript number; this is a Gate 7 blocker because it violates the authoritative-currency precision requirement for large values.
- Existing shop.ts is only a static catalogue/calculation helper. It is not yet a complete transactional server shop system.
- No player trading implementation was found in the current server protocol/search surface.
- No Gate 7 recipe/crafting/resource service was found in the current server source surface.
- Existing inventory is JSONB and is persisted with player state; Gate 7 must introduce transactional mutation primitives rather than layering non-atomic JSON updates over the existing path.
- Existing payment code is real payment-provider infrastructure and is separate from in-game Gold Doubloons; do not conflate the two systems.
- Repository code search found no TODO/FIXME in server/src.

### Gate 7 implementation order
1. G7-03 Resource/item authority + transactional inventory primitive.
2. G7-04 Gold Doubloons 64-bit-safe currency model/ledger.
3. G7-01 Data-driven recipes.
4. G7-02 Atomic crafting transactions.
5. G7-05 Transactional server-authoritative shops.
6. G7-06 Atomic player trading with replay/concurrency controls.
7. G7-07 Protocol/client integration and bounded validation.
8. G7-08 Independent security/concurrency audit.
9. G7-09 full verification and CI.

### Scope firewall
- Do not modify verified Gate 6 base/worker logic unless a concrete Gate 7 dependency requires an interface change.
- Do not implement Phase 8 breeding, Phase 9 ships, Phase 10 guilds, or later auction/global economy infrastructure beyond minimal interfaces required by the Phase 7 trade requirement.
- Do not replace tests with mocks, skip failures, widen timeouts without root cause, or use JavaScript floating-point numbers for authoritative Gold Doubloons.

### First implementation block
The first bounded implementation block is G7-03 + G7-04: establish authoritative resource/inventory mutation primitives and a 64-bit-safe Gold Doubloon ledger. Acceptance requires unit/integration/concurrency tests before the next block is opened.