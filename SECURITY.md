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
Current main static security acceptance: run #50 / 37567712844 PASS. Security claims beyond the controls directly exercised by code/tests/CI remain unverified.