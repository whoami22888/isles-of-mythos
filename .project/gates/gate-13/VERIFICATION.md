# Gate 13 — Invasions Verification Record

## Status

**ACTIVE / OPEN / AUDIT COMPLETE / AWAITING FINAL CI**

Branch: phase-13-invasions  
Gate 12 frozen baseline: 4d302276264d3729d0e188ba3a9acf1c33939e65

## Authoritative requirements audited

The authoritative full-game-prompt.PDF was reconsulted. Phase 13 requires:
- Threat coordinator
- Invasion scheduler
- Enemy waves
- Tactical defense
- Rewards
- Persistent consequences

Detailed PDF requirements include sections 39–41:
- Invasion origins: NPC realms, ancient monsters, pirate fleets, dragon armies, undead fleets, sea monsters, rival factions.
- Lifecycle: WARNING → MUSTER → ARRIVAL → ASSAULT → BATTLE → RESOLUTION → REWARD → COOLDOWN.
- Threat inputs: player level, guild level, territory strength, previous victories, active players, base defenses, regional threat.
- Cooperative team battle support.

## Implementation audit

### Threat coordinator
PASS — server-side deterministic threat calculation incorporates all seven required inputs and clamps the result to the authoritative safe range.

### Invasion scheduler
PASS — persistent territory schedules are stored in PostgreSQL and processed by the server timer. Scheduler execution is transactional and uses row locking.

### Enemy waves
PASS — waves are persisted, scaled from threat, contain typed combat values, activate sequentially, and maintain server-authoritative health/status.

### Lifecycle
PASS — all required phases are represented and advanced by persistent timestamps:
WARNING, MUSTER, ARRIVAL, ASSAULT, BATTLE, RESOLUTION, REWARD, COOLDOWN, followed by COMPLETE.

### Tactical defense
PASS — authenticated players can join with persistent armies; army power and defensive structures are incorporated into defense resolution. Battle actions support attack, reinforce and retreat. Frozen Gate 11 tactical army/defensive systems remain authoritative rather than being duplicated.

### Rewards
PASS — rewards are persisted per invasion/player and transactionally apply Gold Doubloons, Triumph Badges and concrete inventory loot including resources and high-tier/rare treasure records. Economy bounds are enforced through the existing authoritative economy primitives.

### Persistent consequences
PASS — invasion outcomes persist; defeats damage defensive structures and reduce territory control; regional threat and victory/defeat history persist.

### Security / concurrency
PASS — authenticated protocol boundaries, bounded inputs, army ownership checks, anti-double-deployment checks, transactional invasion ticks, row locks, replay-safe application request handling and database constraints are present.

### Persistence / restart
PASS — invasion schedules, phases, waves, participants, rewards, consequences and regional threat state are database-backed rather than process-memory authoritative state.

### Code quality
PASS — Gate 13 changed files contain no TODO/FIXME/placeholder/fake/simulated implementation markers.

## Evidence

- CI Run #594 (37209886656) passed dependencies, security audit, migrations, lint, typecheck, full tests and production build on the pre-final-hardening checkpoint.
- Run #593 failure was root-caused to a stale unit-test expected value; the implementation correctly calculated 2125 from the seven required server-side threat inputs. The assertion was corrected and Run #594 subsequently passed.
- The Gate 13 database integration test passed during Run #593, including persistent creation, army participation, wave materialization, lifecycle advancement, resolution and reward persistence.
- Post-Run-594 hardening added transactional concrete loot, cooldown metadata, configured scheduler cooldowns, sequential wave activation, army double-deployment protection and retreat restoration. A new CI run is required for the final hardening head.

## Final gate decision

Not yet frozen. Final CI on the post-audit/hardening HEAD must pass the complete pipeline. If any stage fails, diagnose and correct the root cause, rerun verification, then re-audit affected behavior.

Only after final CI is green may Gate 13 be marked VERIFIED/FROZEN and Gate 14 be activated.
