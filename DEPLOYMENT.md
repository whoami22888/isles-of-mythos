# Deployment

## Current development deployment
1. Configure `.env` from `.env.example`.
2. Start PostgreSQL with Docker Compose.
3. Install dependencies.
4. Apply migrations.
5. Run lint, typecheck, tests, and build.
6. Deploy the server and client through the intended hosting layer.

## CI gate
The verification workflow provisions PostgreSQL, installs with scripts disabled, rebuilds reviewed native dependencies, checks high/critical audit findings, applies migrations, runs lint/typecheck/tests/build, and cleans up service containers.

## Production requirements still ahead
External secret management, TLS termination, observability, backups, controlled migration rollout, horizontal simulation/shard strategy, CDN/static asset delivery, capacity testing, and mobile network performance validation remain later production gates.
