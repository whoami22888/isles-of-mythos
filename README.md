# Isles of Mythos: Sunken Tides

Step 4 — Combat Foundation.

The combat foundation is server-authoritative: movement, stamina, cooldowns, hit validation, damage, creature AI, replay protection, and projectile simulation are resolved by the server.

CI verifies lint, type safety, database migrations, integration tests, builds, and high/critical dependency vulnerabilities.

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
