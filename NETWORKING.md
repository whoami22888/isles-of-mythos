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
Current main b879b1606acc72c232ee7486de21d1a194b987bd passed full CI and sustained-load acceptance. Do not claim multi-region production deployment or battle sharding without direct evidence.