# Gate 6 Block Assignments

These blocks are derived from the Phase 6 specification and the repository state. Each block has one bounded specialist role.

## 6A — Base Domain & Persistence
Role: Senior multiplayer gameplay/database engineer.
Own: base entities, building definitions/state, migrations, persistence contracts, authoritative state model.
Acceptance: base/building state survives restart and is represented safely in the database.

## 6B — Building Placement & Upgrade
Role: Senior gameplay/world-systems engineer.
Own: placement validation, grid/world constraints, building levels, prerequisites, authoritative placement/update protocol.
Acceptance: invalid placement is rejected; valid placement persists; level/prerequisite rules are enforced server-side.

## 6C — Storage & Production
Role: Senior server-side economy/resource systems engineer.
Own: storage capacity/containers, production jobs, resource movement/processing boundaries needed by Phase 6.
Acceptance: resource operations are atomic/validated and cannot duplicate, disappear, or be client-authoritative.

## 6D — Creature Workers & Automation
Role: Senior game-AI/automation engineer.
Own: workstation assignment, task queue, configurable priorities, valid-job selection, worker execution and resource transport interfaces.
Acceptance: assigned creatures perform valid work according to priorities without per-frame expensive path recomputation.

## 6E — Base Permissions & Security
Role: Senior multiplayer security/authorization engineer.
Own: ownership, permissions, authorization checks, malformed input handling, replay/idempotency boundaries for base mutations.
Acceptance: unauthorized users cannot mutate bases/storage/production/workers; repeated requests cannot duplicate mutations.

## 6F — Integration & Verification
Role: Principal QA/integration engineer.
Own: cross-block verification, regression checks, final Phase 6 acceptance evidence.
Acceptance: all Phase 6 requirements are evidenced, targeted tests pass, full CI passes, no P1/P2 blockers remain.
