# Isles of Mythos: Sunken Tides

## Verified project state

The repository contains the server-authoritative implementation through Phase 16 / Endgame. This README describes the verified implementation scope; remaining post-Phase-16 PDF requirements are not implied to be complete.

Documentation source state: main HEAD `83e4c14b94861c0585c1a50993f7297ad0dda497`, verified 2026-10-08 before this documentation change.
- CI #1010 PASS
- Performance Acceptance #230 PASS
- Static Security Quality #202 PASS

These results apply only to that exact source-state SHA. After any repository change, fresh exact-head verification is required.

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
3. Install dependencies with `npm ci`.
4. Apply PostgreSQL migrations with `npm run migrate:up`.
5. Run `npm run typecheck`.
6. Run `npm run test`.
7. Run `npm run build`.

The server is authoritative; the client never becomes authoritative for persistent gameplay state.

For mandatory verification and SHA documentation rules, see `.project/VERIFICATION-STANDARD.md`.
