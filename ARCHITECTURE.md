# Architecture

## Current verified state
Isles of Mythos uses a split client/server architecture with server-authoritative persistent gameplay. Current main is verified by GitHub as `83e4c14b94861c0585c1a50993f7297ad0dda497` on 2026-10-08. This HEAD verification does not, by itself, transfer workflow evidence from earlier commits.

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

## Verification standard
Every current verification statement MUST identify the exact Git commit SHA, verification date, workflow/run ID where applicable, and verification status.

For this repository, a HEAD check alone is not workflow evidence. Workflow evidence is valid only for the exact commit it executed against. When HEAD changes, current-head workflow claims must be reverified.

Do not describe implemented systems as future work without evidence.