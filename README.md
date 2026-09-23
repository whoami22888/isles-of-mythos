# Isles of Mythos: Sunken Tides

Step 2 — World Foundation.

CI verifies lint, type safety, database migrations, integration tests, builds, and high/critical dependency vulnerabilities.

## World foundation

- Server-authoritative deterministic world generation.
- Fixed 32×32 tile chunks.
- Bounded server-side chunk cache.
- Client-side segmented rendering of nearby chunks only.
- HTTP chunk endpoint for bootstrapping.
- Authenticated WebSocket chunk subscriptions for low-latency streaming.
- WebSocket heartbeat and bounded payloads.
- Phaser 4.2 client renderer.

## Development

1. Copy `.env.example` to `.env`.
2. Start infrastructure with `docker compose up -d`.
3. Install dependencies with `npm install`.
4. Apply PostgreSQL migrations with `npm run migrate:up`.
5. Run `npm run typecheck`.
6. Run `npm run test`.
7. Run `npm run build`.

The server is authoritative; the client never becomes authoritative for persistent gameplay state.
