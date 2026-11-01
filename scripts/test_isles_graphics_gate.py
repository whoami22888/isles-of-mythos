"""Regressions for source-observable graphics failures, not visual acceptance."""
import json
import struct
import contextlib
import io
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
        sys.argv = ['isles_graphics_gate.py', '--client', str(self.root)]
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = gate.main()
        self.assertEqual(1, result)

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
        sys.argv = ['isles_graphics_gate.py', '--client', str(self.root)]
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = gate.main()
        self.assertEqual(0, result)
        self.assertIn('::warning::FLAT_FOAM', output.getvalue())
        self.assertIn('does NOT certify', output.getvalue())

    def test_runtime_material_and_geometry_are_checked_instead_of_source_model(self):
        self.glb('tree.glb', {'asset': {'version': '2.0'}, 'materials': [
            {'name': 'Leaves', 'alphaMode': 'MASK', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}}}],
            'textures': [{'source': 0}], 'images': [{'mimeType': 'image/jpeg'}]})
        self.scene('assets/tree.glb')
        report = {'res://scenes/ship_view.tscn': [{
            'node': 'Tree/Leaves', 'surfaces': [{'triangles': 12000, 'material': 'Leaves',
            'transparency': 4, 'albedo_alpha': True, 'texture': 'res://assets/packed/leaves.png'}]}]}
        findings, _ = gate.audit(self.root, report)
        self.assertNotIn('FOLIAGE_ALPHA', {item.code for item in findings})
        report['res://scenes/ship_view.tscn'][0]['surfaces'][0]['albedo_alpha'] = False
        report['res://scenes/ship_view.tscn'][0]['surfaces'][0]['triangles'] = 400000
        codes = {item.code for item in gate.audit(self.root, report)[0]}
        self.assertIn('FOLIAGE_ALPHA', codes)
        self.assertIn('HEAVY_LOD0', codes)

    def test_distant_tree_budget_uses_instantiated_mesh(self):
        mesh = {'node': 'VerifiedTropicalContentLayer/Tree/island_tree_01_LOD2',
                'surfaces': [{'triangles': 14000, 'material': 'Bark',
                              'transparency': 0, 'albedo_alpha': False, 'texture': ''}]}
        self.assertEqual([], gate.inspect_scene_nodes_runtime('res://scenes/coastal.tscn', [mesh]))
        mesh['surfaces'][0]['triangles'] = 15000
        self.assertIn('HEAVY_LOD0', {f.code for f in
                      gate.inspect_scene_nodes_runtime('res://scenes/coastal.tscn', [mesh])})

    def test_runtime_report_schema_rejects_malformed_surfaces(self):
        surface = {'triangles': 14000, 'material': 'Leaves',
                   'transparency': 4, 'albedo_alpha': True, 'texture': 'leaves.png'}
        report = {
            '__ship_motion_verified__': True,
            'res://scenes/realistic_coastal_slice.tscn': [
                {'node': 'Tree', 'surfaces': [surface]}],
            'res://scenes/realistic_coastal_fx_slice.tscn': [
                {'node': 'Ship', 'surfaces': [surface]}],
        }
        self.assertIs(report, gate._validate_runtime_report(report))
        bad_values = [
            ('triangles', True), ('triangles', float('nan')),
            ('triangles', float('inf')), ('transparency', True),
            ('albedo_alpha', 1), ('texture', None),
        ]
        for field, bad_value in bad_values:
            with self.subTest(field=field):
                original = surface[field]
                surface[field] = bad_value
                with self.assertRaisesRegex(ValueError, 'Invalid runtime surface'):
                    gate._validate_runtime_report(report)
                surface[field] = original

    def test_base_ship_is_only_covered_by_verified_fx_motion(self):
        (self.root / 'scripts').mkdir()
        (self.root / 'scripts/coast.gd').write_text('const SHIP_SCENE = 1\n')
        (self.root / 'scenes/realistic_coastal_slice.tscn').write_text(
            '[ext_resource type="Script" path="res://scripts/coast.gd" id="1"]')
        report = {'__ship_motion_verified__': False,
                  'res://scenes/realistic_coastal_slice.tscn': []}
        self.assertIn('STATIC_SHIP', {f.code for f in gate.audit(self.root, report)[0]})
        report['__ship_motion_verified__'] = True
        self.assertNotIn('STATIC_SHIP', {f.code for f in gate.audit(self.root, report)[0]})

    def test_heightfield_water_is_not_misclassified_as_uv_only_depth(self):
        (self.root / 'scripts').mkdir()
        (self.root / 'scripts/water.gd').write_text(
            'var shallow = true\nvar deep = true\nvar uv = "UV.y"\nvar height = "shore_terrain_height"')
        (self.root / 'scenes/ship_view.tscn').write_text(
            '[ext_resource type="Script" path="res://scripts/water.gd" id="1"]')
        self.assertNotIn('FAKE_WATER_DEPTH', self.codes())

if __name__ == '__main__':
    unittest.main()
