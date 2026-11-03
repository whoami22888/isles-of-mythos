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
