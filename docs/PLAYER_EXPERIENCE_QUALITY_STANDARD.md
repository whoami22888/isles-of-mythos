# Isles of Mythos — Player-First Quality and Sustainable Commercial Standard

**Owner directive:** 2026-10-17. Applies to all NON-PRODUCTION game, graphics, systems, player UX, and monetization work. This complements `docs/ART_DIRECTION_STANDARD.md` and the binding cinematic visual floor in `docs/graphics/CINEMATIC_QUALITY_FLOOR.md`; it does not alter frozen gates, gameplay authority, security rules, or measurable acceptance thresholds.

## Mission

Create an exceptionally compelling, beautiful and reliable fantasy pirate world that people **love playing, recommend to others, voluntarily return to and consider worth supporting financially**. Never trade lasting player trust, enjoyable play, craft quality, accessibility or stability for faster delivery or artificial engagement. A basic demo, technical proof or green CI must never be represented as a finished premium game.

**High-quality by design; evidence before claims.** "Best ever" is an ambitious design direction, not an objectively proven accolade. Every milestone must be judged against the owner's real visual references, working builds, appropriate competitor benchmarks, player playtests and actual device performance.

## Acceptance dimensions and release protections

1. **Immediate player appeal.** The first launch must show a coherent fantasy world, clear stakes and appealing agency. Character control, camera, touch UI and primary interaction must be responsive, legible and accessible. Record first-session real playtests; a successful automated smoke test does not demonstrate fun.
2. **Core game feel.** Ship traversal, exploration, creature interaction, crafting, combat and feedback must provide clear affordances, skill expression and satisfying audiovisual responses. Measure responsiveness, error rates, frame timing and navigation friction on the actual game, not on a concept video.
3. **Meaningful return reasons.** Provide optional short, medium and long loops: discoveries, mastery, co-operation, player-authored creativity and fresh world content. Avoid repetitive chores that exist only to inflate session length. New content must be genuinely playable and durable, with server-authoritative persistence.
4. **Trustworthy commercial model.** Purchases must be transparent, genuinely optional and provide clear value. No deceptive urgency, hidden fees, misleading probabilities, manipulative dark patterns, pay-to-win pressure or exploitative addiction mechanics. Do not penalize healthy breaks. Measure revenue alongside player satisfaction, fairness, refunds, complaints and long-term retention, rather than optimizing spending in isolation. Do not invent conversion or retention results.
5. **Premium visual consistency.** Enforce the owner's pinned video quality floor on every applicable ship, ocean, tropical terrain, settlement, lighting, camera, VFX and cinematic feature. Reject cheap substitutes as final artwork; preserve credible gameplay-camera quality, not just pre-rendered trailer beauty.
6. **Fluid and dependable mobile play.** Optimize for physical Samsung Galaxy S23 Ultra and lower device tiers with measured FPS distribution, frame-time p95/p99, thermal throttling, memory, input latency, streaming pauses, disconnect recovery and battery impact. Reduce unnecessary work while preserving visible near-field detail. Never claim device measurements from desktop CI.
7. **Fairness, safety and correctness.** Fastify/PostgreSQL server remains authoritative for combat/economy/capture/persistence and protected Step 5. Preserve 20 Hz, established 150 ms p95 / 300 ms p99 server criteria, transaction/idempotency/replay protections, accessibility and privacy.
8. **Evidence-first integration.** Require the project's existing three verification groups—Build & Integrity, Functionality & Integration, Data & Transaction Safety—plus exact-final-HEAD CI/security/performance, AI review and human-visible actual Godot art evidence as applicable. Pending, stale, missing or failed is not accepted. Do not merge a graphics milestone solely because its code builds.

## Milestone decision record

Before calling a feature premium / complete, record:
- Owner and final commit SHA, target client version, scene, renderer and Android hardware (if measured).
- Actual in-game footage, gameplay view and references/competition comparisons where applicable; unresolved visual dimensions = NOT VERIFIED/FAIL.
- What players do, why the action is enjoyable, and observed real playtest findings; if not tested, explicitly label UNVALIDATED.
- Scope-specific functional and persistence tests, build, security, performance and final-head review receipts.
- Purchase fairness assessment for changes touching monetization; player value, disclosed price/odds where applicable, and absence of pressure mechanics.
- Known shortcomings and next bounded step. No fabricated reviews, telemetry, gameplay completeness or performance numbers.

**Enforcement:** Reject inadequate changes as *final premium acceptance*, while allowing clearly labeled temporary scaffolding on isolated development branches. Treat quality failures as concrete backlog items with a single owner, test and acceptance evidence; do not loop or quietly lower the bar. Prioritize fixing broken gameplay or poor actual experience over generating more plans and promotional renders.
