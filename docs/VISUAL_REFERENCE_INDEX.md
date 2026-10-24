# Approved visual reference image index

The three user-supplied images are **visual benchmarks only**. Their source/redistribution license is not established; do not extract assets, redistribute them as game resources, or treat them as screenshots of the current Godot build. They belong in repository documentation rather than `client-godot/assets/external/`.

Expected paths and SHA-256 of the original user-supplied JPEG bytes:

| Reference | Repository path | SHA-256 |
| --- | --- | --- |
| Tropical fantasy island | `docs/visual-references/01-tropical-fantasy-island.jpg` | `c44e984e7378e7c2e3c9e28f92733b505261782d307940be2aac513d16ffa8ed` |
| Pirate ship and coastal water | `docs/visual-references/02-pirate-ship-coastal-water.jpg` | `94cc24dc85d3e54977360184e59f29a433a869a1c23026261a01f0779b4868a7` |
| Lush island cliffs | `docs/visual-references/03-lush-island-cliffs.jpg` | `e7e91d6a6c77e5480216624f6dc7f4c15e610daf7229ea4c43274cb26624e0ff` |

**Upload status:** The three binary files are not yet committed to this branch. Upload the originals at these paths, then run `sha256sum docs/visual-references/*.jpg` and compare against this index. Never claim repository image upload complete until GitHub reports the binary paths at an exact commit SHA.

The mandatory [art direction standard](ART_DIRECTION_STANDARD.md) applies to all actual Godot renders, while the images in this index communicate the desired visual direction.
