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
The documentation update was based on authoritative main HEAD `83e4c14b94861c0585c1a50993f7297ad0dda497`, verified on 2026-10-08 before this documentation change. Exact-head evidence for that source state was CI #1010 PASS, Performance Acceptance #230 PASS, and Static Security Quality #202 PASS.

This is a source-state record, not a claim that a later commit has the same verification. After any HEAD change, obtain fresh exact-head evidence before describing the new HEAD as verified. Follow `.project/VERIFICATION-STANDARD.md` for the mandatory evidence format.
