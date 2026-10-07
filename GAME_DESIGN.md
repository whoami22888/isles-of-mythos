# Game Design

## Core fantasy
A persistent nautical high-fantasy MMORPG where players explore islands, gather resources, build settlements, collect mythical creatures, sail, cooperate through guilds, command armies and participate in realm-scale endgame warfare.

## Verified progression
The repository has implemented and verified the numbered phases through Phase 16:
1. Engine Foundation
2. World
3. Player
4. Combat
5. Creatures
6. Bases
7. Crafting & Economy
8. Breeding
9. Ships
10. Guilds
11. Tactical Armies
12. Realm System
13. Invasions
14. MMO Social System
15. World Events
16. Endgame

Phase 16 includes realm wars, large guild battles, high-level creatures, mythic content and territory seasons.

## Authority
Persistent state, currency, combat outcomes, creature ownership, territory, guild/army state and endgame outcomes remain server-authoritative. Important mutations are transactionally persisted.

## Post-Phase-16 scope
The PDF continues with architecture, scalability, performance, deployment and final acceptance requirements after the numbered phases. These must be audited and evidenced separately; no additional numbered gate is implied by the PDF.