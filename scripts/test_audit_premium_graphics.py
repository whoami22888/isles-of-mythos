#!/usr/bin/env python3
"""Regression tests for structural fail-closed premium scene audit."""
import json
import tempfile
import unittest
from pathlib import Path

from audit_premium_graphics import audit


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

    def test_rejects_bad_screenshot_evidence(self):
        self.add_scene("realistic_coastal_slice.tscn", "# simple scene source")
        (self.root / "tests").mkdir()
        (self.root / "tests/render_capture.gd").write_text('var scene = load("realistic_coastal_slice.tscn")\nawait process_frame\nvar img = viewport.get_texture().get_image()\n')
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
