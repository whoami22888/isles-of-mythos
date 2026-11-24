"""CPU reference checks for Prompt 005 triplanar normal orientation.

These tests do not compile or render a Godot shader; engine evidence remains mandatory.
"""

# This standalone unittest module does not use Django settings.
# pylint: disable=django-not-configured

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


def triplanar_uvs(position, geometric_normal):
    """Return X/Y/Z projection UVs with the normal-map tangent-frame signs."""
    normal = normalize(geometric_normal)
    face = tuple(1 if component >= 0 else -1 for component in normal)
    return (
        (position[1], position[2] * face[0]),
        (position[0], -position[2] * face[1]),
        (position[0], position[1] * face[2]),
    )


def reorient_projection(sample, face_sign, axis_index):
    """Map a tangent-space sample into its signed local projection frame."""
    if axis_index == 0:
        return (sample[2] * face_sign, sample[0], sample[1] * face_sign)
    if axis_index == 1:
        return (sample[0], sample[2] * face_sign, -sample[1] * face_sign)
    return (sample[0], sample[1] * face_sign, sample[2] * face_sign)


def blend_normal(geometric_normal, samples, sharpness=4.0):
    """Blend reoriented triplanar normal samples around the geometric normal."""
    normal = normalize(geometric_normal)
    raw_weights = [abs(component) ** sharpness for component in normal]
    total_weight = sum(raw_weights)
    weights = [weight / total_weight for weight in raw_weights]
    signs = [1 if component >= 0 else -1 for component in normal]
    projections = [
        reorient_projection(samples[index], signs[index], index)
        for index in range(3)
    ]
    flat_normals = (
        (signs[0], 0, 0),
        (0, signs[1], 0),
        (0, 0, signs[2]),
    )
    perturbation = tuple(
        sum(
            weight * (projection[component_index] - flat[component_index])
            for weight, projection, flat in zip(weights, projections, flat_normals)
        )
        for component_index in range(3)
    )
    blended = tuple(
        component + delta for component, delta in zip(normal, perturbation)
    )
    return normalize(blended)


