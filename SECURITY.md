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
Verified on 2026-10-10 at main SHA `30eef8b10d80363dc15b4256362d45b6b669019a`: Static Security Quality #317 / run [38055682968](https://github.com/whoami22888/isles-of-mythos/actions/runs/38055682968) PASS. Security claims beyond the controls directly exercised by code/tests/CI remain unverified.