## Live repository status — 2026-10-13

Live `main` HEAD: `46359b7e4251294c889eed836189372ec9410f82`. The previously listed PRs #99, #107, #109 and #111 are no longer open; the current GitHub API reports zero open pull requests and zero open issues. PR #107's documentation changes are merged into the HEAD above.

The following required workflows report SUCCESS on this exact main SHA:
- CI: <https://github.com/whoami22888/isles-of-mythos/actions/runs/38331751882>
- Performance Acceptance: <https://github.com/whoami22888/isles-of-mythos/actions/runs/38331751852>
- Static Security Quality: <https://github.com/whoami22888/isles-of-mythos/actions/runs/38331751861>
- CodeQL Advanced: <https://github.com/whoami22888/isles-of-mythos/actions/runs/38331751872>
- Codacy: <https://github.com/whoami22888/isles-of-mythos/actions/runs/38331751854>

These workflow results establish automated checks for the stated SHA only. They do not establish full product acceptance or physical-device FPS/frame-time/GPU acceptance under PDF §94. Step 5 remains blocked until the required independent Step 2 audit and all other prerequisites/authorizations are verified. Gates 1–16 remain frozen.

Historical status and baseline details are retained below as historical context; do not treat old SHAs, PR states, or workflow results as current evidence.

# Isles of Mythos: Sunken Tides — Development Schedule


## Controller reconciliation update — 2026-10-12

The current engineering priority is PR #99 workflow/performance/supply-chain reconciliation followed by PR #107 documentation reconciliation. The pre-change main baseline is `c500cf7b6cbb967fd92d99bdc33b02536a5d0097`; earlier workflow runs must not be represented as verification of later heads.

The required section 93 matrix remains 1, 50, 250 and 1,000 players. Add independent large guild-battle, large naval-battle, world-boss and 5,000-player-base scenarios. Every baseline scenario must prove persisted crafting and resource mutation evidence. Server load results do not prove physical-device FPS/GPU performance; section 94's Android/iOS device matrix remains a separate acceptance requirement.

The prior PostgreSQL digest `sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24` was recorded but not security-cleared by immutability alone. The candidate replacement is `cgr.dev/chainguard/postgres@sha256:1a417cf464d938b1b1182411416401215af7fbc88395d9b90f7c805e96d639a7`; accept it only after CI verifies the registry digest, signed SLSA provenance, SPDX SBOM attestation, CycloneDX scan SBOM and vulnerability scan, retaining the evidence artifacts. Review monthly and expedite updates through reviewed PRs.

Gates 1–16 remain frozen. No new gameplay gate or production-readiness claim is authorized by this workflow/documentation work.

This schedule is the execution map for the master development directive. Work remains milestone-gated: implement, build, test, inspect failures, fix, retest, verify, document, then continue.

## Current position

- Phase 1 — Engine Foundation: established and repeatedly CI-verified.
- Phase 2 — World: foundational procedural chunk/world streaming implemented.
- Phase 3 — Player: foundational movement, survival, inventory and hotbar implemented.
- Current engineering work: hardening the foundation before advancing into the next major gameplay systems.
- Production graphics direction: retain the current Phaser prototype for the network/gameplay vertical slice while preparing the high-fidelity production client boundary around the documented Unity URP evaluation.
- Payment/fraud architecture is a cross-cutting security foundation, not a reason to jump ahead to the Phase 7 economy implementation.

## Where the requested payment and security work belongs

### Cross-cutting foundation — NOW

Keep these concepts in the architecture from the beginning so later gameplay systems cannot be built around insecure assumptions:

1. Server-authoritative ownership of currency, inventory, purchases and entitlements.
2. Exact monetary representation using integer minor units.
3. Payment order state machine.
4. Provider adapter boundary.
5. Idempotency and replay protection.
6. Webhook verification and reconciliation boundary.
7. Step-up transaction authorization boundary.
8. Fraud/risk event model and audit requirements.
9. No raw PAN/CVV/CVC/card credentials in the game backend.
10. Future withdrawal/cash-out remains a separate, gated financial subsystem.

These are architectural constraints. They do not imply that real-money payment processing is already implemented.

## Phase 7 — Crafting & Economy

The functional payment/shop work belongs here because Phase 7 is where the game first owns the complete economy/shop domain.

