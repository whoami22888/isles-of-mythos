# Gate 12 — Realm System

Status: VERIFIED / FROZEN pending final documentation CI.

Authoritative Phase 12 scope:
- Factions
- Territories
- Territory ownership
- Realm AI
- Trade routes
- Realm reputation

Implemented:
- Six persistent factions/realms with population, economy, military strength, resources, capital coordinates and AI state.
- Server-authoritative territory bounds, ownership, control points, resource bonuses, tax/fishing/mining/trade rights and creature-spawn bonuses.
- Guild territory claims driven by server-computed garrison military influence.
- Persistent realm fortresses and AI-driven garrison-power scaling.
- Persistent trade routes with ownership, endpoints, resource, quantity, travel duration and timestamp-based dispatch state.
- Realm reputation with bounded reputation tiers.
- Server-side realm AI tick with persistent economic/military progression and AI event logging.
- Authenticated protocol/application integration and integration/protocol tests.
