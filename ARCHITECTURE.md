# Architecture

## Current state
Isles of Mythos uses a split client/server architecture. The server is authoritative for persistent gameplay state and combat. The current client is a Phaser renderer and input layer; it does not own persistent inventory, combat damage, creature ownership, or progression.

### Server
- Fastify HTTP API and authenticated WebSocket endpoint.
- PostgreSQL persistence through PlayerStore and CreatureStore.
- Deterministic 32x32 world chunks with bounded cache.
- Server-side combat targets, projectiles, status effects, threat, and creature AI.

### Client
- Phaser world renderer.
- Chunk streaming around the player.
- WebSocket input/output for movement, combat, capture, taming, party assignment, and AI mode.
- Incoming server messages are shape-validated before use.

## Phase boundary
Phase 4 combat remains frozen at the verified hardening baseline. Phase 5 adds persistent creature capture, taming, party state, AI modes, and creature protocol/client support. Guilds, ships, breeding, territory warfare, large-scale armies, and the production Unity client remain later phases.

## Engineering rule
Implement one gated phase at a time. Use BUILD -> TEST -> INSPECT -> FIX -> RETEST -> VERIFY -> DOCUMENT -> CONTINUE. Never treat a build without runtime/test evidence as completion.
