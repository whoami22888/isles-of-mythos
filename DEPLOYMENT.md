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

## Verification evidence
Documentation source state: main HEAD `3766078adfcdeda08dc768b0b8d4bce05d914827`, verified 2026-10-08 before this documentation change.
- verify run 37878375179 PASS
- sustained-load run 37878375176 PASS
- static-security run 37878375323 PASS

These results apply only to the exact source-state SHA above. They must not be transferred to later commits. Follow `.project/VERIFICATION-STANDARD.md` for current verification claims.


## Global MMO deployment status

Current deployment is effectively single-server/single-region. Containerisation and PostgreSQL persistence do not establish a production global-MMO deployment. Regional topology/control plane, cross-server synchronisation, and regional routing are **FUTURE GATE**. Local battle instances, current-world ownership changes, and database persistence are **PARTIAL**; distributed battle routing and regional authority failover are not implemented. The PDF additionally requires global/regional service separation, regional servers, cross-region gateways, dynamic allocation, load balancing, and regional failure/consistency/load testing.
