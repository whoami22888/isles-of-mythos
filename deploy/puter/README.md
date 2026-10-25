# Puter HTTPS authentication gateway (infrastructure only)

Worker: `deploy/puter/isles-of-mythos-api.js`
Public existing Worker URL: `https://isles-of-mythos-api.puter.work`

## Design boundary
- The Worker is only a same-path HTTP gateway for Fastify's `/auth/register`, `/auth/login`, `/auth/admin/login`, `/auth/me` and `/auth/admin/me`.
- Existing Fastify/Argon2id/PostgreSQL owns users, password hashes, JWT issuance, roles, rate limiting and uniqueness.
- Never expose a production or privileged database connection to the Worker; do not independently store passwords in Puter KV.
- No WebSocket proxy, game simulation, player account provisioning, administrator elevation or 20Hz authority is claimed.
- No public Android APK endpoint change before deployed-backend HTTPS tests and real device authentication verification.

## Deploy prerequisites
1. Deploy the existing backend with Postgres, Redis and valid HTTPS/WSS domains using approved infrastructure.
2. Finish testing and review of PR #201 before using its admin routes.
3. Configure `UPSTREAM_API_ORIGIN` in the Worker source to the **exact** trusted HTTPS origin, with no path or credentials, and redeploy the **existing** Puter Worker, not a second name.
4. Validate credential-rate-limits, TLS, registration uniqueness under concurrency, authentication and admin allowlist against that real upstream. Test errors, non-JSON responses, redirects, timeouts and secrets in logs.
5. Set up backend origin access controls and address potential proxy bypass; ensure rate limiting is enforced across public gateway and direct backend.
6. Rebuild Android with separately confirmed HTTPS auth and WSS game URLs. Prove S23 Ultra installation, registration, player login, admin login, reconnect, and gameplay.

## Tests
```sh
node --check deploy/puter/isles-of-mythos-api.js
node deploy/puter/isles-of-mythos-api.test.cjs
```
The test checks all five auth routes refuse service without an upstream and that no fetch is attempted.

## Status
- Public v0.2 health endpoint: confirmed by owner screenshot, not proof of live account service.
- v0.3 branch: infrastructure only, undelivered; **do not deploy to production** without upstream and protected-gate verification.
- Authentication, security, exact-final-head CI, AI review, and physical device: **NOT VERIFIED**.
