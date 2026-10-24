# Premium tropical island asset candidates — screening queue

These are **not imported or accepted**. Compare each asset against the user-supplied three-image benchmark and [mandatory premium standard](ART_DIRECTION_STANDARD.md). All sources below currently advertise CC0 on their official Poly Haven asset pages; validate the exact downloaded bytes, included dependencies and current license terms before manifest admission.

| Priority | Candidate / official source | Use | Initial assessment | Pending gates |
| --- | --- | --- | --- | --- |
| 1 | [Coast Sand Rocks 02](https://polyhaven.com/a/coast_sand_rocks_02) | Shoreline blend PBR texture | Detailed mossy, weathered rock/sandy soil; potential fit with fantasy coast | Choose mobile texture tier, obtain verified bytes/hash, Godot render/visual review |
| 2 | [Aerial Beach 01](https://polyhaven.com/a/aerial_beach_01) | Dry sandy shoreline PBR | Sculpted ripples suitable for beach material | Verified map dependencies/hash, compare scale/colour and real Godot screenshots |
| 3 | [Seaside Rock](https://polyhaven.com/a/seaside_rock) | Cliff/shoreline PBR | Weathered, naturally eroded coastal rock | Hash, material integration, visual compatibility, Android texture budget |
| 4 | [Coast Rocks 03](https://polyhaven.com/a/coast_rocks_03) | Shoreline scanned rock geometry | High detail; official listing describes LODs | Raw listing indicates ~2 million triangles; require LOD selection/mesh profiling, actual near-field visual evaluation |
| 5 | [Coast Rocks 05](https://polyhaven.com/a/coast_rocks_05) | Rock/reef prop | High detail coastal geometry | Model format, verified full dependencies, measured LOD and memory/visual quality |

**Harvest decision:** shortlisting only. Do not add to `external-assets.json` until downloads can be inspected, SHA-256 pinned, author/license/redistribution checked and mandatory gates satisfied. For photogrammetry assets with million-triangle source meshes, do not import high-resolution source meshes directly as unbounded Android runtime meshes. Preserve high-quality near-field materials and generate measured LODs. Vegetation and water require a separate source/technical review; these sources do not by themselves establish a complete island scene.

**Evidence outstanding:** Godot-rendered screenshots, Android FPS/frame-time/memory/thermal, independent visual review, final asset hashes and import success.
