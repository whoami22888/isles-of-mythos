# Isles of Mythos: Sunken Tides

Step 2 — World Foundation.

## Development

1. Copy `.env.example` to `.env`.
2. Start infrastructure with `docker compose up -d`.
3. Install dependencies with `npm install`.
4. Apply PostgreSQL migrations with `npm run migrate:up`.
5. Run `npm run typecheck`.
6. Run `npm run test`.
7. Run `npm run build`.

## World foundation

- The server owns deterministic procedural world generation.
- World terrain is streamed in fixed 32×32 tile chunks.
- The server caches recently generated chunks with a bounded LRU-style cache.
- The client renders only nearby chunks and unloads distant chunks.
- Chunk generation is deterministic from world coordinates and the world seed.
- Resource nodes and creature spawns are generated server-side.
- Phaser 4 is used for the client renderer.

## Backend foundation

- PostgreSQL schema is versioned under `server/migrations`.
- Passwords are stored as Argon2id password hashes.
- Access tokens are short-lived JWTs.
- Authentication endpoints are rate limited.
- API schemas are exposed through OpenAPI documentation at `/documentation/`.
- `/health` is a liveness endpoint.
- `/ready` verifies PostgreSQL connectivity.
- WebSocket payloads are bounded and invalid messages are rejected.

The server is authoritative; client gameplay state must not become authoritative.
