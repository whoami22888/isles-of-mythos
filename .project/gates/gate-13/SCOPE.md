# Gate 13 — Invasions

## Authoritative scope
- Server-side threat coordinator and dynamic threat scaling.
- Persistent invasion scheduler and lifecycle: WARNING → MUSTER → ARRIVAL → ASSAULT → BATTLE → RESOLUTION → REWARD → COOLDOWN.
- Enemy origins: NPC realms, ancient monsters, pirate fleets, dragon armies, undead fleets, sea monsters and rival factions.
- Persistent enemy waves with server-authoritative health and combat values.
- Tactical defense linked to persistent player armies and defensive structures.
- Cooperative participation with contribution tracking and attack/reinforce/retreat actions.
- Server-authoritative rewards including Gold Doubloons, Triumph Badges and treasure-map/rare-treasure loot records.
- Persistent consequences to defensive structures, territory control and regional threat.
- Database-backed state that survives disconnects and restarts.
- Authenticated protocol integration, validation, structured error handling and tests.

## Source evidence
Authoritative `full-game-prompt.PDF` sections 39–41 require the invasion engine, dynamic threat scaling, phases and cooperative team battle. The build directive additionally requires a timer-driven invasion engine, tactical overlay/defense, garrison defense and rewards.

## Verification requirements
Targeted tests → integration tests → regression/full suite → typecheck → lint → build → GitHub Actions CI → independent audit → final CI and freeze.
