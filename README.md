# Isles of Mythos: Sunken Tides

Phase 16 / Endgame integration is present on the current main branch. GitHub verifies current main as `83e4c14b94861c0585c1a50993f7297ad0dda497` on 2026-10-08. This is a repository HEAD check, not a claim of current-head CI/performance/security PASS.

The combat foundation remains server-authoritative: movement, stamina, cooldowns, hit validation, damage, creature AI, replay protection, and projectile simulation are resolved by the server.

## Combat foundation

- Server-authoritative player and creature combat.
- Directional melee hitboxes with creature collision radii.
- Server-side ranged projectile lifecycle with authoritative movement, expiry, collision, and damage.
- Bounded request IDs and replay protection for duplicate combat messages.
- Authoritative creature attack cooldowns and ability cooldowns.
- Server-controlled stamina, blocking, dodging, invulnerability, damage, critical hits, and status effects.
- Bounded WebSocket payloads and authenticated combat messages.
- Client renders authoritative projectile feedback but does not decide hits or damage.

## World foundation

- Server-authoritative deterministic world generation.
- Fixed 32×32 tile chunks.
- Bounded server-side chunk cache.
- Client-side segmented rendering of nearby chunks only.
- HTTP chunk endpoint for bootstrapping.
- Authenticated WebSocket chunk subscriptions for low-latency streaming.
- WebSocket heartbeat and bounded payloads.
- Phaser client renderer.

## Development

1. Copy `.env.example` to `.env`.
2. Start infrastructure with `docker compose up -d`.
3. Install dependencies with `npm install`.
4. Apply PostgreSQL migrations with `npm run migrate:up`.
5. Run `npm run typecheck`.
6. Run `npm run test`.
7. Run `npm run build`.

The server is authoritative; the client never becomes authoritative for persistent gameplay state.

## Verification documentation standard

Every current verification statement MUST identify the exact Git commit SHA, verification date, workflow/run ID where applicable, and verification status. Historical evidence must remain explicitly tied to its original commit and must never be presented as current-main evidence.