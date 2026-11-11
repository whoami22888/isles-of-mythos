# Opening battle asset provenance

These files are the client-only opening in `client-godot/gameplay/opening_battle.tscn`. They are not an admission that the scene meets the cinematic quality floor. SHA-256 values are of the bytes committed in this tree. Godot 4.7.2 imports GLB/FBX with the default scene importer (`nodes/root_scale=1.0`) and the shared Kenney palette from `Textures/colormap.png`. Audio was peak- or loudness-normalised so decoded peaks stay below 0 dBFS. No sample was clipped.

## Previously admitted CC0 scenery

The two fighting galleons, the cliff, the sand, and the volcano rock are the Poly Haven models and textures already registered in `client-godot/assets/external-assets.json` (CC0-1.0, commercial redistribution allowed). This change does not re-download them.

| Use | Path |
| --- | --- |
| Player and navy galleons, including sail cloth | `client-godot/assets/external/polyhaven/dutch_ship_medium/` |
| Island cliff | `client-godot/assets/external/polyhaven/coastal_cliff_01/` |
| Beach sand | `client-godot/assets/external/polyhaven/coast_sand_rocks_02/` |

Sail sway is a vertex shader on the existing sail textures. The leviathan is an original generated silhouette mesh, not a third-party creature.

## Kenney Pirate Kit 2.1 (CC0-1.0)

- Author: Kenney (www.kenney.nl)
- Page: https://kenney.nl/assets/pirate-kit
- Mirror used for the bytes: https://opengameart.org/content/pirate-kit (`kenney_pirate-kit_2.1.zip`)
- License: [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/). Text in `kenney/License-pirate-kit.txt`. Credit is not required.
- Archive SHA-256: `667ed2caf92954ddb98f7b7cede831fe99ab75063c26b25e23d32715bee9c943` (3,154,665 bytes)

Extracted into `client-godot/assets/opening/kenney/`: cannon, cannon-ball, barrel, chest, both flags, both palms, rocks-sand, dock, watchtower, ship-pirate-large, and `Textures/colormap.png`. The GLBs reference that palette by relative URI.

## Kenney Animated Characters 1 (CC0-1.0)

- Author: Kenney
- Page: https://kenney.nl/assets/animated-characters-protagonists
- License: [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/). Text in `kenney/License-animated-characters.txt`.
- Archive SHA-256: `ec3787de70fa2200256848d74201b10f6b6c3126594e9857bf989753312c2b84` (581,441 bytes)

`characterMedium.fbx` is the rigged mesh. `idle.fbx`, `run.fbx`, and `jump.fbx` supply the clips. `criminalMaleA.png` is the albedo. The opening copies the longest clip from each animation file onto that skeleton.

## Recorded audio (CC0-1.0)

