# Godot player registration and administrator login

The Android client now offers **Player login**, **Register**, and **Admin login**.
It never asks the player to paste a JWT. HTTPS requests return 15-minute
access tokens in memory; player modes then authenticate the existing
server-authoritative WebSocket. No password, JWT, or admin credentials are
embedded in the APK, stored in project settings, or printed.

## Server configuration and deployment

This repository does **not** contain a verified live backend hostname. Deploy
the existing Fastify/PostgreSQL/Redis stack and TLS Caddy reverse proxy through
the repository's approved deployment process. This source change is not a
production deployment and does not authorize applying protected migrations.

Set the Android connection URL to `wss://YOUR_HOST/ws` and verify
`https://YOUR_HOST/health` and `https://YOUR_HOST/ready` before sign-in.
Only explicit loopback `ws://127.0.0.1`, `localhost`, or `[::1]`
addresses are allowed for development, not remote plaintext HTTP.

Configure backend `DATABASE_URL`, `JWT_SECRET` (32+ characters in production),
`PUBLIC_DOMAIN`, `CORS_ORIGIN`, and TLS per `DEPLOYMENT.md`.

## Player accounts

Register with a username, email and password (12-128 characters). The server
hashes passwords with Argon2id, stores accounts in PostgreSQL, and issues a
short-lived `accessToken`. Existing accounts use `/auth/login`; both cases
pass the returned token to the game's existing WebSocket auth frame.
The client does not persist credentials. A new login is required after session
expiry; silent refresh and the full gameplay scene are separate features.

## Administrator login (fail closed)

1. Register the intended administrator as an ordinary account.
2. Obtain the **user UUID** from that account's registration response or a
   protected database administrator read. Do not use a chosen username as
   an admin allow-list entry, because usernames can be pre-registered.
3. An authorized backend operator sets `ADMIN_USER_IDS` to a comma-separated
   allow-list of exact registered UUIDs (no default admin account or password).
   Apply this environment setting to the **backend only**, not Godot/APK.
   With the supplied Docker Compose stack, export `ADMIN_USER_IDS` in the
   host environment or the project `.env` before `docker compose up`;
   `docker-compose.yml` forwards it to the `server` service and defaults to
   empty (no administrators) when unset. Example shape only:
   `ADMIN_USER_IDS=<uuid-1>,<uuid-2>`. Do not commit real values.
4. The "Admin login" tab posts the existing username/email and password
   over HTTPS to `/auth/admin/login`. Only verified credentials plus
   allow-list membership receive an admin-scoped JWT. `/auth/admin/me`
   rechecks both JWT role and current membership.
5. The Android UI deliberately does **not** expose any administration commands
   or a management console. Admin actions will require independently
   authorized server routes, explicit permissions and security tests.

Production admin accounts should add MFA, session revocation and audit
logging before privileged administration is enabled; the login alone is
not a complete secure admin-console implementation.

## Deployment / release acceptance

Targeted server auth tests, Godot 4.7.2 headless tests, ARM64 APK export,
CI/CodeQL/Codacy/security, performance and final-head AI review must all
pass at the exact commit before merge. A real HTTPS/WSS backend with
PostgreSQL and Android device installation/login are separate gates. All
premium visual and protected migration requirements stay unchanged.
