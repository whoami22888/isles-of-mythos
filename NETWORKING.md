# Networking

## Authoritative model
The server is authoritative for movement validation, combat, inventory, currency, creature ownership, party state, guild/realm state, endgame state and persistence. Clients send intent and render authoritative responses.

## Transport
The current gameplay transport is authenticated WebSockets. Payload size, request identifiers and per-connection message rates are bounded.

## Interest management
The server uses world chunks and nearby-entity activation to limit active simulation and client updates. The client requests nearby chunk regions and unloads chunks outside its local rendering radius.

## Reliability
Combat request IDs are replay-protected. Ranged projectiles are resolved server-side. Economy, capture, crafting, trading, guild, army, realm and endgame mutations use server validation and transactional persistence where required. Persistence failures are logged.

## Global MMO boundary

Current deployment is effectively single-server/single-region. Regional server topology, cross-server synchronization, regional routing and capacity/latency load balancing are **FUTURE GATE** requirements. Local battle instancing, current-world ownership changes and PostgreSQL persistence are **PARTIAL** capabilities; they do not establish distributed battle routing, cross-region ownership transfer or regional failover. The PDF's global gateway, service separation, dynamic allocation, failure recovery and distributed consistency/load tests remain future requirements.

Movement timing is server-owned and anti-cheat movement evidence is implemented. Detection coverage for resource collection, attack frequency, coordinates and inventory mutation remains incomplete.

## Verification
The documentation update was based on authoritative main HEAD `d4de5d278369b5dc3d57aeee13c86bb4bec70c8e`, queried directly from GitHub on 2026-10-09 before this documentation change. Exact-head evidence for that source state was verify run 37915489570 PASS, sustained-load run 37915489672 PASS, and static-security run 37915489593 PASS.

This is a source-state record, not a claim that a later commit has the same verification. After any HEAD change, obtain fresh exact-head evidence before describing the new HEAD as verified. Follow `.project/VERIFICATION-STANDARD.md`.
