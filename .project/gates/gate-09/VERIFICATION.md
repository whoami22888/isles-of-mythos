# Gate 9 — Verification Record

Status: VERIFIED / FROZEN
Date: 2026-10-04

## Final implementation checkpoint
- Gate 9 branch: phase-9-ships.
- Final implementation HEAD before freeze documentation: 96201321616353914161d72be43721c4e77e9686.
- Gate 8 remained frozen; no Gate 8 regression was identified.

## CI recovery evidence
- Run #426: failed in server tests because the naval integration assertion expected 7 repair_lumber after repairing (which consumes one) and then adding two. Correct arithmetic is 6. Fixed in 75f856c310d9994bc0311b8eb939cedb6d19f8b7.
- Run #428: failed because the second naval integration test was accidentally nested inside the first test. Fixed in 4d644061dc2f333dc7b2e01328a1051daf77dabd, then corrected the extra closing delimiter in 5fdb1e9843590b046288cfa5c68d67e0a958b7d2.
- Run #432: full CI SUCCESS: audit, migrations, lint, typecheck, full tests and production build all passed.
- Independent end-of-gate audit identified duplicate naval cannon authority in ShipStore.fireCannon alongside the authoritative NavalStore.fireCannon. The duplicate path lacked newer Gate 9 mechanics and could create divergent server behaviour.
- Removed the duplicate method in 694fc6d157d64c12ce407a9c835b13fe7bdb51b2 and changed the ship integration test to exercise NavalStore.fireCannon in 96201321616353914161d72be43721c4e77e9686.
- Run #435 (37201787323) against the resulting implementation passed every required CI stage: dependency/install-script checks, audit, migrations, lint, typecheck, full test suite and production build.

## Independent PDF audit
- Persistent ship entities and all nine required classes are implemented.
- Required ship statistics are persisted and server-authoritative.
- Sailing persists movement/fuel and consumes authoritative world wind state.
- Ship inventory is transactional with row locking, non-negative protection and capacity enforcement.
- Crew types and all PDF roles are represented; role skill/morale effects are wired into sailing, cannon range/arc/damage, repair/firefighting and boarding.
- Cannons consume server-side ammunition and enforce range, arc and cooldown; naval damage is persisted transactionally.
- Fire, firefighting, boarding, repair and retreat are persistent/transactional server operations.
- Fleet membership was added as an audited persistence/concurrency improvement.
- Restart/concurrency integration coverage is present.
- No required Gate 9 PDF requirement remains identified as unimplemented after the duplicate-authority correction.

## Closure decision
Gate 9 satisfies its implementation, verification, audit and regression criteria and is frozen at the next documentation checkpoint commit. Gate 10 may begin only from this frozen Gate 9 checkpoint.
