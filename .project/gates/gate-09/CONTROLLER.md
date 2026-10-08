# Gate 9 Controller — Ships

Status: ACTIVE / OPEN / UNVERIFIED
Starting checkpoint: 24bc960646fa802a16ab2894b1b7acee67a52ba4
Frozen Gate 8 implementation checkpoint: 4259877ea005ec80541b12796a24ea3709ec1ed9
Frozen Gate 8 verification commit: 24bc960646fa802a16ab2894b1b7acee67a52ba4

Authoritative Phase 9 scope:
- Ships
- Sailing
- Ship inventory
- Crew
- Cannons
- Naval combat

Detailed PDF naval requirements:
- Persistent ship ownership/entities.
- Ship classes: Raft, Dinghy, Sloop, Cutter, Brig, Frigate, Galleon, Dragon Ship, Ancient Warship.
- Ship statistics: hull, armor, speed, turn_rate, cargo_capacity, crew_capacity, cannon_count, sail_power, fuel/energy.
- Crew may include pirates, mermaids, dragons, NPC specialists and creature workers.
- Crew roles: Captain, Navigator, Gunner, Engineer, Medic, Scout, Boarding Specialist.
- Crew efficiency depends on skills and morale.
- Ship inventory must remain server authoritative and transactional.
- Naval combat must remain server authoritative.

Continuation order:
1. Inspect existing shipyard/building and inventory architecture.
2. Design/persist ships without duplicating existing systems.
3. Transactional ship inventory.
4. Sailing/server movement and persistence.
5. Crew assignment, roles, skills and morale.
6. Cannons and ammunition/resource accounting.
7. Server-authoritative naval combat.
8. Protocol/application integration.
9. Restart/concurrency/race-condition coverage.
10. Targeted tests.
11. Integration tests.
12. Regression suite.
13. Full suite.
14. Typecheck.
15. Lint.
16. Production build.
17. GitHub Actions CI.
18. Independent Gate 9 audit.
19. Correct defects and repeat affected verification.
20. Freeze Gate 9.
21. Only after Gate 9 freeze, advance automatically to Gate 10.

Recovery rule:
DIAGNOSE -> CONSULT PDF -> INSPECT INDEX -> PRESERVE VALID WORK -> ALTERNATE LEGITIMATE EXECUTION -> VERIFY -> RECORD -> RESUME.

No Gate 10 implementation is permitted until Gate 9 is fully verified and frozen.
