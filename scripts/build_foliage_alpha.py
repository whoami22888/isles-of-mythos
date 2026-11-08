#!/usr/bin/env python3
"""Derive the island-tree leaf opacity from the source atlas's black matte."""
from __future__ import annotations

import hashlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "client-godot/assets/external/polyhaven/island_tree_01/textures/island_tree_01_leaves_diff_1k.jpg"
SECOND_SOURCE = ROOT / "client-godot/assets/external/polyhaven/island_tree_02/textures/island_tree_02_leaves_diff_1k.jpg"
OUTPUT = ROOT / "client-godot/assets/external/generated/foliage/island_tree_leaves_rgba_1k.png"
SOURCE_SHA256 = "f56d762a1507754752abf164cc12acbc1e87ce87fa609ac44b98a1b0037c89d8"


def main() -> None:
    if any(hashlib.sha256(path.read_bytes()).hexdigest() != SOURCE_SHA256
           for path in (SOURCE, SECOND_SOURCE)):
        raise ValueError("Source leaf atlas changed; inspect matte before regenerating alpha")
    image = Image.open(SOURCE).convert("RGB")
    if image.size != (1024, 1024):
        raise ValueError("Unexpected source leaf atlas size")
    output = Image.new("RGBA", image.size)
    pixels = []
    for red, green, blue in image.get_flattened_data():
        # The licensed atlas has an actual black matte. Values 0-4 are the
        # matte/JPEG fringe; leaf interiors are far brighter. Retain the
        # original colour and feather only this narrow authored edge.
        strength = max(red, green, blue)
        alpha = min(255, max(0, (strength - 4) * 255 // 20))
        pixels.append((red, green, blue, alpha))
    output.putdata(pixels)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    output.save(OUTPUT, optimize=False)
    print(f"{OUTPUT.relative_to(ROOT)} {hashlib.sha256(OUTPUT.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