| Shipped file | SHA-256 | Origin |
| --- | --- | --- |
| `audio/explosion.ogg` | `d25a59b68fab4ec270c9c024b0ce3508cc80cdab8a64f674f0cced6a93f97955` | rubberduck, [25 CC0 bang / firework SFX](https://opengameart.org/content/25-cc0-bang-firework-sfx), `fw_04.ogg`. Archive SHA-256 `c0c9ecc11e2dc0d190f0cced755569858234b8528286bc83becb6314c663407f` |
| `audio/hit.ogg` | `ba077b387cb747b8a53bac115eb1b5cfd512f2f27777ef03fdd148e0196ed605` | same pack, `shot_01.ogg` |
| `audio/ocean.ogg` | `87eb6546b02e52b57943aba569f05d44bb1154ca7067c3af243b35dd4de19f58` | jasinski, [Beach Ocean Waves](https://opengameart.org/content/beach-ocean-waves), `wave_02_cc0-18363__jasinski__alkaibeach.flac` (SHA-256 `53b5c28c0edc36f049e77e65f2cf8a86135103328c44c1507c416e6469d18096`), looped to 18 s |
| `audio/roar.ogg` | `2e28bf0df5876c4228650dff9a59c1f8fc18e5e9900d820b27500cf6568bdec9` | trazzz123, [CC0 Deep Monster Roar](https://opengameart.org/content/cc0-deep-monster-roar), `monster_roar.wav` (SHA-256 `040d2841619c732098c30a638731317d13d7647e5ce1a75a3246219ce4b162ff`) |
| `audio/cheer.ogg` | `4fc5a954582cc3892cf8037243ce08cc54c5ec428c2e6bffa474b0520e975b6f` | eXpl0it3r, [Applause in a large hall or church](https://opengameart.org/content/applause-in-a-large-hall-or-church), first 4.5 s of `applause-clapping-church-crowd-immersive.wav` (SHA-256 `0d3bfde5a050f3c5e6685bd7f1efc7ab1d289fbad65c88c1ce9b4691228c69c9`) |
| `audio/swing.ogg` | `b726014de7fa3e6d47c3146582744b5270471100ace0fd4b87a8afb9baba9173` | artisticdude, [Swishes sound pack](https://opengameart.org/content/swishes-sound-pack), `swishes/swish-7.wav`. Archive SHA-256 `7980215241b739a787dcf26f660ce510bb237900968789395a86911619795693` |

The title cannon and shanty are documented in `client-godot/assets/TITLE_SCREEN_PROVENANCE.md`. `soft_round.png` is an original radial particle sprite generated for this scene, not a third-party texture.


## Opening build v1 library (`library/`)

Real-scale meshes for the opening battle, its endings, and the castaway avatar. Embedded textures are 1K JPEG, extracted by Godot beside each `.glb`. SHA-256 values are of the committed `.glb` bytes.

| Shipped file | SHA-256 | Origin | Licence | Notes |
| --- | --- | --- | --- | --- |
| `library/cannon_01/cannon_01.glb` | `5406262b5c10c06668ca42e931384217bd73b931d0164816e274b8388bd52018` | Poly Haven [cannon_01](https://polyhaven.com/a/cannon_01) (Yann Kervran, James Ray Cock) | CC0-1.0 | Rebuilt from the FBX (the upstream glTF buffer is truncated), decimated 41k to 4.2k tris, metallic 0, 1K JPEG. |
| `library/castaway_ubc_rigged/castaway_ubc_rigged.glb` | `84ced2068d3538531432f46c2d966331233cc400161fedfca808b50f5b80e7bc` | Quaternius [Ultimate Base Characters](https://quaternius.com) Superhero_Male body with hair and beard, rigged to the [Universal Animation Library](https://quaternius.com) (Standard) UE-style skeleton; clips Idle, Walk, Run, Attack, SwordIdle, Dodge, Jump, Interact, PickUp, Kneel, Death, Hit, Punch, Talk | CC0-1.0 | Blender merge, linen shirt / canvas trousers / dark hair materials, 1K JPEG. Stand-in castaway and crew. |
| `library/cliff_hy3d/cliff_hy3d.glb` | `d9c639ef309c473d9c91707e6fb21d0cfed65e05dbb72c139abbfb3eea9373e3` | Tencent HY 3D Global (free tier), first-party concept | HY3D free tier, commercial terms unconfirmed | Flat-base cut, decimated, 1K. |
| `library/coast_rocks_01/coast_rocks_01.glb` | `62d0827bf0e8542ff9f1bb33e6a6d811ae345a2a66ed01bcb965ff93f07e2563` | Poly Haven [coast_rocks_01](https://polyhaven.com/a/coast_rocks_01) | CC0-1.0 | 1K, reef dressing only. |
| `library/coast_rocks_03/coast_rocks_03.glb` | `3d5f20162aa1c9d568ee01975140d9f566fa2a3e9f2c5fe7a5bcbaf3b5eeb36d` | Poly Haven [coast_rocks_03](https://polyhaven.com/a/coast_rocks_03) | CC0-1.0 | 1K, reef dressing only. |
| `library/dark_boulder_06/dark_boulder_06.glb` | `6c3fb0bfb21d0995dcb1246e4904c7d4451de6a8ed4487173cbc4ef73f5ca712` | Poly Haven [namaqualand_boulder_06](https://polyhaven.com/a/namaqualand_boulder_06) | CC0-1.0 | Regraded grey-brown, 1K. |
| `library/driftwood_branches/driftwood_branches.glb` | `a181b9c219cb6fd45cfc8d1f8a389fd5b488cb941965167b228db60b69508489` | Poly Haven [dry_branches_medium_01](https://polyhaven.com/a/dry_branches_medium_01) | CC0-1.0 | 1K. |
| `library/driftwood_trunk/driftwood_trunk.glb` | `f1904477c90597a941ddbcbc28502ea3137e6ba34db283612ef9bc3b2e3d8d61` | Poly Haven [dead_tree_trunk](https://polyhaven.com/a/dead_tree_trunk) | CC0-1.0 | 1K. |
| `library/hull_half_bow/hull_half_bow.glb` | `8d30bdfccf8b5e4000710bfff8718c3f23c98b0d909563c12850be1db6bcdcaa` | Poly Haven [dutch_ship_large_02](https://polyhaven.com/a/dutch_ship_large_02), broken in Blender (first-party break script) | CC0-1.0 | Meshes joined per material (3 draw calls), 1K. |
| `library/hull_half_stern/hull_half_stern.glb` | `0c1afb7c1ce0c2f7a11d8e51772b51dc10aeb87e799cf4c6ad5b1827e959e5ad` | Poly Haven [dutch_ship_large_02](https://polyhaven.com/a/dutch_ship_large_02), broken in Blender (first-party break script) | CC0-1.0 | Meshes joined per material (3 draw calls), 1K. |
| `library/jungle_clump_hy3d/jungle_clump_hy3d.glb` | `cda83fb028b1c8182e800c9f4e19dfd9a32dfe3291d4aaf5bb16be33c797ca89` | Tencent HY 3D Global (free tier), first-party concept | HY3D free tier, commercial terms unconfirmed | Decimated to ~9.7k tris, 1K. |
| `library/leviathan_head_hy3d/leviathan_head_hy3d.glb` | `b2c32f21b88f8d9e6ce1894358216c072fee8a3fd9fadac1b4686edb02839a2b` | Tencent HY 3D Global (free tier), first-party concept | HY3D free tier, commercial terms unconfirmed | Trimmed and capped at the waterline, roughness floor 0.55, no emissive, 1K. Graded in scene. |
| `library/leviathan_tentacle/leviathan_tentacle.glb` | `aa4e32732be2c7c5882ced5f2b89cc833ab7665a5d79ff7d9a85b50f26fffa84` | Z-Image-Turbo concept (Apache-2.0) to TripoSR (MIT), run locally | Output owned; TripoSR MIT, Z-Image-Turbo Apache-2.0 | 1K. Graded in scene. |
| `library/plank_pile_procedural/plank_pile_procedural.glb` | `93fdc7914efcf868c5e2f2eb0c7b46d59a6b3fa87abe6aef18f023605edbd8dd` | First-party Blender procedural with a Poly Haven CC0 plank texture | CC0-1.0 texture; mesh first-party | 1K. |
| `library/rope_coil_procedural/rope_coil_procedural.glb` | `163c61d1f88fd707c1a7164951b657295e7d3b59344b160ccab2dcf89511461b` | First-party Blender procedural with a Poly Haven CC0 hessian texture | CC0-1.0 texture; mesh first-party | 1K. |
| `library/sea_stack_boulder_02/sea_stack_boulder_02.glb` | `d1811597023060419b403f5c4b211a57f981ca9c9cce7941152f1e18056f1293` | Poly Haven [namaqualand_boulder_02](https://polyhaven.com/a/namaqualand_boulder_02) | CC0-1.0 | Regraded grey-brown, 1K. |
| `library/silas_cutlass_saber/silas_cutlass_saber.glb` | `7fca54a03abdf03e7c37af27b140c45510791286fc9cf4869cdbde41bbad7bad` | Poly Haven [wooden_handle_saber](https://polyhaven.com/a/wooden_handle_saber) | CC0-1.0 | 1K. |
| `library/snapped_mast/snapped_mast.glb` | `dcf0e4d78d442c2bb77f5053b5c6ac1520acb75ea6d6ae7b2fa9aa28b5cafc2e` | First-party Blender procedural, dutch_ship_large_02 and Poly Haven hessian_230 textures | CC0-1.0 textures; mesh first-party | 1K. |
| `library/tidepuck_hy3d/tidepuck_hy3d.glb` | `bedbd0696e842c84480c185870c90ffeb0a471ced1b2aa4d299c72e41f9778ea` | Tencent HY 3D Global (free tier), first-party concept (Tide-Puck with bandaged front-right flipper) | HY3D free tier, commercial terms unconfirmed | 1K. |
| `library/torn_sail/torn_sail.glb` | `1ad0ddd48326d90a5c37139d33345c039fa81261e9ea5fd3c6b554908f4ee168` | First-party Blender procedural, dutch_ship_large_02 sail texture | CC0-1.0 texture; mesh first-party | 1K; toned in scene. |
| `library/treasure_chest/treasure_chest.glb` | `dd39ebe6f7acd703d8476cf76396a384f8ae267cb1b172c1452261c085b8a90b` | Poly Haven [treasure_chest](https://polyhaven.com/a/treasure_chest) | CC0-1.0 | 1K. |
| `library/wine_barrel_01/wine_barrel_01.glb` | `321b72c27acdd6898797914d60a1321b7cbaf6af6b981297c0067f82c3e9def3` | Poly Haven [wine_barrel_01](https://polyhaven.com/a/wine_barrel_01) | CC0-1.0 | 1K. |
| `library/wooden_barrels_01/wooden_barrels_01.glb` | `1fe2331c6e2a8da5a9f6a831dfbe8e0ab7f7230f07e02d70fc600280c7cd6eaa` | Poly Haven [wooden_barrels_01](https://polyhaven.com/a/wooden_barrels_01) | CC0-1.0 | 1K. |
| `library/wooden_crate_01/wooden_crate_01.glb` | `44c74626a49448be71e7c739eaa27b42e1582e0f91a23657fb8473df4b6683f5` | Poly Haven [wooden_crate_01](https://polyhaven.com/a/wooden_crate_01) | CC0-1.0 | 1K. |
| `library/wooden_crate_02/wooden_crate_02.glb` | `08f4832617df6a97d70cf45273318726a40a3c4692d819b221e25f899ea82748` | Poly Haven [wooden_crate_02](https://polyhaven.com/a/wooden_crate_02) | CC0-1.0 | 1K. |

**Hunyuan3D (HY 3D) assets:** `*_hy3d.glb` were generated with Tencent HY 3D Global on its free tier from first-party concept images. The free tier's commercial-use terms are **not yet confirmed**. Treat these as placeholders until the terms are confirmed or the meshes are replaced.