### 7A — Economy core

- Recipes
- Resource economy
- Currency ledger
- Server-authoritative balances
- Item ownership
- Shop catalogue
- Shop pricing
- Trading foundation

### 7B — Game-gold shop

- Resource purchases
- Upgrade purchases
- Defence purchases
- Atomic server-side purchase transactions
- Inventory limits
- Purchase history/audit
- Abuse/velocity limits
- Shop UI

### 7C — Real-money store architecture

Only after the game-gold economy is stable:

- Real-money product catalogue separate from game-gold catalogue
- Immutable server-generated order
- Provider adapter selection/configuration
- PayPal integration
- Google Pay tokenized integration through a supported payment processor
- Card checkout through hosted/tokenized PCI-compliant provider flow
- Saved payment methods using provider tokens/IDs
- Explicit consent records for saved/automatic payments
- Payment authentication/step-up flow
- Signed webhook processing
- Idempotent fulfillment
- Refund/dispute state handling
- Fraud/risk controls
- Payment audit trail
- Reconciliation jobs
- Sandbox/test environment

### 7D — Economy/payment graphical interface

The production UI should be integrated into the normal game interface rather than bolted on later.

Required screens/components:

- Shop browser
- Category navigation: Resources / Upgrades / Defences / Premium
- Item detail panel
- Quantity selector
- Server-calculated price display
- Game-gold balance
- Premium-currency balance, if introduced
- Checkout screen
- Payment-method selector
- PayPal button
- Google Pay button where supported
- Provider-hosted/tokenized card entry
- Saved payment-method list
- Add/remove payment method
- Automatic-payment consent screen
- Transaction authorization/step-up screen
- Order confirmation
- Processing state
- Success/failure state
- Purchase history
- Refund/dispute status
- Security/risk challenge state

The UI must never be authoritative for price, balance, ownership, payment status or entitlement. It displays server state and submits user intent.

## Payment UI security gate

Before a real-money UI can be considered complete:

- Client cannot choose the final amount.
- Client cannot grant itself currency/items.
- Client cannot bypass authorization.
- Payment state transitions are validated server-side.
- Provider callbacks/webhooks are authenticated.
- Repeated callbacks cannot duplicate fulfillment.
- Sensitive transaction data is shown for confirmation.
- High-risk actions can require step-up authentication.
- Payment secrets and raw card data never enter logs or game storage.
- Automated tests cover replay, duplicate webhook, price tampering, amount tampering and authorization bypass attempts.

## Later phases

The payment foundation must remain available to later systems but must not pull later phases forward.

- Phase 8 — Breeding: no real-money breeding shortcuts; normal breeding remains gameplay-authoritative.
- Phase 9 — Ships: premium ship products, if eventually added, use the same entitlement/payment pipeline.
- Phase 10+ — Guilds, territory and warfare: purchases must not bypass server-authoritative progression, permissions or territory rules.
- Withdrawal/cash-out: only if explicitly included as a product requirement; it is a separate regulated subsystem with eligibility, jurisdiction, KYC/AML where applicable, payout verification, limits, cooling-off, fraud review, immutable ledger and reconciliation.

## Graphics and interface placement

High-fidelity graphical development is also staged rather than front-loaded:

1. Early phases: functional prototype UI and gameplay feedback.
2. Foundation hardening: UI architecture, asset pipeline, rendering abstraction and performance telemetry.
3. Economy Phase 7: production shop/payment UX structure is introduced when the underlying economy is authoritative.
4. Later graphics milestones: replace prototype presentation with the production high-fidelity client, adaptive rendering, LOD/culling, asset streaming, effects and platform-specific optimization.
5. Final acceptance: validate the graphical UI and gameplay against Android/iOS/Desktop performance budgets.

## Execution rule

Do not skip a phase because a later feature is already designed. The payment/security design is intentionally recorded now so Phase 7 can implement it without architectural rework.

The implementation sequence remains:

BUILD → TEST → INSPECT → FIX → RETEST → VERIFY → DOCUMENT → CONTINUE.

A failing gate always takes priority over new feature work.


**Compatibility warning:** this pin selects PostgreSQL 18.6, a major-version change from PostgreSQL 17. Do not accept it unless the exact-image migration, integration, regression and full CI chain passes.
