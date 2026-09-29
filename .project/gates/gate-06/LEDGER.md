# Gate 6 Work Ledger

| ID | Requirement | Block | Status | Evidence | Notes |
|---|---|---|---|---|---|
| G6-01 | Building placement | 6B | IMPLEMENTED | authoritative create_building path + validation + protocol | CI verification pending |
| G6-02 | Storage | 6C | IMPLEMENTED | persistent base_storage + transactional inventory↔base transfer + capacity | CI verification pending |
| G6-03 | Production | 6C | IMPLEMENTED | timestamp-based production with persistent processing timestamp | CI verification pending |
| G6-04 | Creature workers | 6D | IMPLEMENTED | persistent base_workers + tame/party/ownership checks | CI verification pending |
| G6-05 | Resource automation | 6D | IMPLEMENTED | worker-driven production + auto priority mode | CI verification pending |
| G6-06 | Base permissions | 6E | IMPLEMENTED | server-side build/storage/production/worker/manage authorization | CI verification pending |
| G6-07 | Base/building persistence | 6A | IMPLEMENTED | migrations 008/009 + BaseStore load/runtime persistence | migration/restart verification pending |
| G6-08 | Building levels/prerequisites | 6B | IMPLEMENTED | level 1-7 validation + upgrade transactions + costs | CI verification pending |
| G6-09 | Configurable work priorities/task queue | 6D | IMPLEMENTED | persistent priorities + worker auto mode | CI verification pending |
| G6-10 | Transactional resource operations | 6C | IMPLEMENTED | row locks + atomic inventory/storage transfer + production transaction | CI verification pending |
| G6-11 | Server authority/security | 6E | IMPLEMENTED | replay wrapper + authenticated authorization + bounded protocol | final security audit pending |
| G6-12 | Restart/regression verification | 6F | IN PROGRESS | final CI/audit not yet complete | must pass full verification before gate acceptance |

## Current execution checkpoint

- Gate 5 remains frozen at `fe2c4154514c547930646cde44db6f819aa1c344`.
- Gate 6 continues from the current `phase-6-bases` checkpoint; the gate has not been restarted.
- 6A–6E implementation work is present in the current branch.
- Migration 008 constraint declarations were corrected earlier and migration 009 adds production timestamp and persistent worker assignments.
- Base mutations use per-user serialization plus database row locks for resource/building mutation boundaries.
- Base storage cannot mint resources: positive storage deltas consume the authenticated player's inventory transactionally.
- Offline production uses server timestamps and bounded elapsed processing; it does not simulate every offline frame.
- Worker auto mode consults the configured base priority queue for valid production work.
- Current HEAD: `07c84634726778bc8dd48c9872059a0f483983da`.
- Current CI run: #299 / 36553211306, pending.

## Final acceptance gates

1. Current-head CI passes migration, lint, typecheck, tests, and build.
2. Relevant Gate 5 regression suite remains green.
3. Final source audit against `SPEC.md` and authoritative PDF finds no missing Phase 6 requirement.
4. No P1/P2 correctness, security, persistence, concurrency, or fake/placeholder implementation remains.
5. Verification record is updated with concrete evidence.
6. Gate 6 is then marked complete; otherwise only the affected block is reopened.

## Process controls

- No gate restart.
- No blind test loops.
- A repeated failure with no new evidence triggers root-cause re-establishment and strategy change.
- Deferred work must remain outside the Gate 6 acceptance scope.
