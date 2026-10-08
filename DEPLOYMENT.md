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

## Deployment architecture status

**Current implementation is effectively single-server/single-region.**

The current deployment stack provides a deployable server/database/edge environment, but it does not establish production global-MMO infrastructure.

### Global MMO classification
- **Regional server topology — FUTURE GATE:** no multi-region fleet/control-plane deployment is implemented.
- **Cross-server synchronisation — FUTURE GATE:** no cross-region replication/authority-consistency service is implemented.
- **Battle instancing — PARTIAL:** local server-side tactical battle instances exist; distributed battle-server allocation/routing does not.
- **Regional routing — FUTURE GATE:** no verified global gateway, server discovery or capacity/latency routing layer.
- **World ownership transfer — PARTIAL:** current territory ownership is authoritative and transferable within the world model; cross-region transfer is absent.
- **Cross-server persistence/failover — PARTIAL:** PostgreSQL persistence and backup/restore exist, but no regional authority failover/takeover protocol is implemented.

## Production global MMO requirements
The PDF requires, at minimum:
- Global control plane.
- Geographically distributed region/edge game servers.
- Global services separated from regional simulation services.
- Cross-region gateway and battle/session coordinator.
- Server transfer with locked/persisted/validated state and no duplication.
- Dynamic server allocation and server discovery.
- Region load balancing using capacity/latency/health signals.
- Cross-server persistence and authority recovery.
- Regional failure, cross-region consistency and distributed capacity/load testing.

These remain **FUTURE GATE** work. They must not be represented as production-ready merely because the current single-server deployment is containerised or PostgreSQL-backed.

## Verification evidence
Source state for this documentation change: main HEAD 0d4817acdd14cab9fda75366da857e82236c6933, queried directly from GitHub on 2026-10-08. GitHub currently reports no workflow runs attached to this exact SHA, so this change makes no current-head CI/Performance/Security PASS claim.

Follow .project/VERIFICATION-STANDARD.md for exact-SHA evidence rules.
