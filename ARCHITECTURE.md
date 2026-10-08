# Architecture

## Current verified state
Isles of Mythos uses a split client/server architecture with server-authoritative persistent gameplay. The repository contains implemented systems through Phase 16 / Endgame; remaining post-Phase-16 PDF requirements are tracked separately and must not be represented as completed without evidence.

### Current deployment boundary
**Current implementation is effectively single-server/single-region.** PostgreSQL persistence and server-authoritative gameplay operate within the current game-server deployment model. The repository does not currently provide verified multi-region game-server orchestration, cross-server authority transfer, or regional failover.

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

## Global MMO architecture classification

| Requirement | Classification | Evidence / boundary |
|---|---|---|
| Regional server topology | **FUTURE GATE** | No authoritative multi-region server fleet/control-plane implementation or deployment topology is present. |
| Cross-server synchronisation | **FUTURE GATE** | No verified cross-server replication/consistency protocol or regional authority synchronisation service is present. Existing region_id fields are domain data, not evidence of server-to-server synchronisation. |
| Battle instancing | **PARTIAL** | Gate 11 implements server-side tactical battle instances with persistent deployed units and turn resolution, but no distributed battle-server routing/coordinator across regions is implemented. |
| Regional routing | **FUTURE GATE** | No verified global gateway/region-discovery/load-balancing path assigns players by latency, capacity, location, party/guild requirements and world region. |
| World ownership transfer | **PARTIAL** | Territory ownership can transfer through server-computed influence within the current authoritative world, but cross-region ownership handoff with duplicate/loss prevention is not implemented. |
| Cross-server persistence / failover | **PARTIAL** | PostgreSQL persistence, transactional locking and disconnect persistence exist, but no verified regional authority failover/recovery protocol exists. Database persistence alone is not cross-server failover. |

### Production Global MMO
The PDF target requires a global control plane, geographically distributed region servers, global-vs-regional service boundaries, cross-region gateways, battle/session coordination, server transfer, dynamic allocation, server discovery, regional load balancing and resilient persistence/failover. These are not current production capabilities.

### Future global-MMO gates
Track separately:
- Regional server topology/control plane.
- Cross-server synchronisation and consistency.
- Battle-server instancing/routing across regions.
- Regional gateway/routing/load balancing.
- World/territory ownership transfer between authoritative servers.
- Cross-server persistence and regional failover.
- Distributed load testing.
- Regional failure testing.
- Cross-region consistency testing.
- Capacity/load validation.

Do not infer completion from the presence of local region_id fields, local tactical battle instances, territory ownership, or PostgreSQL persistence.

## Verification rule
The source state for this documentation audit is authoritative main HEAD 0d4817acdd14cab9fda75366da857e82236c6933, queried directly from GitHub on 2026-10-08. GitHub currently reports no commit-associated workflow runs for this exact SHA, so this change does not claim current-head CI, Performance or Security PASS.

After any HEAD change, obtain fresh exact-head evidence before describing the new HEAD as verified. Follow .project/VERIFICATION-STANDARD.md for the mandatory evidence format.
