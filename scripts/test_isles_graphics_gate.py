"""Regressions for source-observable graphics failures, not visual acceptance."""
import json
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import isles_graphics_gate as gate

class GraphicsGateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'project.godot').write_text('[application]\n')
        (self.root / 'scenes').mkdir()
        (self.root / 'assets').mkdir()

    def scene(self, resource):
        (self.root / 'scenes/ship_view.tscn').write_text(
            '[gd_scene format=3]\n[ext_resource type="PackedScene" '
            f'path="res://{resource}" id="1"]\n[node name="Ship" type="Node3D"]\n')

    def codes(self):
        return {x.code for x in gate.audit(self.root)[0]}

    def glb(self, name, doc):
        payload = json.dumps(doc).encode()
        payload += b' ' * (-len(payload) % 4)
        blob = struct.pack('<III', 0x46546C67, 2, 20 + len(payload))
        blob += struct.pack('<II', len(payload), 0x4E4F534A) + payload
        (self.root / 'assets' / name).write_bytes(blob)

    def test_no_candidate_is_blocker(self):
        self.assertIn('NO_CANDIDATE', self.codes())
        result = subprocess.run([sys.executable, gate.__file__, '--client', str(self.root)], capture_output=True)
        self.assertEqual(1, result.returncode)

    def test_missing_glb_is_not_silently_accepted(self):
        self.scene('assets/missing.glb')
        self.assertIn('MISSING_MODEL', self.codes())

    def test_valid_glb_container_can_be_inspected(self):
        self.glb('ship.glb', {'asset': {'version': '2.0'}, 'meshes': []})
        self.scene('assets/ship.glb')
        self.assertEqual(set(), self.codes())

    def test_glb_foliage_jpeg_alpha_finding(self):
        self.glb('leaves.glb', {'asset': {'version': '2.0'}, 'materials': [
            {'name': 'Leaves', 'alphaMode': 'MASK', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}}}],
            'textures': [{'source': 0}], 'images': [{'mimeType': 'image/jpeg'}]})
        self.scene('assets/leaves.glb')
        self.assertIn('FOLIAGE_ALPHA', self.codes())

    def test_truncated_glb_is_blocker(self):
        (self.root / 'assets/broken.glb').write_bytes(b'glTF')
        self.scene('assets/broken.glb')
        self.assertIn('INVALID_MODEL', self.codes())

    def test_path_traversal_is_blocker(self):
        self.scene('assets/../../outside.gltf')
        self.assertIn('UNSAFE_RESOURCE', self.codes())

    def test_json_array_model_is_controlled_error(self):
        (self.root / 'assets/bad.gltf').write_text('[]')
        self.scene('assets/bad.gltf')
        self.assertIn('INVALID_MODEL', self.codes())

    def test_missing_attached_script_is_blocker(self):
        (self.root / 'scenes/ship_view.tscn').write_text(
            '[gd_scene format=3]\n[ext_resource type="Script" path="res://scripts/missing.gd" id="1"]\n')
        self.assertIn('MISSING_SCRIPT', self.codes())

    def test_malformed_nested_model_is_controlled(self):
        documents = [
            {'materials': [{'name': None}]},
            {'materials': [{'pbrMetallicRoughness': None}]},
            {'meshes': [{'primitives': None}]},
            {'images': [{'uri': None}]},
            {'accessors': [{'count': float('inf')}]},
            {'materials': [{'pbrMetallicRoughness': {'baseColorTexture': {'index': -1}}}]},
        ]
        self.scene('assets/bad.gltf')
        for doc in documents:
            with self.subTest(doc=doc):
                (self.root / 'assets/bad.gltf').write_text(json.dumps(doc))
                self.assertIn('INVALID_MODEL', self.codes())

    def test_nested_scene_dependencies_are_inspected(self):
        (self.root / 'scenes/nested').mkdir()
        (self.root / 'scenes/nested/ship.tscn').write_text(
            '[ext_resource type="PackedScene" path="res://assets/missing.glb" id="1"]')
        (self.root / 'scenes/wrapper.tscn').write_text(
            '[ext_resource type="PackedScene" path="res://scenes/nested/ship.tscn" id="1"]')
        self.assertIn('MISSING_MODEL', self.codes())

    def test_model_path_with_spaces_is_inspected(self):
        self.scene('assets/missing ship.glb')
        self.assertIn('MISSING_MODEL', self.codes())

    def test_scene_symlink_escape_is_blocker(self):
        with tempfile.TemporaryDirectory() as other:
            external = Path(other) / 'outside.tscn'
            external.write_text('[gd_scene format=3]')
            (self.root / 'scenes/escape.tscn').symlink_to(external)
            self.assertIn('UNSAFE_RESOURCE', self.codes())

    def test_visual_regex_is_advisory(self):
        (self.root / 'scripts').mkdir()
        (self.root / 'scripts/ship.gd').write_text('var foam = QuadMesh.new() # animated elsewhere')
        (self.root / 'scenes/ship_view.tscn').write_text(
            '[ext_resource type="Script" path="res://scripts/ship.gd" id="1"]')
        findings, _ = gate.audit(self.root)
        foam = [f for f in findings if f.code == 'FLAT_FOAM']
        self.assertEqual(1, len(foam))
        self.assertEqual('review', foam[0].severity)

    def test_dependency_graph_reaches_material_outside_scene_discovery(self):
        (self.root / 'scripts').mkdir()
        (self.root / 'materials').mkdir()
        (self.root / 'scenes/ship_view.tscn').write_text(
            '[ext_resource type="Script" path="res://scripts/ship.gd" id="1"]')
        (self.root / 'scripts/ship.gd').write_text('var art = preload("res://materials/ship.tres")')
        (self.root / 'materials/ship.tres').write_text(
            '[ext_resource type="PackedScene" path="res://assets/missing.glb" id="1"]')
        self.assertIn('MISSING_MODEL', self.codes())

    def test_triangle_hint_aggregates_indexed_nonindexed_strip_and_fan(self):
        primitives = [
            [{'indices': 0}, {'attributes': {'POSITION': 0}}],
            [{'indices': 1, 'mode': 5}],
            [{'attributes': {'POSITION': 1}, 'mode': 6}],
        ]
        self.scene('assets/ship.gltf')
        for value in primitives:
            with self.subTest(primitives=value):
                doc = {'accessors': [{'count': 600000}, {'count': 400000}],
                       'meshes': [{'name': 'Ship', 'primitives': value}]}
                (self.root / 'assets/ship.gltf').write_text(json.dumps(doc))
                self.assertIn('HEAVY_LOD0', self.codes())
        (self.root / 'assets/ship.gltf').write_text(json.dumps({
            'accessors': [{'count': 9999999}],
            'meshes': [{'primitives': [{'indices': 0, 'mode': 1}]}]}))
        self.assertNotIn('HEAVY_LOD0', self.codes())

    def test_review_only_cli_succeeds_without_claiming_visual_acceptance(self):
        (self.root / 'scripts').mkdir()
        (self.root / 'scripts/ship.gd').write_text('var foam = QuadMesh.new()')
        (self.root / 'scenes/ship_view.tscn').write_text(
            '[ext_resource type="Script" path="res://scripts/ship.gd" id="1"]')
        result = subprocess.run([sys.executable, gate.__file__, '--client', str(self.root)], capture_output=True, text=True)
        self.assertEqual(0, result.returncode)
        self.assertIn('::warning::FLAT_FOAM', result.stdout)
        self.assertIn('does NOT certify', result.stdout)

if __name__ == '__main__':
    unittest.main()
