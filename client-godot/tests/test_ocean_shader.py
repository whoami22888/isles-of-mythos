"""Non-rendering regression contracts for the existing Godot Mobile ocean shader.

These checks cannot establish shader compilation, image quality, or device FPS.
"""

import re
import unittest
from pathlib import Path

SHADER = Path(__file__).resolve().parents[1] / "shaders" / "ocean_surface.gdshader"


def strip_shader_comments(source: str) -> str:
    """Remove GLSL comments without truncating quoted include paths."""
    return re.sub(
        r'("(?:\\.|[^"\\])*")|/\*.*?\*/|//[^\n]*',
        lambda match: match.group(1) or "",
        source,
        flags=re.DOTALL,
    )


def shader_stage_body(source: str, stage: str) -> str:
    """Return a top-level shader stage body for stage-local contracts."""
    match = re.search(
        rf"(?ms)^void\s+{re.escape(stage)}\s*\(\s*\)\s*\{{(.*?)^\}}",
        source,
    )
    if match is None:
        raise AssertionError(f"missing {stage} shader stage")
    return match.group(1)


class OceanShaderContractTests(unittest.TestCase):
    """Guard production ocean features against accidental shader replacement."""

    @classmethod
    def setUpClass(cls):
        """Read the production shader and strip comments before matching code."""
        cls.source = SHADER.read_text(encoding="utf-8")
        cls.code = strip_shader_comments(cls.source)

    def test_comment_strip_preserves_shader_include_paths(self):
        """Keep quoted res:// paths while removing actual GLSL comments."""
        sample = (
            '#include "res://shaders/coastal_shore_sampler.gdshaderinc"\n'
            '// NORMAL_MAP = vec3(0.0);\n'
            '/* ALPHA = 0.0; */\n'
            'uniform float foam_amount = 0.7; // example comment\n'
        )
        cleaned = strip_shader_comments(sample)
        self.assertIn('#include "res://shaders/coastal_shore_sampler.gdshaderinc"', cleaned)
        self.assertIn('uniform float foam_amount = 0.7;', cleaned)
        self.assertNotIn('NORMAL_MAP = vec3(0.0);', cleaned)
        self.assertNotIn('ALPHA = 0.0;', cleaned)
        self.assertNotIn('example comment', cleaned)

    def test_shoreline_include_resolves_required_functions(self):
        """A named include must exist and define the functions the ocean calls."""
        includes = re.findall(r'^\s*#include\s+"(res://[^"]+)"', self.code, re.MULTILINE)
        self.assertIn("res://shaders/coastal_shore_sampler.gdshaderinc", includes)
        for uri in includes:
            path = SHADER.parents[1] / uri.removeprefix("res://")
            with self.subTest(include=uri):
                self.assertTrue(path.is_file(), f"missing Godot shader include: {uri}")
                source = strip_shader_comments(path.read_text(encoding="utf-8"))
                if uri.endswith("/coastal_shore_sampler.gdshaderinc"):
                    for symbol in ("shore_terrain_coverage", "shore_terrain_height"):
                        self.assertRegex(source, rf"\bfloat\s+{symbol}\s*\(")

    def test_mobile_depth_texture_alpha_path_is_preserved(self):
        """Use the existing Mobile water depth-texture path with bounded alpha."""
        self.assertRegex(
            self.code,
            r"render_mode\s+blend_mix\s*,\s*depth_draw_opaque\s*,\s*cull_back\s*,\s*diffuse_burley\s*,\s*specular_schlick_ggx\s*;",
        )
        self.assertRegex(
            self.code,
            r"uniform\s+sampler2D\s+depth_texture\s*:\s*hint_depth_texture",
        )
        self.assertIn("texture(depth_texture, SCREEN_UV)", self.code)
        self.assertIn("INV_PROJECTION_MATRIX", self.code)
        self.assertRegex(self.code, r"\bALPHA\s*=\s*mix\s*\(\s*0\.85\s*,\s*0\.98")
        self.assertRegex(
            self.code,
            r"uniform\s+bool\s+shoremap_bound\s*=\s*false\s*;",
        )

    def test_depth_texture_drives_view_space_thickness(self):
        """Require a positive view-space scene-minus-water thickness."""
        fragment_body = shader_stage_body(self.code, "fragment")
        self.assertIn("float surface_depth = max(-VERTEX.z, 0.001);", fragment_body)
        self.assertIn("float raw_depth = texture(depth_texture, SCREEN_UV).r;", fragment_body)
        self.assertIn("INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0)", fragment_body)
        self.assertIn("float scene_thickness = max(behind_depth - surface_depth, 0.0);", fragment_body)
        self.assertIn("effective_depth_m", fragment_body)

    def test_deterministic_capture_controls_both_stages(self):
        """Require exactly one capture-time selector in each shader stage."""
        self.assertIn("uniform bool deterministic_capture", self.code)
        self.assertIn("uniform float capture_time_seconds", self.code)
        capture_selector = (
            r"deterministic_capture\s*\?\s*capture_time_seconds\s*:\s*TIME"
        )
        vertex_body = shader_stage_body(self.code, "vertex")
        fragment_body = shader_stage_body(self.code, "fragment")
        self.assertEqual(len(re.findall(capture_selector, vertex_body)), 1)
        self.assertEqual(len(re.findall(capture_selector, fragment_body)), 1)

    def test_terrain_derived_shoreline_and_unbound_guard(self):
        """Require terrain height to drive depth attenuation and shoreline foam."""
        self.assertIn(
            '#include "res://shaders/coastal_shore_sampler.gdshaderinc"',
            self.code,
        )
        self.assertRegex(
            self.code,
            r"shore_terrain_coverage\s*\(p\)\s*\*\s*float\s*\(shoremap_bound\)",
        )
        self.assertRegex(
            self.code,
            r"float\s+floor_y\s*=\s*shore_terrain_height\s*\(\s*p\s*\)\s*;",
        )
        self.assertRegex(
            self.code,
            r"float\s+depth_m\s*=\s*max\s*\(\s*SEA_LEVEL\s*-\s*floor_y\s*,\s*0\.0\s*\)\s*;",
        )
        self.assertRegex(
            self.code,
            (
                r"float\s+depth_factor\s*=\s*1\.0\s*-\s*smoothstep\s*"
                r"\(\s*0\.15\s*,\s*6\.5\s*,\s*depth_m\s*\)\s*;"
            ),
        )
        self.assertRegex(
            self.code,
            (
                r"float\s+shallow_factor\s*=\s*coverage\s*\*\s*"
                r"depth_factor\s*\*\s*seabed_variation\s*;"
            ),
        )
        self.assertRegex(
            self.code,
            r"float\s+contact\s*=\s*coverage\s*\*\s*\(\s*1\.0\s*-\s*smoothstep",
        )

    def test_shoreline_foam_uses_absolute_sea_level_distance(self):
        """Foam must reach exposed sand as well as the submerged shoreline."""
        fragment_body = shader_stage_body(self.code, "fragment")
        self.assertRegex(
            fragment_body,
            r"float\s+shoreline_distance_m\s*=\s*abs\s*\(\s*SEA_LEVEL\s*-\s*floor_y\s*\)\s*;",
        )
        self.assertRegex(
            fragment_body,
            r"float\s+terrain_contact\s*=\s*coverage\s*\*\s*\(\s*1\.0\s*-\s*smoothstep\s*\(\s*0\.025\s*,\s*0\.24\s*,\s*shoreline_distance_m\s*\)\s*\)\s*;",
        )
        self.assertRegex(
            fragment_body,
            r"float\s+depth_contact\s*=\s*coverage\s*\*\s*\(\s*1\.0\s*-\s*smoothstep\s*\(\s*0\.08\s*,\s*1\.35\s*,\s*scene_thickness\s*\)\s*\)\s*;",
        )
        self.assertRegex(
            fragment_body,
            r"float\s+contact\s*=\s*max\s*\(\s*terrain_contact\s*,\s*depth_contact\s*\)\s*;",
        )
        self.assertNotRegex(
            fragment_body,
            r"contact\s*=\s*coverage\s*\*\s*smoothstep\s*\(\s*0\.02\s*,\s*0\.12\s*,\s*depth_m",
        )

    def test_existing_wave_normals_and_wake_are_not_lost(self):
        """Protect wave displacement in vertex() and wake inputs in fragment()."""
        vertex_body = shader_stage_body(self.code, "vertex")
        fragment_body = shader_stage_body(self.code, "fragment")
        for symbol in ("swell_scale", "near_patch_half_extent", "swell_crest"):
            with self.subTest(stage="vertex", symbol=symbol):
                self.assertIn(symbol, vertex_body)
        for symbol in (
            "vessel_xz",
            "vessel_forward",
            "wake_strength",
            "foam_amount",
            "NORMAL_MAP",
            "ROUGHNESS",
        ):
            with self.subTest(stage="fragment", symbol=symbol):
                self.assertIn(symbol, fragment_body)
        self.assertIn("vec3 world_base_offset = vec3(0.0, 0.18, 0.0);", vertex_body)
        self.assertIn("displacement + vertical_displacement", vertex_body)
        self.assertIn("VERTEX += transpose(MODEL_NORMAL_MATRIX)", vertex_body)
        self.assertRegex(vertex_body, r"NORMAL\s*=\s*normalize")


    def test_dual_gerstner_waves_and_scene_controls_are_live(self):
        """Require two world-space Gerstner trains, analytic normals, and exposed controls."""
        declarations = (
            "uniform vec4 deep_ocean_color",
            "uniform vec4 shallow_ocean_color",
            "uniform vec4 foam_color",
            "uniform float wave_speed",
            "uniform float wave_amplitude",
            "uniform float wave_frequency",
            "uniform vec2 wave_direction_a",
            "uniform vec2 wave_direction_b",
            "uniform float wave_steepness_a",
            "uniform float wave_steepness_b",
        )
        for declaration in declarations:
            with self.subTest(declaration=declaration):
                self.assertIn(declaration, self.code)

        vertex_body = shader_stage_body(self.code, "vertex")
        vertex_tokens = (
            "vec2 xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;",
            "dot(xz, direction_a)",
            "dot(xz, direction_b)",
            "sin(wave_phase_a)",
            "cos(wave_phase_a)",
            "sin(wave_phase_b)",
            "cos(wave_phase_b)",
            "wave_speed",
            "wave_amplitude",
            "wave_frequency",
            "horizontal_displacement",
            "vertical_displacement",
            "tangent_x",
            "tangent_z",
            "transpose(MODEL_NORMAL_MATRIX)",
            "transpose(mat3(MODEL_MATRIX))",
        )
        for token in vertex_tokens:
            with self.subTest(token=token):
                self.assertIn(token, vertex_body)
        self.assertIn("vec3 world_normal = normalize(cross(tangent_z, tangent_x));", vertex_body)
        self.assertIn(
            "NORMAL = normalize(transpose(mat3(MODEL_MATRIX)) * world_normal);",
            vertex_body,
        )

        fragment_body = shader_stage_body(self.code, "fragment")
        self.assertIn("wave_speed", fragment_body)

    def test_mobile_normal_map_is_encoded_in_unsigned_tangent_space(self):
        """Tie unsigned tangent-space encoding to the actual NORMAL_MAP assignment."""
        encoded_assignment = re.compile(
            r"""
            NORMAL_MAP \s* = \s* normalize \s* \( \s* vec3 \s* \(
            [^;]*?
            \) \s* \) \s* \* \s* 0\.5 \s* \+ \s* 0\.5 \s* ;
            """,
            re.VERBOSE,
        )
        fragment_body = shader_stage_body(self.code, "fragment")
        self.assertRegex(fragment_body, encoded_assignment)

    def test_wake_is_derived_from_vessel_position_direction_and_strength(self):
        """Require wake geometry to use the vessel position, heading and strength."""
        patterns = (
            r"vec2\s+p\s*=\s*surface_world\.xz\s*;",
            r"vec2\s+fwd\s*=\s*vessel_forward\s*;",
            r"vec2\s+rel\s*=\s*p\s*-\s*vessel_xz\s*;",
            r"float\s+along\s*=\s*dot\s*\(\s*rel\s*,\s*-fwd\s*\)\s*;",
            r"float\s+across\s*=\s*abs\s*\(\s*dot\s*\(\s*rel\s*,\s*side\s*\)\s*\)\s*;",
            (
                r"float\s+wake_band\s*=\s*smoothstep\s*"
                r"\(\s*0\.6\s*,\s*2\.2\s*,\s*along\s*\)\s*\*\s*"
                r"\(\s*1\.0\s*-\s*smoothstep\s*"
                r"\(\s*9\.0\s*,\s*28\.0\s*,\s*along\s*\)\s*\)\s*;"
            ),
            (
                r"float\s+lane\s*=\s*1\.0\s*-\s*smoothstep\s*"
                r"\(\s*half_w\s*\*\s*0\.28\s*,\s*half_w\s*,\s*across\s*\)\s*;"
            ),
            (
                r"float\s+bow\s*=\s*1\.0\s*-\s*smoothstep\s*"
                r"\(\s*0\.35\s*,\s*3\.6\s*,\s*length\s*"
                r"\(\s*rel\s*-\s*fwd\s*\*\s*2\.6\s*\)\s*\)\s*;"
            ),
            (
                r"float\s+wake\s*=\s*\(\s*wake_band\s*\*\s*lane\s*\*\s*"
                r"wake_noise\s*\*\s*0\.55\s*\+\s*bow\s*\*\s*0\.35\s*\)"
                r"\s*\*\s*wake_strength\s*;"
            ),
        )
        fragment_body = shader_stage_body(self.code, "fragment")
        for pattern in patterns:
            with self.subTest(pattern=pattern):
                self.assertRegex(fragment_body, pattern)

    def test_foam_is_bounded(self):
        """Keep the shoreline and wake foam blend within its existing limit."""
        fragment_body = shader_stage_body(self.code, "fragment")
        self.assertRegex(
            fragment_body,
            (
                r"foam\s*=\s*clamp\s*"
                r"\(shore_foam\s*\+\s*wake\s*,\s*0\.0\s*,\s*0\.82\s*\)"
            ),
        )


    def test_depth_and_foam_reach_surface_color_output(self):
        """Prevent live depth and shoreline/wake terms becoming dead calculations."""
        patterns = (
            re.compile(
                r"""
                vec3 \s+ sea \s* = \s* mix \s*
                \(
                    \s* gulf \s*, \s*
                    shallow_ocean_color \. rgb \s*, \s*
                    clamp \s* \(
                        \s* shallow_factor \s*, \s* 0\.0 \s*, \s* 1\.0 \s*
                    \)
                    \s*
                \)
                """,
                re.VERBOSE,
            ),
            re.compile(
                r"""
                float \s+ shore_foam \s* = \s*
                contact \s* \* \s* foam_motion \s* \* \s* foam_amount
                """,
                re.VERBOSE,
            ),
            re.compile(
                r"""
                float \s+ foam \s* = \s* clamp \s*
                \(
                    \s* shore_foam \s* \+ \s* wake \s*, \s*
                    0\.0 \s*, \s* 0\.82 \s*
                \)
                """,
                re.VERBOSE,
            ),
            re.compile(
                r"""
                ALBEDO \s* = \s* mix \s*
                \(
                    \s* sea \s*, \s* foam_color \. rgb \s*, \s* foam \s*
                \)
                """,
                re.VERBOSE,
            ),
            re.compile(
                r"ALPHA\s*=\s*mix\s*\(\s*0\.85\s*,\s*0\.98\s*,\s*clamp\s*\(\s*effective_depth_m",
            ),
        )
        fragment_body = shader_stage_body(self.code, "fragment")
        for pattern in patterns:
            with self.subTest(pattern=pattern.pattern):
                self.assertRegex(fragment_body, pattern)


if __name__ == "__main__":
    unittest.main()
