# Graphics baseline and gameplay fine-tuning acceptance

Status: reference-only evaluation contract. This document does not change gameplay, production assets, CI thresholds, required checks or merge permissions.

## Canonical references

- Visual reference branch: [Graphic_baseline](https://github.com/whoami22888/isles-of-mythos/tree/Graphic_baseline). The baseline branch is a separate reference, not an implicit merge target.
- Baseline screenshot paths (preserve original bytes and provenance):
  - `Screenshot_20261016_211902_ChatGPT.jpg`
  - `Screenshot_20261016_212057_ChatGPT.jpg`
  - `Screenshot_20261016_212101_ChatGPT.jpg`
- Current production-client architecture: Godot 4.7.2 Mobile Android ARM64, with server-authoritative Fastify/WebSocket/PostgreSQL. Historical Phaser recommendations in `GRAPHICS_ENGINE_ARCHITECTURE.md` are not an engine migration mandate.
- Gameplay fine-tuning guide: the Isles of Mythos gameplay, retention and commercial audit. Its qualitative recommendations require separate player research and playtest evidence; do not manufacture metrics or claim a repository copy is present without locating it.

## Nonblocking visual review contract

1. Pin the exact baseline commit SHA and record screenshot hashes before comparison. Treat the branch name alone as mutable.
2. Capture candidate and baseline with documented camera, aspect ratio, viewport, scene, seed, render settings and device. Screenshots without matching scenarios are illustrative, not pixel-regression evidence.
3. Compare terrain silhouette, elevation layering, shoreline irregularity, cliff/beach transition, material provenance and texel scale, water depth/foam, lighting consistency, landmarks, composition and mobile legibility.
4. Record observations with evidence paths and reviewer verdicts. Distinguish visual judgement from deterministic raster/telemetry measurements.
5. Keep baseline and candidate artifacts in separate immutable directories. Do not overwrite approved screenshots.
6. For Godot, execute the project's existing headless import/smoke/visual workflow on the exact candidate SHA; verify the new terrain geometry test is actually invoked before counting it as coverage.
7. Physical Android GPU, FPS/frame-time, memory, thermal and battery results are **unverified** until measured on devices. Never infer them from headless export.
8. Preserve existing exact-SHA CI/security/performance and final-HEAD AI-review requirements without adding a second independent AI-review gate. This reference contract adds no blocking GitHub check and does not modify build workflows.

## Gameplay and retention fine-tuning matrix

| Goal | Player-visible acceptance question | Evidence needed | Current disposition |
| --- | --- | --- | --- |
| First-session clarity | Can a new player move, understand the next action and complete a meaningful goal? | Observed first-session playtests, completion and abandonment events | Not validated |
| Moment-to-moment fun | Is navigation, combat, gathering and sailing responsive and understandable? | Structured player sessions, controls feedback, device captures | Not validated |
| Exploration | Do islands offer recognisable landmarks, discovery and navigable routes? | Scene captures plus real player navigation tests | Not validated |
| Short progression loop | Is each session's immediate objective clear and rewarding? | Instrumented objective completions and qualitative interviews | Not validated |
| Medium/long progression | Are crafting, ships, creatures and social goals understandable without repetitive grind? | Cohort progression and retention analysis | Not validated |
| Fair commercial experience | Are purchases transparent, optional and compatible with enjoyable free play? | Economy audit, consent/UX tests and legal/provider review | Not validated |
| Accessibility/mobile | Are HUD, contrast, touch controls and effects settings usable? | Physical-device accessibility and thermal tests | Not validated |

## Candidate review record template

- Baseline commit SHA and screenshot SHA-256:
- Candidate PR and exact head SHA:
- Scenario/camera/viewport/seed:
- Godot version, device and rendering mode:
- CI/security/performance workflow IDs and conclusions:
- Geometry regression command, exit code and log:
- Baseline and candidate capture artifact URLs:
- Visual deltas (terrain, shoreline, water, lighting, composition):
- Gameplay guide impact (onboarding, exploration, accessibility):
- Confirmed defects / hypotheses / missing evidence:
- Final exact-SHA AI review, findings and disposition:
- Disposition: PASS / PARTIAL / FAIL / INCONCLUSIVE

## Scope and dependency policy

This document is additive and documentation-only. The owner's SHA-pinned cinematic reference in [CINEMATIC_QUALITY_FLOOR.md (immutable integration commit `cffe584718ac0fabd5fe4fae1e3578187a507bc2`)](https://github.com/whoami22888/isles-of-mythos/blob/cffe584718ac0fabd5fe4fae1e3578187a507bc2/docs/graphics/CINEMATIC_QUALITY_FLOOR.md) remains the mandatory premium visual-quality floor for applicable categories; the older `Graphic_baseline` is supplementary and cannot override that requirement. Do not alter `Graphic_baseline`, modify other owners' graphics PRs, import unlicensed art, introduce duplicate approval gates, weaken acceptance thresholds, or merge candidate graphics on the strength of this document alone. Visual comparison and gameplay playtests may proceed independently while existing CI executes.
