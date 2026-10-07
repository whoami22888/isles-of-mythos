# Architecture

## Current verified state
Isles of Mythos uses a split client/server architecture with server-authoritative persistent gameplay. Current main is verified through Phase 16 / Endgame.

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
Current main b879b1606acc72c232ee7486de21d1a194b987bd is the verified Phase 16 integration baseline. CI #858, Performance Acceptance #78 and Static Security #50 all passed. Do not describe implemented systems as future work without evidence.