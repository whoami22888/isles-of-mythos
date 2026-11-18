"""CPU reference checks for Prompt 005 triplanar normal orientation.

These tests do not compile or render a Godot shader; engine evidence remains mandatory.
"""
import math
import unittest
from pathlib import Path


def read_utf8(path):
    """Read a UTF-8 source file without relying on newer pathlib convenience APIs."""
    with open(str(path), "r", encoding="utf-8") as source_file:
        return source_file.read()


def normalize(vector):
    """Return a unit-length tuple in the same direction as vector."""
    length = math.sqrt(
        sum(component * component for component in vector)
    )
    return tuple(component / length for component in vector)


def blend_normal(geometric_normal, samples, sharpness=4.0):
    """Blend reoriented triplanar normal samples around the geometric normal."""
    normal = normalize(geometric_normal)
    raw_weights = [abs(component) ** sharpness for component in normal]
    total_weight = sum(raw_weights)
    weights = [weight / total_weight for weight in raw_weights]
    signs = [1 if component >= 0 else -1 for component in normal]
    sample_x, sample_y, sample_z = samples

    tangent_x = (sample_x[2] * signs[0], sample_x[0], sample_x[1])
    tangent_y = (sample_y[0], sample_y[2] * signs[1], sample_y[1])
    tangent_z = (sample_z[0], sample_z[1], sample_z[2] * signs[2])
    flat_x = (signs[0], 0, 0)
    flat_y = (0, signs[1], 0)
    flat_z = (0, 0, signs[2])
    projections = (tangent_x, tangent_y, tangent_z)
    flat_normals = (flat_x, flat_y, flat_z)

    perturbation = tuple(
        sum(
            weights[projection_index]
            * (
                projections[projection_index][component_index]
                - flat_normals[projection_index][component_index]
            )
            for projection_index in range(3)
        )
        for component_index in range(3)
    )
    blended = tuple(
        normal[index] + perturbation[index]
        for index in range(3)
    )
    return normalize(blended)


class TriplanarNormalReferenceTests(unittest.TestCase):
    """Verify the CPU reference normal reconstruction on representative faces."""

    def test_flat_normal_map_preserves_six_axis_faces(self):
        """A flat tangent normal must preserve every signed cardinal face."""
        flat_normal = (0.0, 0.0, 1.0)
        for axis_index in range(3):
            for face_sign in (-1, 1):
                face = tuple(
                    face_sign if component_index == axis_index else 0
                    for component_index in range(3)
                )
                actual = blend_normal(
                    face, (flat_normal, flat_normal, flat_normal)
                )
                for actual_component, expected_component in zip(actual, face):
                    self.assertAlmostEqual(
                        actual_component, expected_component, places=7
                    )

    def test_flat_normal_map_preserves_oblique_faces(self):
        """A flat tangent normal must not tilt oblique geometric faces."""
        flat_normal = (0.0, 0.0, 1.0)
        faces = (
            (1, 1, 1),
            (-1, 2, -3),
            (0.1, -0.2, 0.7),
            (-0.5, -0.5, 0.25),
        )
        for face in faces:
            actual = blend_normal(
                face, (flat_normal, flat_normal, flat_normal)
            )
            expected = normalize(face)
            for actual_component, expected_component in zip(actual, expected):
                self.assertAlmostEqual(
                    actual_component, expected_component, places=7
                )

    def test_weighted_blend_remains_normalized(self):
        """Perturbed triplanar blends remain finite and unit length."""
        sample_x = (0.2, -0.1, math.sqrt(0.95))
        sample_y = (-0.1, 0.2, math.sqrt(0.95))
        sample_z = (0.1, 0.2, math.sqrt(0.95))
        samples = (sample_x, sample_y, sample_z)
        faces = ((1, 2, 3), (-1, 2, -3), (0.1, -0.2, 0.7))
        for face in faces:
            result = blend_normal(face, samples)
            squared_length = sum(
                component * component for component in result
            )
            self.assertAlmostEqual(squared_length, 1.0, places=7)
            self.assertTrue(
                all(math.isfinite(component) for component in result)
            )


class StylizedPbrShaderContractTests(unittest.TestCase):
    """Guard the optional shader and its headless test-scene contract."""

    @classmethod
    def setUpClass(cls):
        """Load shader and scene text for source-level contract assertions."""
        project_root = Path(__file__).resolve().parents[1]
        test_directory = Path(__file__).resolve().parent
        cls.source = read_utf8(
            project_root / "shaders" / "cel_stylized_pbr.gdshader"
        )
        cls.scene = read_utf8(
            test_directory / "cel_stylized_pbr_shader_test.tscn"
        )
        cls.vertex = cls.source.split("void vertex()", 1)[1].split(
            "void fragment()", 1
        )[0]
        cls.fragment = cls.source.split("void fragment()", 1)[1].split(
            "void light()", 1
        )[0]
        cls.light = cls.source.split("void light()", 1)[1]

    def test_vertex_and_fragment_rim_paths_use_smoothstep(self):
        """Both vertex and fragment paths retain smooth rim transitions."""
        self.assertIn("CAMERA_POSITION_WORLD", self.vertex)
        self.assertIn("vertex_rim_factor = smoothstep", self.vertex)
        self.assertIn("vertex_rim_factor", self.light)
        self.assertIn("n_dot_v", self.light)
        self.assertIn("n_dot_l", self.light)
        self.assertGreaterEqual(self.light.count("smoothstep("), 3)

    def test_three_stop_palette_and_light_specular_are_present(self):
        """The light function keeps three palette stops and specular response."""
        for token in (
            "toon_shadow_tint",
            "toon_mid_tint",
            "toon_highlight_tint",
        ):
            self.assertIn(token, self.light)
        self.assertIn("SPECULAR_AMOUNT", self.light)
        self.assertIn("specular_amount", self.light)

    def test_uv_and_triplanar_texture_fallbacks_are_present(self):
        """UV and triplanar maps retain scalar material fallbacks."""
        self.assertIn("use_triplanar", self.fragment)
        self.assertIn("sample_triplanar_normal", self.fragment)
        self.assertIn("texture(normal_texture, UV)", self.fragment)
        self.assertIn("texture(roughness_texture, UV)", self.fragment)
        self.assertIn("base_color.rgb", self.fragment)
        self.assertIn("METALLIC = metallic", self.fragment)
        self.assertIn("ROUGHNESS = roughness", self.fragment)

    def test_mobile_force_vertex_shading_has_builtin_toon_fallback(self):
        """Mobile's built-in lighting path keeps toon diffuse, specular and rim."""
        shader_header = self.source.split("void vertex()", 1)[0]
        self.assertIn("diffuse_toon", shader_header)
        self.assertIn("specular_toon", shader_header)
        self.assertIn("SPECULAR = specular_amount", self.fragment)
        self.assertIn("RIM = clamp(vertex_rim_factor", self.fragment)

    def test_opaque_material_does_not_force_transparent_pipeline(self):
        """Opaque material output must not assign ALPHA."""
        self.assertNotIn("ALPHA =", self.fragment)

    def test_godot_test_scene_attaches_shader_to_mesh_instance(self):
        """The smoke scene binds the shader to a real MeshInstance3D node."""
        self.assertIn('type="MeshInstance3D"', self.scene)
        self.assertIn("cel_stylized_pbr.gdshader", self.scene)
        self.assertIn("material_override = SubResource", self.scene)


if __name__ == "__main__":
    unittest.main()
