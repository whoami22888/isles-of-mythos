# Third-party CC0 assets

Every asset listed here is published under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) by [Poly Haven](https://polyhaven.com). No attribution is legally required; this file records source, resolution, and any processing so the tree stays auditable.

Downloads used the public Poly Haven API (`https://api.polyhaven.com/files/{id}`) at 1K only.

## Island art pass (`art/island-pass`)

### Textures (1K JPEG, albedo / OpenGL normal / roughness / AO where used)

| Asset | Type | Source | Local path | Notes |
| --- | --- | --- | --- | --- |
| coast_sand_01 | Beach sand | https://polyhaven.com/a/coast_sand_01 | `external/polyhaven/coast_sand_01/` | Terrain sand layer |
| forrest_ground_01 | Grassy ground | https://polyhaven.com/a/forrest_ground_01 | `external/polyhaven/forrest_ground_01/` | Terrain grass layer (author spelling) |
| cliff_side | Layered cliff rock | https://polyhaven.com/a/cliff_side | `external/polyhaven/cliff_side/` | Terrain rock / steep slopes, triplanar |
| brown_planks_08 | Weathered wood | https://polyhaven.com/a/brown_planks_08 | `external/polyhaven/brown_planks_08/` | Hut walls, stilts, pier |
| thatch_roof_angled | Reed thatch | https://polyhaven.com/a/thatch_roof_angled | `external/polyhaven/thatch_roof_angled/` | Hut roofs; shader applies a warm straw tint |

### Models (1K glTF)

| Asset | Source | Local path | Processing |
| --- | --- | --- | --- |
| grass_bermuda_01 | https://polyhaven.com/a/grass_bermuda_01 | `external/polyhaven/grass_bermuda_01/` | Alpha packed into `textures/grass_bermuda_01_diff_1k.png`. Runtime MultiMesh uses the medium/small tufts only, scaled and recentred. |
| fern_02 | https://polyhaven.com/a/fern_02 | `external/polyhaven/fern_02/` | Alpha packed into `textures/fern_02_diff_1k.png`. Runtime uses the `fern_02_a` clump only. |
| shrub_03 | https://polyhaven.com/a/shrub_03 | `external/polyhaven/shrub_03/` | Alpha packed into `textures/shrub_03_diff_1k.png`. Runtime uses `shrub_03_a` only. |
| calathea_orbifolia_01 | https://polyhaven.com/a/calathea_orbifolia_01 | `external/polyhaven/calathea_orbifolia_01/` | Alpha packed into `textures/calathea_orbifolia_01_diff_1k.png`. Runtime uses `calathea_orbifolia_01_b` only. |
| boulder_01 | https://polyhaven.com/a/boulder_01 | `external/polyhaven/boulder_01/` | Original 66k-triangle scan is not in the tree. `boulder_01_mobile.gltf` is a cluster-decimated ~7590-triangle derivative that keeps nearest-vertex UVs and the official 1K CC0 textures. |

### HDRI (1K HDR)

| Asset | Source | Local path | Use |
| --- | --- | --- | --- |
| kloofendal_48d_partly_cloudy_puresky | https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky | `external/polyhaven/kloofendal_48d_partly_cloudy_puresky/` | Official 1K HDR kept for provenance. Runtime uses `kloofendal_48d_partly_cloudy_puresky_1k_ldr.png`, a filmic/sRGB 1K bake of that HDR, because the compatibility renderer clips HDR skies to white. |

### Already in the repository (unchanged licence, still CC0 Poly Haven)

coast_sand_rocks_02, coast_rocks_05, coastal_cliff_01, rock_moss_set_01, tree_small_02, island_tree_01, island_tree_02, dutch_ship_medium. See also `TITLE_SCREEN_PROVENANCE.md` and `opening/PROVENANCE.md`.

Palms (`assets/generated/palm_v2/`) are first-party game art, not Poly Haven, and are out of scope for this pass.
