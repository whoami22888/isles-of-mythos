# Isles of Mythos: Sunken Tides

Step 1 — Engine Foundation.

## Development
1. Copy .env.example to .env.
2. Start infrastructure with docker compose up -d.
3. Install dependencies with npm install.
4. Run npm run typecheck.
5. Run npm run test.
6. Run npm run build.

Client: Vite + TypeScript + Phaser 3.
Server: Node.js + TypeScript + Fastify + WebSocket.
Persistence infrastructure: PostgreSQL + Redis.

The server is authoritative; client gameplay state must not become authoritative.