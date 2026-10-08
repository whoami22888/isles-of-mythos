# Security

## Current controls
- JWT authentication for WebSocket gameplay.
- Argon2 password hashing.
- WebSocket payload-size and per-connection rate limits.
- Bounded request IDs, target IDs, coordinates and movement inputs.
- Server-side validation for combat, inventory, currency, capture, taming, party, AI, guild, army, realm and endgame operations.
- Server-authoritative persistent state.
- Transactional inventory/currency mutations and database row/advisory locks.
- Global wild-source ownership constraint.
- CI dependency audit and reviewed native install-script allowlist.
- Static security acceptance is exercised in CI.

## Payment data
Do not store payment card PAN, CVV or CVC data in the game database. Future real-money features must use tokenized/provider-hosted payments, signed webhooks, idempotency, replay protection and reconciliation.

## Verification
GitHub verifies current main as `83e4c14b94861c0585c1a50993f7297ad0dda497` on 2026-10-08. No current-head static-security PASS is claimed without a workflow run tied to that exact SHA.

Historical Static Security run #50 / 37567712844 belongs to an earlier commit and is not current-main evidence.

Every current verification statement MUST identify the exact Git commit SHA, verification date, workflow/run ID where applicable, and verification status.