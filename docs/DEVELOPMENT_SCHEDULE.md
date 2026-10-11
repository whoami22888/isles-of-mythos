# Isles of Mythos: Sunken Tides — Development Schedule

This schedule is the execution map for the master development directive. Work remains milestone-gated: implement, build, test, inspect failures, fix, retest, verify, document, then continue.

## Current position (verified repository state, 2026-10-11)

- **Authoritative main HEAD:** `30eef8b10d80363dc15b4256362d45b6b669019a` (Step 4 — Creature AI and base worker routing).
- **Sequential build status:** Steps 1–4 are merged. Step 2 is independently audited PASS and remains frozen. Step 5 — Combat, Capture, & Saving — has not been authorized to start because the controller's PR reconciliation and repository-control/policy preflight remains open; see the Master Project Index for the live dependency register.
- **Gate state:** Gates 1–16 remain frozen. Do not infer a new gate from the PDF's later requirements.
- **Exact current-main evidence:** CI #1128 / run `38055682984` PASS; Performance Acceptance #345 / run `38055682961` PASS; Static Security Quality #317 / run `38055682968` PASS, all on `30eef8b10d80363dc15b4256362d45b6b669019a`.
- **Current engineering priority:** reconcile the outstanding workflow-integrity PR against current main, restore required branch checks, resolve the approved performance/image policies, and then rerun exact-head verification before any authorized integration.
- **Graphics direction:** retain the current Phaser prototype while measuring actual device performance. The production renderer/engine choice remains evidence-driven; do not treat a Unity URP migration as approved or implemented without the documented technical evaluation.
- The game-gold crafting/economy implementation exists in the repository. Real-money payment/fraud functionality remains a separate security-sensitive workstream and must not be inferred from this schedule or treated as implemented without direct evidence.

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

## Phase 7 — Crafting & Economy (implemented game-gold scope; remaining real-money work is planned)

The repository already contains the game-gold crafting/economy/shop/trading implementation. The real-money payment architecture and UI described below are future/planned scope, not a claim that provider checkout, tokenized payments, webhook fulfillment, or cash-out is currently implemented.

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
