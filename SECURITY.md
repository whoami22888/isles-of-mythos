# Security

## Current controls
- JWT authentication for WebSocket gameplay authentication.
- Argon2 password hashing.
- WebSocket payload-size and per-connection rate limits.
- Bounded request IDs, target IDs, coordinates, and movement inputs.
- Server-side validation for combat range, stamina, cooldowns, ammo, capture items, tame items, party slots, and AI modes.
- Server-authoritative inventory and creature ownership.
- Transactional inventory-consuming creature operations.
- CI dependency audit and reviewed native install-script allowlist.

## Payment data
Do not store payment card PAN, CVV, or CVC data in the game database. Future real-money features must use tokenized/provider-hosted payments, signed webhooks, idempotency, replay protection, and reconciliation.

## Verification rule
A security control is implemented only when exercised by tests or verified in deployment. Simulated security responses are not acceptable.
