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

## Global MMO deployment status

Current deployment is effectively single-server/single-region. Containerisation and PostgreSQL persistence do not establish a production global-MMO deployment. Regional topology/control plane, cross-server synchronization and regional routing are **FUTURE GATE**. Local battle instances, current-world ownership changes and database persistence are **PARTIAL**; distributed battle routing and regional authority failover are not implemented. The PDF additionally requires global/regional service separation, regional servers, cross-region gateways, dynamic allocation, load balancing, and regional failure/consistency/load testing.

## Renderer status

The current client uses a Phaser prototype with per-chunk Graphics batching. This does not establish production atlas/tilemap rendering, LOD, asset streaming or physical-device GPU acceptance. See GRAPHICS_ENGINE_ARCHITECTURE.md.

## Verification evidence
Documentation source state: main HEAD `d4de5d278369b5dc3d57aeee13c86bb4bec70c8e`, queried directly from GitHub on 2026-10-09 before this documentation change.
- verify run 37915489570 PASS
- sustained-load run 37915489672 PASS
- static-security run 37915489593 PASS

These results apply only to the exact source-state SHA above. They must not be transferred to later commits. Follow `.project/VERIFICATION-STANDARD.md` for current verification claims.
