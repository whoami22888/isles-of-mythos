"""CPU reference checks for Prompt 005 triplanar normal orientation.

These tests do not compile or render a Godot shader; engine evidence remains mandatory.
"""
import math
import unittest
from pathlib import Path


def normalize(v):
    length = math.sqrt(sum(x * x for x in v))
    return tuple(x / length for x in v)


def blend_normal(geometric, samples, sharpness=4.0):
    n = normalize(geometric)
    raw = [abs(v) ** sharpness for v in n]
    total = sum(raw)
    weights = [v / total for v in raw]
    signs = [1 if v >= 0 else -1 for v in n]
    nx, ny, nz = samples
    tx = (nx[2] * signs[0], nx[0], nx[1])
    ty = (ny[0], ny[2] * signs[1], ny[1])
    tz = (nz[0], nz[1], nz[2] * signs[2])
    flats = ((signs[0], 0, 0), (0, signs[1], 0), (0, 0, signs[2]))
    projections = (tx, ty, tz)
    perturbation = tuple(sum(weights[j] * (projections[j][i] - flats[j][i]) for j in range(3)) for i in range(3))
    return normalize(tuple(n[i] + perturbation[i] for i in range(3)))


class TriplanarNormalReferenceTests(unittest.TestCase):
    def test_flat_normal_map_preserves_six_axis_faces(self):
        flat = (0.0, 0.0, 1.0)
        for axis in range(3):
            for sign in (-1, 1):
                face = tuple(sign if i == axis else 0 for i in range(3))
                actual = blend_normal(face, (flat, flat, flat))
                for a, expected in zip(actual, face):
                    self.assertAlmostEqual(a, expected, places=7)

    def test_flat_normal_map_preserves_oblique_faces(self):
        flat = (0.0, 0.0, 1.0)
        for face in ((1, 1, 1), (-1, 2, -3), (0.1, -0.2, 0.7),
                     (-0.5, -0.5, 0.25)):
            actual = blend_normal(face, (flat, flat, flat))
            for component, expected in zip(actual, normalize(face)):
                self.assertAlmostEqual(component, expected, places=7)

    def test_weighted_blend_remains_normalized(self):
        samples = ((0.2, -0.1, math.sqrt(0.95)),
                   (-0.1, 0.2, math.sqrt(0.95)),
                   (0.1, 0.2, math.sqrt(0.95)))
        for face in ((1, 2, 3), (-1, 2, -3), (0.1, -0.2, 0.7)):
            result = blend_normal(face, samples)
            self.assertAlmostEqual(sum(v * v for v in result), 1.0, places=7)
            self.assertTrue(all(math.isfinite(v) for v in result))


class StylizedPbrShaderContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.source = (root / "shaders" / "cel_stylized_pbr.gdshader").read_text(encoding="utf-8")
        cls.scene = (Path(__file__).resolve().parent / "cel_stylized_pbr_shader_test.tscn").read_text(encoding="utf-8")
        cls.vertex = cls.source.split("void vertex()", 1)[1].split("void fragment()", 1)[0]
        cls.fragment = cls.source.split("void fragment()", 1)[1].split("void light()", 1)[0]
        cls.light = cls.source.split("void light()", 1)[1]

    def test_vertex_and_fragment_rim_paths_use_smoothstep(self):
        self.assertIn("CAMERA_POSITION_WORLD", self.vertex)
        self.assertIn("vertex_rim_factor = smoothstep", self.vertex)
        self.assertIn("vertex_rim_factor", self.light)
        self.assertIn("n_dot_v", self.light)
        self.assertIn("n_dot_l", self.light)
        self.assertGreaterEqual(self.light.count("smoothstep("), 3)

    def test_three_stop_palette_and_light_specular_are_present(self):
        for token in ("toon_shadow_tint", "toon_mid_tint", "toon_highlight_tint"):
            self.assertIn(token, self.light)
        self.assertIn("SPECULAR_AMOUNT", self.light)
        self.assertIn("specular_amount", self.light)

    def test_uv_and_triplanar_texture_fallbacks_are_present(self):
        self.assertIn("use_triplanar", self.fragment)
        self.assertIn("sample_triplanar_normal", self.fragment)
        self.assertIn("texture(normal_texture, UV)", self.fragment)
        self.assertIn("texture(roughness_texture, UV)", self.fragment)
        self.assertIn("base_color.rgb", self.fragment)
        self.assertIn("METALLIC = metallic", self.fragment)
        self.assertIn("ROUGHNESS = roughness", self.fragment)

    def test_opaque_material_does_not_force_transparent_pipeline(self):
        self.assertNotIn("ALPHA =", self.fragment)

    def test_godot_test_scene_attaches_shader_to_mesh_instance(self):
        self.assertIn('type="MeshInstance3D"', self.scene)
        self.assertIn("cel_stylized_pbr.gdshader", self.scene)
        self.assertIn("material_override = SubResource", self.scene)


if __name__ == "__main__":
    unittest.main()
