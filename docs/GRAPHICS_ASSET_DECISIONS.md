# Graphics asset decisions

Use this register alongside [the mandatory premium graphics standard](ART_DIRECTION_STANDARD.md) and `client-godot/assets/external-assets.json`.

| Candidate / source | Category | Reviewer | Licence and rendered evidence | Visual rubric (35/25/20/10/10) | Technical checks | Decision and reason | Exact SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| No candidates yet | — | — | — | Not scored | Not tested | No production art approved | — |
| Kenney Nature Kit / proposed `tropical_palm_tree_01.glb` | Palm candidate | GPT/Codex graphics integration | Kenney Nature Kit official CC0 listing: https://kenney.nl/assets/nature-kit ; proposed exact GLB URL/hash unverified; no in-engine reference capture | Not scored | No exact source bytes, SHA-256, Android or Godot renderer evidence | **NOT ADMITTED**: do not invent a GLB or insert `PENDING_LOCAL_CALCULATION`; the flat, low-poly kit is not proven suitable for premium foreground foliage. Reassess only with an exact licensed model, digest and approved visual reference comparison. | Pending exact-head branch |

Record rejected assets and reasons to avoid repeating unsuitable selections. Visual scores are proposed review evaluations, not measured facts; licensing, Godot import, device performance, exact-SHA CI and independent review are separate pass/fail gates.
# Realistic coastal restart (2026-10-17)

The owner rejected the earlier flat disc, smooth mound, palette and primitive foliage presentation as final art. This branch starts a fresh player-facing foundation without deleting the historical scenes. `client-godot/scenes/realistic_coastal_slice.tscn` is the new integration target. It admits only the verified CC0 Poly Haven `coast_rocks_05` and `tree_small_02` GLTF packages with their 1k texture dependency closure and SHA-256 manifest in `client-godot/assets/external-assets.json`.

The slice includes irregular terrain topology with the verified `coast_sand_rocks_02` diffuse/normal/roughness/AO material, authored shoreline foam bands, shallow-to-deep water shading, warm sun/ambient atmosphere, four rock formations, four instanced trees, a CC0 Dutch ship focal point, a readable gameplay camera, and a separate cinematic reveal camera. Alpha-capable PNG composites are generated from the official tree-leaf and ship-sail masks so the GLTF cutouts do not render opaque JPEG backgrounds. Repeated geometry has bounded mobile visibility ranges; physical device cost remains unmeasured. CI captures and local headless checks are evidence of loading and rendering only; visual acceptance remains blocked until a display-backed capture artifact can be downloaded and inspected. No creature asset is admitted by this restart yet.
