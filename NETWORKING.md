# Networking

## Authoritative model
The server is authoritative for movement validation, combat, inventory, currency, creature ownership, party state, guild/realm state, endgame state and persistence. Clients send intent and render authoritative responses.

## Transport
The current gameplay transport is authenticated WebSockets. Payload size, request identifiers and per-connection message rates are bounded.

## Interest management
The server uses world chunks and nearby-entity activation to limit active simulation and client updates. The client requests nearby chunk regions and unloads chunks outside its local rendering radius.

## Reliability
Combat request IDs are replay-protected. Ranged projectiles are resolved server-side. Economy, capture, crafting, trading, guild, army, realm and endgame mutations use server validation and transactional persistence where required. Persistence failures are logged.

## Global MMO architecture status

**Current implementation is effectively single-server/single-region.**

| Requirement | Classification | Evidence |
|---|---|---|
| Regional server topology | **FUTURE GATE** | No multi-region game-server fleet/control plane is implemented or verified. |
| Cross-server synchronisation | **FUTURE GATE** | No cross-region authoritative replication/consistency protocol is implemented or verified. region_id fields in social/world-event data do not constitute server synchronisation. |
| Battle instancing | **PARTIAL** | Gate 11 has server-side tactical battle instances and battle resolution, but they are not distributed battle servers routed across regions. |
| Regional routing | **FUTURE GATE** | No global gateway/server-discovery/load-balancing implementation is verified. |
| World ownership transfer | **PARTIAL** | Current territory ownership is server-authoritative and transferable within the world model; cross-region ownership migration is absent. |
| Cross-server persistence/failover | **PARTIAL** | PostgreSQL persistence and disconnect recovery exist; regional authority takeover and cross-server failover do not. |

## Scaling direction
The PDF requires spatial interest management, regional servers, cross-region synchronization, battle instancing and adaptive LOD/network strategies. The current repository satisfies the local/server-authoritative portions but does not satisfy the distributed global-MMO deployment target.

Production global-MMO readiness additionally requires verified regional routing, cross-server state consistency, battle/session coordination, world ownership transfer, failover/recovery and distributed load/failure testing.

These requirements remain future-gated unless an authorized gate explicitly scopes them.

## Verification
Source state for this classification: main HEAD 0d4817acdd14cab9fda75366da857e82236c6933, queried directly from GitHub on 2026-10-08. No workflow evidence is currently associated with this exact SHA.

Historical verification evidence from earlier SHAs must not be transferred to this HEAD. Follow .project/VERIFICATION-STANDARD.md.
