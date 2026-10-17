#!/usr/bin/env python3
import base64
import json
import struct
import sys
import unittest
import zlib
from pathlib import Path
from typing import List, Tuple

sys.path.insert(0, str(Path(__file__).parent))
from validate_visual_assets import VisualAssetError, validate_gltf  # noqa: E402  # pylint: disable=wrong-import-position


def png(width: int, height: int, colours: List[Tuple[int, int, int]]) -> bytes:
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            row.extend(colours[(x + y * width) % len(colours)])
        rows.append(bytes(row))

    def chunk(kind: bytes, payload: bytes) -> bytes:
        checksum = zlib.crc32(kind + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(b"".join(rows)))
        + chunk(b"IEND", b"")
    )


def gltf(texture: bytes, with_pbr: bool = True) -> dict:
    uri = "data:image/png;base64," + base64.b64encode(texture).decode("ascii")
    material = {"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}
    if with_pbr:
        material.update({"normalTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 0}})
    return {
        "images": [{"uri": uri}],
        "textures": [{"source": 0}],
        "materials": [material],
        "meshes": [{"primitives": [{"attributes": {"TEXCOORD_0": 0}, "material": 0}]}],
    }


class VisualAssetValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(__file__).parent / ".visual-fixtures"
        self.root.mkdir(exist_ok=True)

    def tearDown(self) -> None:
        for path in self.root.glob("*.gltf"):
            path.unlink()
        self.root.rmdir()

    def write(self, name: str, document: dict) -> Path:
        path = self.root / name
        path.write_text(json.dumps(document), encoding="utf-8")
        return path

    def test_palette_texture_is_rejected_even_when_large(self) -> None:
        path = self.write("palette.gltf", gltf(png(128, 128, [(10, 20, 30), (200, 210, 220)])))
        with self.assertRaisesRegex(VisualAssetError, "palette/swatch-only"):
            validate_gltf(path)

    def test_textured_pbr_asset_passes(self) -> None:
        colours = [(x * 17 % 256, y * 19 % 256, (x * 11 + y * 7) % 256) for y in range(16) for x in range(16)]
        validate_gltf(self.write("textured.gltf", gltf(png(128, 128, colours))))

    def test_missing_normal_map_is_rejected(self) -> None:
        colours = [(x * 17 % 256, y * 19 % 256, (x * 11 + y * 7) % 256) for y in range(16) for x in range(16)]
        path = self.write(
            "no-normal.gltf", gltf(png(128, 128, colours), False)
        )
        with self.assertRaisesRegex(VisualAssetError, "normalTexture"):
            validate_gltf(path)


if __name__ == "__main__":
    unittest.main()
