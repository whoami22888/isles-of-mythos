# Deployment

## CI / verification
The CI workflow verifies dependency installation, reviewed native dependency rebuilds, install-script policy, high/critical npm audit findings, migrations, lint, typecheck, full tests, build, PostgreSQL backup/restore and the production Docker image.

## Production Docker deployment
The repository includes a multi-stage backend Docker image and Compose deployment stack. The runtime image contains compiled server code and production dependencies and runs as the unprivileged node user.

Required production variables:
- POSTGRES_PASSWORD
- DATABASE_URL
- JWT_SECRET
- CORS_ORIGIN
- PUBLIC_DOMAIN
- ACME_EMAIL

## Observability/TLS
Production Compose includes Caddy TLS termination, Prometheus and PostgreSQL exporter. The application exposes metrics internally; the public edge blocks direct metrics access.

## Recovery
PostgreSQL persistence uses a named volume, with CI backup/restore verification. Production operations still require an external backup policy and restore drill appropriate to the deployment environment.

## Scaling
The PDF requires regional server topology, cross-server synchronization, battle instancing, adaptive rendering and load testing beyond the current verified single-region/single-server deployment. These remain post-Phase-16 compliance items unless separately evidenced.

## Current acceptance evidence
Current main is `83e4c14b94861c0585c1a50993f7297ad0dda497`, verified from the GitHub `main` ref on 2026-10-08.

Exact-head CI, Performance Acceptance and Static Security workflow evidence for this commit must be recorded separately when available. Historical CI #858, Performance Acceptance #78 and Static Security #50 belong to an earlier commit and are not current-head evidence.

Every current verification statement MUST identify the exact Git commit SHA, verification date, workflow/run ID where applicable, and verification status.