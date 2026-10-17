#!/usr/bin/env python3
"""Regression tests for structural fail-closed premium scene audit."""
import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from audit_premium_graphics import audit, main


class PremiumVisualAuditTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "scenes").mkdir()
        (self.root / "scripts").mkdir()
        (self.root / "project.godot").write_text('run/main_scene="res://scenes/boot.tscn"\n')
        (self.root / "scenes/boot.tscn").write_text('[node name="Boot" type="Control"]\n')

    def tearDown(self):
        self.tmp.cleanup()

    def add_scene(self, name, script):
        (self.root / "scenes" / name).write_text('[ext_resource path="res://scripts/scene.gd" type="Script" id="1"]\n')
        (self.root / "scripts/scene.gd").write_text(script)

    def codes(self):
        return {finding.code for finding in audit(self.root)[0]}

    def test_empty_project_is_not_certified_but_has_no_false_error(self):
        errors, scenes = audit(self.root)
        self.assertEqual((errors, scenes), ([], 0))

    def test_rejects_prototype_as_main_scene(self):
        (self.root / "project.godot").write_text('run/main_scene="res://scenes/island_preview.tscn"\n')
        self.assertIn("PROTOTYPE_LAUNCH", self.codes())

    def test_detects_flat_terrain_water_foam_and_static_ship(self):
        script = '''
func _terrain_material() -> StandardMaterial3D:
    var material = StandardMaterial3D.new()
    material.albedo_color = Color("#c9a77b")
    return material
func build():
    var water = PlaneMesh.new()
    var foam = QuadMesh.new()
    var code = "ShallowToDeepWater shallow deep UV.y"
    var ship = SHIP_SCENE.instantiate()
    ship.position = Vector3.ZERO
'''
        self.add_scene("realistic_coastal_slice.tscn", script)
        self.assertTrue({"FLAT_TERRAIN", "FLAT_FOAM", "FAKE_WATER_DEPTH", "STATIC_WATER", "STATIC_SHIP"}.issubset(self.codes()))

    def test_pbr_animated_scene_no_flat_flags(self):
        script = '''
func _terrain_material() -> StandardMaterial3D:
    var material = StandardMaterial3D.new()
    material.albedo_texture = load("res://assets/sand.png")
    material.normal_texture = load("res://assets/normal.png")
    material.roughness_texture = load("res://assets/rough.png")
    return material
func _build_water():
    var shader = "ShallowToDeepWater shallow deep hint_depth_texture TIME void vertex()"
'''
        self.add_scene("realistic_coastal_slice.tscn", script)
        self.assertFalse(self.codes() & {"FLAT_TERRAIN", "FLAT_FOAM", "FAKE_WATER_DEPTH", "STATIC_WATER"})

    def test_rejects_leaf_jpeg_alpha_and_excessive_detail(self):
        self.add_scene("premium_island.tscn", 'const TREE_SCENE = preload("res://assets/tree.gltf")\n')
        (self.root / "assets").mkdir()
        doc = {"images": [{"uri": "leaves.jpg", "mimeType": "image/jpeg"}],
               "textures": [{"source": 0}],
               "materials": [{"name": "tree_leaves", "alphaMode": "BLEND", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
               "accessors": [{"count": 1500000}],
               "meshes": [{"name": "tree_LOD0", "primitives": [{"indices": 0}]}]}
        (self.root / "assets/tree.gltf").write_text(json.dumps(doc))
        self.assertTrue({"FOLIAGE_ALPHA", "HEAVY_LOD0"}.issubset(self.codes()))

    def test_rejects_sail_mask_with_jpeg_alpha_loss(self):
        self.add_scene("premium_ship.tscn", 'const SHIP_SCENE = preload("res://assets/ship.gltf")\n')
        (self.root / "assets").mkdir()
        doc = {"images": [{"uri": "sail_diffuse.jpg", "mimeType": "image/jpeg"}],
               "textures": [{"source": 0}],
               "materials": [{"name": "ship_sails", "alphaMode": "MASK", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}]}
        (self.root / "assets/ship.gltf").write_text(json.dumps(doc))
        self.assertIn("MASKED_ALPHA_JPEG", self.codes())

    def test_rejects_generic_polyhaven_sources(self):
        self.add_scene("premium_coast.tscn", "# isolated candidate")
        (self.root / "assets").mkdir()
        manifest = {"assets": [{"path": "polyhaven/rock_asset/rock.bin",
                                "source_url": "https://polyhaven.com/a/polyhaven",
                                "download_url": "https://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/polyhaven/rock.bin"}]}
        (self.root / "assets/external-assets.json").write_text(json.dumps(manifest))
        self.assertTrue({"ASSET_SOURCE_MISMATCH", "BAD_ASSET_DOWNLOAD_PATH"}.issubset(self.codes()))

    def test_rejects_binary_above_exact_importer_limit(self):
        (self.root / "assets/external/polyhaven/tree").mkdir(parents=True)
        binary = self.root / "assets/external/polyhaven/tree/model.bin"
        with binary.open("wb") as stream:
            stream.truncate(80 * 1024 * 1024 + 1)
        (self.root / "assets/external-assets.json").write_text(json.dumps({"assets": [{
            "path": "polyhaven/tree/model.bin", "source_url": "https://polyhaven.com/a/tree",
            "download_url": "https://dl.polyhaven.org/file/tree/model.bin"}]}))
        self.assertIn("ASSET_EXCEEDS_FETCH_LIMIT", self.codes())

    def test_strict_release_mode_fails_without_premium_scene(self):
        with patch("sys.argv", ["audit", "--client", str(self.root), "--require-candidate"]):
            self.assertEqual(main(), 1)

    def test_missing_script_is_not_ignored(self):
        (self.root / "scenes/premium_world.tscn").write_text(
            '[ext_resource path="res://scripts/gone.gd" type="Script" id="1"]\n')
        self.assertIn("MISSING_SCENE_SCRIPT", self.codes())

    def test_rejects_spoofed_or_partial_publisher_urls(self):
        self.add_scene("premium_coast.tscn", "# candidate")
        (self.root / "assets").mkdir()
        for url in ("https://evil.example/a/tree", "https://polyhaven.com/a/tree_variant"):
            manifest = {"assets": [{"path": "polyhaven/tree/model.bin",
                                    "source_url": url, "download_url": "https://dl.polyhaven.org/a.bin"}]}
            (self.root / "assets/external-assets.json").write_text(json.dumps(manifest))
            self.assertIn("ASSET_SOURCE_MISMATCH", self.codes())

    def test_payload_limit_applies_to_unprefixed_asset_paths(self):
        (self.root / "assets/external/models").mkdir(parents=True)
        payload = self.root / "assets/external/models/large.bin"
        with payload.open("wb") as handle:
            handle.truncate(80 * 1024 * 1024 + 1)
        (self.root / "assets/external-assets.json").write_text(json.dumps({
            "assets": [{"path": "models/large.bin"}]}))
        self.assertIn("ASSET_EXCEEDS_FETCH_LIMIT", self.codes())

    def test_glass_with_uniform_jpeg_transparency_is_allowed(self):
        self.add_scene("premium_glass.tscn", 'const GLASS = preload("res://assets/glass.gltf")\n')
        (self.root / "assets").mkdir()
        doc = {"images": [{"uri": "glass.jpg", "mimeType": "image/jpeg"}],
               "textures": [{"source": 0}],
               "materials": [{"name": "glass", "alphaMode": "BLEND", "pbrMetallicRoughness": {
                   "baseColorTexture": {"index": 0}, "baseColorFactor": [1, 1, 1, 0.35]}}]}
        (self.root / "assets/glass.gltf").write_text(json.dumps(doc))
        self.assertNotIn("MASKED_ALPHA_JPEG", self.codes())

    def test_triangle_modes_obey_gltf_semantics(self):
        self.add_scene("premium_geometry.tscn", 'const MESH = preload("res://assets/shape.gltf")\n')
        (self.root / "assets").mkdir()
        filename = self.root / "assets/shape.gltf"
        base = {"accessors": [{"count": 400000}], "meshes": [{"name": "complex_LOD0",
                "primitives": [{"indices": 0, "mode": 5}]}]}
        filename.write_text(json.dumps(base))
        self.assertIn("HEAVY_LOD0", self.codes())
        base["meshes"][0]["primitives"][0]["mode"] = 1  # LINES
        filename.write_text(json.dumps(base))
        self.assertNotIn("HEAVY_LOD0", self.codes())

    def test_missing_or_unrelated_capture_does_not_pass(self):
        self.add_scene("realistic_coastal_slice.tscn", "# candidate")
        self.assertIn("MISSING_CAPTURE", self.codes())
        (self.root / "tests").mkdir()
        (self.root / "tests/render_capture.gd").write_text(
            'load("res://scenes/island_preview.tscn")\nvar img = get_image()')
        self.assertIn("MISSING_CAPTURE", self.codes())

    def test_nested_world_scene_is_audited(self):
        nested = self.root / "scenes/world"
        nested.mkdir()
        (nested / "coast.tscn").write_text(
            '[ext_resource path="res://scripts/missing.gd" type="Script" id="1"]\n')
        findings, count = audit(self.root)
        self.assertEqual(count, 1)
        self.assertIn("MISSING_SCENE_SCRIPT", {x.code for x in findings})

    def test_render_capture_with_frame_fence_and_content_assertion(self):
        self.add_scene("premium_scene.tscn", "# candidate")
        (self.root / "tests").mkdir()
        (self.root / "tests/render_premium.gd").write_text(
            'load("res://scenes/premium_scene.tscn")\nawait RenderingServer.frame_post_draw\n'
            'var img = root.get_viewport().get_texture().get_image()\n'
            'img.get_pixel(0, 0)\n')
        self.assertFalse(self.codes() & {"MISSING_CAPTURE", "STALE_CAPTURE", "BLANK_CAPTURE"})

    def test_rejects_bad_screenshot_evidence(self):
        self.add_scene("realistic_coastal_slice.tscn", "# simple scene source")
        (self.root / "tests").mkdir()
        (self.root / "tests/render_capture.gd").write_text('var scene = load("res://scenes/realistic_coastal_slice.tscn")\nawait process_frame\nvar img = viewport.get_texture().get_image()\n')
        self.assertTrue({"STALE_CAPTURE", "BLANK_CAPTURE"}.issubset(self.codes()))

    def test_rejects_prototype_in_final_scene(self):
        self.add_scene("premium_world.tscn", 'var scene = preload("res://scenes/island_preview.tscn")')
        self.assertIn("PROTOTYPE_DEPENDENCY", self.codes())

    def test_exempts_explicit_preview_and_archive(self):
        (self.root / "scenes/island_preview.tscn").write_text('CylinderMesh SphereMesh')
        archive = self.root / "scenes/archive"
        archive.mkdir()
        (archive / "bad.tscn").write_text('CylinderMesh')
        self.assertEqual(audit(self.root), ([], 0))


if __name__ == "__main__":
    unittest.main()
