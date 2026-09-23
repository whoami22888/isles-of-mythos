# Isles of Mythos: Sunken Tides

Step 1 — Engine Foundation.

## Development

1. Copy `.env.example` to `.env`.
2. Start infrastructure with `docker compose up -d`.
3. Install dependencies with `npm install`.
4. Apply PostgreSQL migrations with `npm run migrate:up`. Migrations are stored in `server/migrations`.
5. Run `npm run typecheck`.
6. Run `npm run test`.
7. Run `npm run build`.
8. CI also runs linting and a high/critical vulnerability audit.

Client: Vite + TypeScript + Phaser 3.
Server: Node.js + TypeScript + Fastify + WebSocket.
Persistence infrastructure: PostgreSQL + Redis.

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
