# Graphics asset decisions

Use this register alongside [the mandatory premium graphics standard](ART_DIRECTION_STANDARD.md) and `client-godot/assets/external-assets.json`.

| Candidate / source | Category | Reviewer | Licence and rendered evidence | Visual rubric (35/25/20/10/10) | Technical checks | Decision and reason | Exact SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| No candidates yet | — | — | — | Not scored | Not tested | No production art approved | — |

Record rejected assets and reasons to avoid repeating unsuitable selections. Visual scores are proposed review evaluations, not measured facts; licensing, Godot import, device performance, exact-SHA CI and independent review are separate pass/fail gates.
# Realistic coastal restart (2026-10-17)

The owner rejected the earlier flat disc, smooth mound, palette and primitive foliage presentation as final art. This branch starts a fresh player-facing foundation without deleting the historical scenes. `client-godot/scenes/realistic_coastal_slice.tscn` is the new integration target. It admits only the verified CC0 Poly Haven `coast_rocks_05` and `tree_small_02` GLTF packages with their 1k texture dependency closure and SHA-256 manifest in `client-godot/assets/external-assets.json`.

The slice includes irregular terrain topology, authored shoreline foam bands, shallow-to-deep water shading, warm sun/ambient atmosphere, four rock formations, four instanced trees, a readable gameplay camera, and a separate cinematic reveal camera. CI captures and local headless checks are evidence of loading and rendering only; visual acceptance remains blocked until a display-backed capture artifact can be downloaded and inspected. No ship or creature asset is admitted by this restart yet.
