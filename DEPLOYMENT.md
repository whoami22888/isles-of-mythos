# Deployment

## CI / local verification

The CI workflow verifies dependency installation, reviewed native dependency rebuilds, install-script policy, high/critical npm audit findings, migrations, lint, typecheck, full tests, build, and the production Docker image.

## Production Docker deployment

The repository includes a multi-stage backend Docker image and a Compose deployment stack. The runtime image contains only the compiled server and production dependencies and runs as the unprivileged `node` user.

Required production variables:
- `POSTGRES_PASSWORD`
- `DATABASE_URL`
- `JWT_SECRET` (minimum 32 characters)
- `CORS_ORIGIN`
- `PUBLIC_DOMAIN` (public DNS name used by Caddy for automatic HTTPS)
- `ACME_EMAIL` (certificate account email)
- Optional `SERVER_PORT` (defaults to `3000`)

Start:
```bash
docker compose up -d --build
```

Compose waits for PostgreSQL health before running migrations, then starts the server only after the migration job succeeds.

Validate:
```bash
docker compose ps
curl http://localhost:3000/health
curl http://localhost:3000/ready
```

PostgreSQL and Redis are internal-only in this Compose stack; only the application port is published.

## Security

Do not commit production `.env` files or secrets. Use an external secret manager or Docker secrets for production credentials.

Production configuration requires `DATABASE_URL`, `CORS_ORIGIN`, and a strong `JWT_SECRET`. Development/test defaults remain available only outside production.

## Database recovery

The PostgreSQL named volume provides persistence across container replacement, but it is not a backup. Production acceptance still requires an external PostgreSQL backup/restore procedure and a successful restore drill.

## Client deployment

The client remains a separately built static web application. Build with `npm run build -w client` and deploy `client/dist` through the intended static/CDN layer.

## Remaining production evidence

- sustained capacity/load testing at target player concurrency
- external database backup and restore drill
- TLS termination and certificate automation
- production observability/alerting
- horizontal scaling/shard strategy
