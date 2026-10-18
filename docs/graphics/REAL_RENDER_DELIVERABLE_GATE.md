# Isles of Mythos — Non-negotiable visual deliverable gate

**Owner directive: 18 October 2026. Applies to every premium graphics, asset, cinematic and playable visual milestone.** This is an additive gate to `docs/graphics/CINEMATIC_QUALITY_FLOOR.md`, `docs/ART_DIRECTION_STANDARD.md`, `AGENTS.md` and existing Build & Integrity / Functionality & Integration / Data & Transaction Safety requirements. It must never relax existing quality, security, provenance, Android or gameplay protections.

## Absolute deliverable requirement

**No new game visual is presented, admitted, promoted or described as implemented premium graphics without at least one genuinely game-engine-rendered, independently inspectable still PNG image or a real Godot MP4 video showing the actual feature.**

- **Static assets/materials/environments:** provide one or more full-resolution PNG captures rendered by the actual Godot 4.7.2 game scene, with close and normal gameplay views where applicable.
- **Moving creatures/people, rigging, sailing ships, water/spray/wake, combat, spells, cannon impact, destruction, animated cameras and title sequences:** provide an actual **MP4 encoded from sequential Godot 4.7.2-rendered frames**, with multiple visible, non-identical frames proving motion. A single image cannot prove animation. When encoding is unavailable, preserve and verify the complete ordered genuine engine-frame sequence as an engineering intermediate; still mark user-facing deliverable NOT VERIFIED until an inspectable MP4 exists.
- **Both types of work:** provide source-asset/license/redistribution receipt, exact source SHA-256, candidate commit SHA, renderer/version, scene and camera identity, output dimensions/frame count/FPS (MP4), artifact ID, portable SHA256SUMS, capture command and an accessible human-viewable image/video. A ZIP or CI log with no verified render content does not count as visual proof.
- **Quality:** inspect the actual owner master reference video SHA-256 `713cd6e90c6f7d589a06eb3bd4b9b2d5ebeb9c0ff711b5de527a68460dfbcb05` from ChatGPT Library `/isles-of-mythos/graphics-references/cinematic-quality-floor-2026-10-17.mp4`. Compare real Godot frame(s) side-by-side with matching applicable categories. Every applicable category must be **at least as visually convincing** as the reference, with no flat/missing materials, cheap primitive replacements, incomplete alpha, unconvincing water, or obviously degraded camera composition. A technical CI pass is not an art pass.

## Hard fail-closed statuses

- **PASS:** exact-head legitimate source/asset provenance, renderer/capture, content-integrity, real visual inspection/parity, applicable gameplay/security/performance checks and final-head AI review are each independently verified. Only then may the visual milestone be accepted and merged under the existing project controls.
- **FAIL:** material quality visibly below reference in any applicable category, fake/flat substitute, blank/frozen render, missing real motion, unlicensed/mis-pinned asset, invalid frame checksum, failed test or unresolved blocking review. Keep blocked from premium admission and fix root cause.
- **NOT VERIFIED:** video master or candidate PNG/MP4 inaccessible, only code/assets/docs/CI checkmarks available, preview source uncertain, or actual Android measurements unavailable for Android performance claims. Keep blocked from premium admission.
- **NOT IN SCOPE:** a future beat not implemented/changed by this PR. This cannot waive existing integrated categories or represent full milestone acceptance.

## Never substitute

No promotional art, AI-generated image, synthetic offline render, parallax video from a still, animation of a still, GLB viewer thumbnail, uninspected zipped video, mocked screenshot or unrendered model dump can be presented as Godot proof. Inferior attempts may remain as internal diagnostic evidence but must not be shown as accepted visual work or used to justify merging premium final graphics.

Development infrastructure, tests and catalogues can still be worked on *as infrastructure*, but **must not be represented as completed visual content** until the actual PNG/MP4 quality gate is met. This is a visual admission restriction; it does not prohibit legitimate nonvisual game code.

## Compact graphics PR acceptance receipt

| Field | Required evidence |
|---|---|
| Exact PR HEAD | Full Git commit SHA + source asset SHA-256 and licensing |
| Feature and source scene | Exact Godot 4.7.2 scene, renderer, capture method |
| Artifact | Accessible actual Godot PNG(s) and MP4 for animated features; file checksums and CI artifact identifier |
| Animation verification | MP4 decoded frames, motion consistency and no still-frame loop/AI substitution |
| Owner baseline | Master SHA, applicable owner-video timestamps and captured comparison shots |
| Quality verdict | PASS / FAIL / NOT VERIFIED per applicable visual category, signed off in actual human-visible review |
| Android | Real physical-device captures, FPS/frame-time/memory/thermal numbers only when measured |
| Final integration | Build & Integrity, Functionality & Integration, Data & Transaction Safety, security, performance, exact-HEAD AI review and mergeability |

**Owner display rule:** If the owner explicitly rejects sub-baseline visual examples, do not show them unprompted even labeled WIP. Give factual text-only failure reports and keep failed renders as internal engineering artifacts unless the owner asks to inspect a specific failure.

## Production-use admission before asset generation or downloading

Do not start an expensive render, production asset download, geometry generation, PBR re-authoring or procedural substitute until the output has an identified **shipping-client use** and a recorded feature/scene owner. Each accepted work item must specify the approved Godot 4.7.2 scene and intended in-game function, asset or animation source, license and commercial redistribution rights, SHA-256 and dependencies, supported import format, required rig/clip/material/texture maps, expected Android ARM64 memory/draw-call/LOD/thermal constraints and the precise reference-video category it must satisfy. A small, bounded quarantine-only download from a verified allowlisted publisher is permitted before the final source SHA-256 and dependency hashes are known, exclusively to inspect and hash those bytes. Require declared shipping use, preliminary licensing, approved HTTPS origin/redirects, finite byte limits, a non-executable staging area and **no Godot import or manifest admission**. Validate full downloaded hashes, dependencies and commercial redistribution rights before production admission; reject incompatible/unlicensed/unverifiable, synthetic proof and knowingly sub-baseline sources before costly conversion or rendering. Do not spend credits producing images or videos the runtime cannot ingest. Do not generate additional alternatives without an evidenced deficiency and a specific requirement from the binding guide.

**Required minimum outputs only:** canonical integrable model/scene/material/script and legitimate provenance receipts; an accessible genuine Godot PNG (or verified moving MP4 for animated changes) with source/scene/camera/renderer and exact commit SHA, capture settings, artifact SHA-256 and side-by-side owner-video review; and scope-specific functional, security and performance evidence. Do not synthesize fake in-engine results, duplicate accepted art, produce extra promotional videos, or claim mobile parity without physical-device metrics. If inspected evidence demonstrates the source cannot reach reference quality within mobile constraints, mark **FAIL** (never NOT VERIFIED), record the concrete deficiency, and stop generating that variant. Reserve **NOT VERIFIED** strictly for missing, inaccessible, or inconclusive evidence; both states block admission. Keep rejected/test-only captures internal unless owner explicitly requests them.
