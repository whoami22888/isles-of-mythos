# Gate 9 — Ships and Naval Mechanics

Status: VERIFIED / FROZEN

Authoritative scope reconciled against `full-game-prompt.PDF`:
- Persistent ships and nine ship classes.
- Sailing with persistent position, heading, fuel and authoritative wind state.
- Transactional ship inventory/cargo with capacity and non-negative quantity enforcement.
- Crew persistence, supported crew types/roles, skill and morale effects.
- Cannons, ammunition, range/arc/cooldown validation and server-authoritative damage.
- Naval combat persistence including boarding, fire, repair, retreat and combat events.
- Fleet formation/membership as a required audited persistence improvement.
- Protocol/application integration and restart/concurrency regression coverage.

Closure criteria: full CI verification, independent PDF audit, correction of all required audit findings, final CI against the frozen checkpoint, and Master Project Index update.
