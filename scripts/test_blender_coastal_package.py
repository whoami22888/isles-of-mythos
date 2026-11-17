"""Static regression checks for the Blender-authored coastal cliff package."""

from __future__ import annotations

import hashlib
import json
import re
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "client-godot/assets/external/generated/coastal_cliff_blender"
BLEND_SOURCE = ROOT / "graphics/blender/coastal_cliff_authoring.blend"
MANIFEST = ROOT / "client-godot/assets/external-assets.json"


def glb_json(path: Path) -> dict:
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise AssertionError(f"invalid GLB container: {path}")
    offset = 12
    while offset < length:
        size, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + size]
        if chunk_type == 0x4E4F534A:
            return json.loads(chunk)
        offset += 8 + size
    raise AssertionError(f"GLB has no JSON chunk: {path}")


class BlenderCoastalPackageTests(unittest.TestCase):
    def test_manifest_hashes_and_metadata(self) -> None:
        manifest = {item["path"]: item for item in json.loads(MANIFEST.read_text())["assets"]}
        metadata_path = PACKAGE / "BLENDER_BUILD_METADATA.json"
        metadata = json.loads(metadata_path.read_text())
        self.assertEqual(metadata["license"], "CC0-1.0")
        self.assertEqual(metadata["godot_validation"], "PENDING_GODOT_4.7.2_MOBILE")
        self.assertEqual(metadata["geometry"]["lod0_source_triangles"], 461824)
        self.assertTrue(BLEND_SOURCE.is_file())
        self.assertEqual(metadata["outputs"]["blend"], hashlib.sha256(BLEND_SOURCE.read_bytes()).hexdigest())
        for path in PACKAGE.iterdir():
            # Godot extracts these embedded GLB textures and creates sidecars
            # during import. They are cache outputs, not vendored source files.
            if path.suffix in {".import", ".uid"} or re.fullmatch(
                r"coastal_cliff_lod[12]_coastal_cliff_01_(?:arm|diff|nor_gl)_1k\.jpg", path.name
            ):
                continue
            rel = path.relative_to(ROOT / "client-godot/assets/external").as_posix()
            if rel not in manifest:
                self.fail(f"generated package file missing from provenance manifest: {rel}")
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            self.assertEqual(manifest[rel]["sha256"], digest, rel)

    def test_lods_keep_pbr_materials_and_bounded_geometry(self) -> None:
        for name, max_triangles, min_images in (
            ("coastal_cliff_lod1.glb", 150000, 3),
            ("coastal_cliff_lod2.glb", 60000, 3),
        ):
            document = glb_json(PACKAGE / name)
            self.assertGreaterEqual(len(document.get("images", [])), min_images, name)
            self.assertGreaterEqual(len(document.get("textures", [])), min_images, name)
            materials = document.get("materials", [])
            self.assertTrue(materials, name)
            pbr = materials[0].get("pbrMetallicRoughness", {})
            self.assertIn("baseColorTexture", pbr, name)
            self.assertIn("metallicRoughnessTexture", pbr, name)
            triangles = 0
            for mesh in document.get("meshes", []):
                for primitive in mesh.get("primitives", []):
                    accessor = document["accessors"][primitive["indices"]]
                    triangles += accessor["count"] // 3
            self.assertGreater(triangles, 0, name)
            self.assertLessEqual(triangles, max_triangles, name)


if __name__ == "__main__":
    unittest.main()