class TriplanarNormalReferenceTests(unittest.TestCase):
    """Verify the CPU reference normal reconstruction on representative faces."""

    def test_signed_projection_uvs_match_normal_map_bitangents(self):
        """Albedo, roughness and normal maps must use the same signed projection frames."""
        cases = (
            ((1, 0, 0), 0, 1, 2, 1),
            ((-1, 0, 0), 0, 1, 2, -1),
            ((0, 1, 0), 1, 0, 2, -1),
            ((0, -1, 0), 1, 0, 2, 1),
            ((0, 0, 1), 2, 0, 1, 1),
            ((0, 0, -1), 2, 0, 1, -1),
        )
        origin = (0.0, 0.0, 0.0)
        for face, projection, u_axis, v_axis, v_sign in cases:
            base_uv = triplanar_uvs(origin, face)[projection]
            u_position = [0.0, 0.0, 0.0]
            u_position[u_axis] = 1.0
            v_position = [0.0, 0.0, 0.0]
            v_position[v_axis] = 1.0
            u_uv = triplanar_uvs(tuple(u_position), face)[projection]
            v_uv = triplanar_uvs(tuple(v_position), face)[projection]
            self.assertAlmostEqual(u_uv[0] - base_uv[0], 1.0)
            self.assertAlmostEqual(u_uv[1] - base_uv[1], 0.0)
            self.assertAlmostEqual(v_uv[0] - base_uv[0], 0.0)
            self.assertAlmostEqual(v_uv[1] - base_uv[1], v_sign)

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

    def test_signed_projection_bitangents_keep_face_handedness(self):
        """Each signed face keeps the expected orientation for its UV bitangent."""
        flat = (0.0, 0.0, 1.0)
        tangent_y = (0.0, 1.0, 0.0)
        cases = (
            ((1, 0, 0), (tangent_y, flat, flat), (0, 0, 1)),
            ((-1, 0, 0), (tangent_y, flat, flat), (0, 0, -1)),
            ((0, 1, 0), (flat, tangent_y, flat), (0, 0, -1)),
            ((0, -1, 0), (flat, tangent_y, flat), (0, 0, 1)),
            ((0, 0, 1), (flat, flat, tangent_y), (0, 1, 0)),
            ((0, 0, -1), (flat, flat, tangent_y), (0, -1, 0)),
        )
        for face, samples, expected in cases:
            actual = blend_normal(face, samples)
            for actual_component, expected_component in zip(actual, expected):
                self.assertAlmostEqual(actual_component, expected_component, places=7)

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
        shader_directory = project_root / "shaders"
        cls.desktop_source = read_utf8(
            shader_directory / "cel_stylized_pbr.gdshader"
        )
        cls.mobile_source = read_utf8(
            shader_directory / "cel_stylized_pbr_mobile.gdshader"
        )
        cls.shared = read_utf8(
            shader_directory / "cel_stylized_pbr_shared.gdshaderinc"
        )
        cls.scene = read_utf8(
            test_directory / "cel_stylized_pbr_shader_test.tscn"
        )
        cls.test_script = read_utf8(
            test_directory / "cel_stylized_pbr_shader_compile_test.gd"
        )
        cls.vertex = cls.shared.split("void vertex()", 1)[1].split(
            "void fragment()", 1
        )[0]
        cls.fragment = cls.shared.split("void fragment()", 1)[1].split(
            "void light()", 1
        )[0]
        cls.light = cls.shared.split("void light()", 1)[1]

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
        for token in ("toon_shadow_tint", "toon_mid_tint", "toon_highlight_tint"):
            self.assertIn(token, self.light)
        self.assertIn("SPECULAR_AMOUNT", self.light)
        self.assertIn("SPECULAR = specular_amount", self.fragment)

    def test_uv_and_triplanar_texture_fallbacks_are_present(self):
        """UV and triplanar maps retain scalar material fallbacks."""
        self.assertIn("use_triplanar", self.fragment)
        self.assertIn("sample_triplanar_normal", self.fragment)
        self.assertIn("nx.y * face.x", self.shared)
        self.assertIn("-ny.y * face.y", self.shared)
        self.assertIn("nz.y * face.z", self.shared)
        self.assertIn("texture(normal_texture, UV)", self.fragment)
        self.assertIn("texture(roughness_texture, UV)", self.fragment)
        self.assertIn("base_color.rgb", self.fragment)
        self.assertIn("METALLIC = metallic", self.fragment)
        self.assertIn("ROUGHNESS = roughness", self.fragment)

    def test_triplanar_projection_uses_world_space_coordinates(self):
        """Albedo, normal and roughness projections use transformed world-space inputs."""
        self.assertIn(
            "varying vec3 triplanar_world_position;", self.shared
        )
        self.assertIn(
            "varying vec3 triplanar_world_normal;", self.shared
        )
        self.assertIn(
            "triplanar_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;",
            self.shared,
        )
        self.assertIn(
            "triplanar_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);",
            self.shared,
        )
        self.assertIn(
            "sample_triplanar(albedo_texture, triplanar_world_position, triplanar_world_normal)",
            self.fragment,
        )
        self.assertIn(
            "sample_triplanar(roughness_texture, triplanar_world_position, triplanar_world_normal)",
            self.fragment,
        )
        self.assertIn(
            "sample_triplanar_normal(triplanar_world_position, triplanar_world_normal)",
            self.fragment,
        )
        self.assertNotIn("local_position", self.shared)
        self.assertNotIn("local_normal", self.shared)

    def test_all_triplanar_maps_share_signed_projection_uvs(self):
        """Every sampled map must share the signed world-space tangent frames."""
        for token in (
            "vec3 projection_face_signs(vec3 n)",
            "vec2 uv_x = vec2(uvw.y, uvw.z * face.x);",
            "vec2 uv_y = vec2(uvw.x, -uvw.z * face.y);",
            "vec2 uv_z = vec2(uvw.x, uvw.y * face.z);",
            "texture(tex, uv_x)",
            "texture(tex, uv_y)",
            "texture(tex, uv_z)",
            "texture(normal_texture, uv_x)",
            "texture(normal_texture, uv_y)",
            "texture(normal_texture, uv_z)",
        ):
            self.assertIn(token, self.shared)
        self.assertNotIn("texture(tex, uvw.yz)", self.shared)
        self.assertNotIn("texture(normal_texture, uvw.yz)", self.shared)

    def test_triplanar_normal_reconstruction_stays_world_space_until_view_transform(self):
        """Reconstruct triplanar normals in world space, then transform once for shading."""
        self.assertIn(
            "vec3 sample_triplanar_normal(vec3 p, vec3 world_geometric_normal)",
            self.shared,
        )
        self.assertIn("vec3 n = normalize(world_geometric_normal);", self.shared)
        self.assertIn("return normalize(n + perturbation);", self.shared)
        self.assertIn(
            "NORMAL = normalize(mat3(VIEW_MATRIX) * world_normal);",
            self.fragment,
        )
        self.assertNotIn("MODEL_NORMAL_MATRIX * world_normal", self.fragment)

    def test_unassigned_samplers_use_uniform_fallbacks(self):
        """Unassigned texture samplers preserve the base-colour and scalar PBR uniforms."""
        for token in (
            "uniform bool use_albedo_texture = false;",
            "uniform bool use_normal_texture = false;",
            "uniform bool use_roughness_texture = false;",
            "vec4 albedo_sample = vec4(1.0);",
            "if (use_albedo_texture) {",
            "if (use_normal_texture) {",
            "if (use_roughness_texture) {",
            "ALBEDO = base_color.rgb * albedo_sample.rgb;",
            "METALLIC = metallic;",
            "ROUGHNESS = roughness;",
        ):
            self.assertIn(token, self.shared)

    def test_mobile_uv_normal_map_feeds_fragment_ramp(self):
        """The mobile toon ramp must transform UV normal maps through view-space TBN."""
        mobile_block = self.fragment.split(
            "#ifdef IOM_CEL_MOBILE_VERTEX_RAMP", 1
        )[1].split("#endif", 1)[0]
        self.assertIn("mobile_uv_tangent_normal", self.fragment)
        self.assertIn("TANGENT", mobile_block)
        self.assertIn("BINORMAL", mobile_block)
        self.assertIn("use_normal_texture && !use_triplanar", mobile_block)
        self.assertIn("mobile_view_normal", mobile_block)
        self.assertIn('set_shader_parameter("use_triplanar", false)', self.test_script)
        self.assertIn("Mobile UV normal map did not affect", self.test_script)
        self.assertIn('set_shader_parameter("use_triplanar", true)', self.test_script)
        self.assertIn("Mobile triplanar normal map did not affect", self.test_script)

    def test_entrypoints_share_the_same_shader_implementation(self):
        """Desktop and mobile entrypoints must include the single shared source."""
        shared_include = (
            '#include "res://shaders/cel_stylized_pbr_shared.gdshaderinc"'
        )
        self.assertIn(shared_include, self.desktop_source)
        self.assertIn(shared_include, self.mobile_source)
        self.assertIn("#define IOM_CEL_MOBILE_VERTEX_RAMP", self.mobile_source)
        self.assertNotIn("#define IOM_CEL_MOBILE_VERTEX_RAMP", self.desktop_source)

    def test_mobile_force_vertex_shading_has_builtin_toon_fallback(self):
        """Mobile's built-in lighting path keeps toon diffuse, specular and rim."""
        self.assertIn("vertex_lighting", self.mobile_source)
        self.assertIn("diffuse_toon", self.mobile_source)
        self.assertIn("specular_toon", self.mobile_source)
        self.assertIn("SPECULAR = specular_amount", self.fragment)
        self.assertIn("RIM = clamp(vertex_rim_factor", self.fragment)

    def test_builtin_rim_is_mobile_only_to_avoid_double_desktop_rim(self):
        """Desktop uses its per-light rim; only mobile uses the built-in fallback."""
        mobile_block = self.fragment.split(
            "#ifdef IOM_CEL_MOBILE_VERTEX_RAMP", 1
        )[1].split("#endif", 1)[0]
        desktop_block = self.fragment.split(
            "#ifdef IOM_CEL_MOBILE_VERTEX_RAMP", 1
        )[0]
        self.assertIn("RIM = clamp(vertex_rim_factor", mobile_block)
        self.assertIn("RIM_TINT = rim_tint", mobile_block)
        self.assertNotIn("RIM =", desktop_block)
        self.assertNotIn("RIM_TINT =", desktop_block)

    def test_back_facing_lights_do_not_add_direct_diffuse(self):
        """Back-facing lights must not contribute the shadow tint as direct light."""
        guard = "if (n_dot_l > 0.0) {"
        self.assertIn(guard, self.light)
        light_code = "\n".join(
            line.split("//", 1)[0] for line in self.light.splitlines()
        )
        self.assertNotIn("return;", light_code)
        guarded_body = self.light.split(guard, 1)[1].rsplit("\n}", 1)[0]
        self.assertIn("DIFFUSE_LIGHT +=", guarded_body)
        self.assertIn("SPECULAR_LIGHT +=", guarded_body)

    def test_specular_amount_is_applied_once(self):
        """The fragment SPECULAR control must not be squared in the light lobe."""
        self.assertEqual(self.light.count("* SPECULAR_AMOUNT;"), 1)
        self.assertIn("SPECULAR = specular_amount", self.fragment)
        self.assertIn("vec3 f0 = mix(vec3(0.04), ALBEDO, METALLIC);", self.light)
        self.assertNotIn("specular_amount * SPECULAR_AMOUNT", self.light)
        self.assertNotIn("0.04 * specular_amount", self.light)

    def test_opaque_material_does_not_force_transparent_pipeline(self):
        """Opaque material output must not assign ALPHA."""
        self.assertNotIn("ALPHA =", self.fragment)

    def test_godot_test_scene_attaches_shader_to_mesh_instance(self):
        """The smoke scene binds the shader to a real MeshInstance3D node."""
        self.assertIn('type="MeshInstance3D"', self.scene)
        self.assertIn("cel_stylized_pbr.gdshader", self.scene)
        self.assertIn("cel_stylized_pbr_mobile.gdshader", self.scene)
        self.assertIn("material_override = SubResource", self.scene)

    def test_capture_samples_projected_mobile_mesh(self):
        """The Vulkan regression must sample the mesh, not an arbitrary viewport pixel."""
        self.assertIn('get_node_or_null("Camera3D") as Camera3D', self.test_script)
        self.assertIn("camera.is_position_behind(mobile_mesh.global_position)", self.test_script)
        self.assertIn("camera.unproject_position(mobile_mesh.global_position)", self.test_script)
        self.assertIn("rotation_degrees = Vector3(-24.2, 0, 0)", self.scene)


if __name__ == "__main__":
    unittest.main()
