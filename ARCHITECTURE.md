# Architecture

## Current verified state
Isles of Mythos uses a split client/server architecture with server-authoritative persistent gameplay. The repository contains implemented systems through Phase 16 / Endgame; remaining post-Phase-16 PDF requirements are tracked separately and must not be represented as completed without evidence.

### Server
- Fastify HTTP API and authenticated WebSocket endpoint.
- PostgreSQL persistence with transactional gameplay state.
- Deterministic 32x32 world chunks with bounded cache.
- Server-side combat, projectiles, status effects, threat and creature AI.
- Persistent systems for player, creatures, bases, crafting/economy, breeding, ships/naval combat, guilds, armies, realms, invasions, social/auction systems, world events, endgame warfare and territory seasons.
- Background simulation starts only from the server listening lifecycle and is cleaned deterministically on close.

### Client
- Phaser renderer and input layer.
- Chunk streaming around the player.
- WebSocket gameplay transport.
- Server-message shape validation before use.
- Client does not own persistent inventory, currency, combat outcomes, creature ownership or progression.

### Endgame
Phase 16 provides realm wars, large guild battles, high-level creatures, mythic content and territory seasons. Endgame persistence uses PostgreSQL transactions, row/advisory locks and server-side validation.

## Verification rule
The documentation update was based on authoritative main HEAD `d4de5d278369b5dc3d57aeee13c86bb4bec70c8e`, queried directly from GitHub on 2026-10-09 before this documentation change. Exact-head evidence for that source state was verify run 37915489570 PASS, sustained-load run 37915489672 PASS, and static-security run 37915489593 PASS.

This is a source-state record, not a claim that a later commit has the same verification. After any HEAD change, obtain fresh exact-head evidence before describing the new HEAD as verified. Follow `.project/VERIFICATION-STANDARD.md` for the mandatory evidence format.


## Global MMO architecture classification

- Regional server topology/control plane: **FUTURE GATE**; no verified multi-region server fleet is implemented.
- Cross-server synchronization and regional authority consistency: **FUTURE GATE**; region identifiers alone are not evidence of synchronization.
- Battle instancing: **PARTIAL**; local tactical instances exist, but distributed battle-server routing does not.
- Regional routing/load balancing: **FUTURE GATE**; no verified global gateway, server discovery, or latency/capacity routing.
- World ownership transfer: **PARTIAL** within the current world model; cross-region authority handoff is absent.
- Cross-server persistence/failover: **PARTIAL**; database persistence exists, but regional authority failover is not implemented.

The PDF target additionally requires a global control plane, regional servers, global/regional service boundaries, cross-region gateways, battle/session coordination, dynamic allocation, and regional failure/consistency/load testing. These remain future requirements, not current production capabilities.

## Renderer status

The current Phaser prototype now batches terrain and entity markers into two Graphics objects per loaded chunk. This is an incremental object-count improvement, not the production renderer. Atlas/tilemap terrain, LOD/culling, asset streaming, adaptive quality and physical-device GPU profiling remain future work. See GRAPHICS_ENGINE_ARCHITECTURE.md for the design proposal.
