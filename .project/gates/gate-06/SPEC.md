# Gate 6 — Phase 6 Bases

Status: ACTIVE
Baseline: fe2c4154514c547930646cde44db6f819aa1c344 (Gate 5 frozen)
Authoritative specification: full-game-prompt.PDF, Phase 6 — BASES

## Required Phase 6 systems
- Building placement
- Storage
- Production
- Creature workers
- Resource automation
- Base permissions

## Detailed PDF requirements carried into this gate
- Settlements with buildings including Command Centre, Storage, Lumber Mill, Steel Mill, Forge, Farm, Fishing Dock, Breeding Pen, Barracks, Creature Stable, Shipyard, Watchtower, Cannon Tower, Wall, Gate, Treasure Vault, Guild Hall, Research Laboratory, Magic Observatory.
- Buildings have levels 1–7; higher levels require increasing resources and prerequisites.
- Every base has a task queue. Default priority example: repair defenses, feed creatures, collect resources, transport resources, process resources, store resources.
- Players can configure work priorities; creature AI selects valid jobs.
- Creature work roles include fishing/net operation/irrigation/aquatic harvesting, ore smelting/base defense/furnace power/storage protection, mining/ore transport, timber cutting/log transport, scouting/light transport/map discovery.
- Resource processing and storage must be authoritative and persistent.
- Inventory/resource operations must remain transactional.
- Large authoritative values must use safe integer/database representations; never use JS floating point for authoritative currency calculations.
- Authoritative gameplay state belongs on the server/database, not the client.
- Permissions/ownership must be enforced server-side.

## Gate boundary
Phase 7 crafting/economy, Phase 8 breeding, ships, guilds, territory, and later systems are not to be implemented except where a minimal interface is strictly required by Phase 6.

## Completion rule
BUILD → TEST → INSPECT → FIX → RETEST → VERIFY → DOCUMENT → STOP.
No fake completion, skipped tests, weakened assertions, speculative refactors, or blind retry loops.
