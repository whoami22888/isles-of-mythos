# Networking

## Authoritative model
The server is authoritative for movement validation, combat, inventory, currency, creature ownership, party state, guild/realm state, endgame state and persistence. Clients send intent and render authoritative responses.

## Transport
The current gameplay transport is authenticated WebSockets. Payload size, request identifiers and per-connection message rates are bounded.

## Interest management
The server uses world chunks and nearby-entity activation to limit active simulation and client updates. The client requests nearby chunk regions and unloads chunks outside its local rendering radius.

## Reliability
Combat request IDs are replay-protected. Ranged projectiles are resolved server-side. Economy, capture, crafting, trading, guild, army, realm and endgame mutations use server validation and transactional persistence where required. Persistence failures are logged.

## Scaling direction
The PDF requires spatial interest management, regional servers, cross-region synchronization, battle instancing and adaptive LOD/network strategies. These remain architectural/scaling requirements beyond the currently verified single-server implementation unless separately evidenced.

## Verification
The documentation update was based on authoritative main HEAD `83e4c14b94861c0585c1a50993f7297ad0dda497`, verified on 2026-10-08 before this documentation change. Exact-head evidence for that source state was CI #1010 PASS, Performance Acceptance #230 PASS, and Static Security Quality #202 PASS.

This is a source-state record, not a claim that a later commit has the same verification. After any HEAD change, obtain fresh exact-head evidence before describing the new HEAD as verified. Follow `.project/VERIFICATION-STANDARD.md`.
