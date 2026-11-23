"""Non-rendering regression contracts for the existing Godot Mobile ocean shader.

These checks cannot establish shader compilation, image quality, or device FPS.
"""

import hashlib
import importlib.util
import json
import re
import tempfile
import unittest
from pathlib import Path
import sys

CLIENT = Path(__file__).resolve().parents[1]
SHADER = CLIENT / "shaders" / "ocean_surface.gdshader"
COAST_SCRIPT = CLIENT / "scripts" / "realistic_coastal_slice.gd"
WAVE_SETTINGS = CLIENT / "scripts" / "ocean_wave_settings.gd"
WAKE_SHADER = CLIENT / "shaders" / "ship_wake_foam.gdshader"
WAVE_INCLUDE = CLIENT / "shaders" / "coastal_ocean_wave.gdshaderinc"
WAKE_SCRIPT = CLIENT / "scripts" / "ship_wake_effect.gd"
CAPTURE_SCRIPT = CLIENT / "tests" / "render_coastal_fx_sequence.gd"
CONTINUITY_SCRIPT = CLIENT.parent / "scripts" / "check_capture_continuity.py"


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


def shader_assignment_expression(source: str, name: str) -> str:
    """Return one shader assignment expression without its terminating semicolon."""
    match = re.search(
        rf"(?ms)^[ \\t]*(?:(?:float|vec[234]|int|bool)\\s+)?{re.escape(name)}\\s*=\\s*(.*?);",
        source,
    )
    if match is None:
        raise AssertionError(f"missing shader assignment: {name}")
    return " ".join(match.group(1).split())


class OceanShaderContractTests(unittest.TestCase):
    def test_coastal_capture_embeds_verified_source_asset_hashes(self):
        """Tie moving engine evidence to the exact licensed source asset bytes."""
        capture = (CLIENT / "tests" / "render_coastal_fx_sequence.gd").read_text(encoding="utf-8")
        workflow = (CLIENT.parent / ".github" / "workflows" / "iom-coastal-ship-fx.yml").read_text(encoding="utf-8")
        for token in (
            'const SOURCE_ASSET_MANIFEST := "res://assets/external-assets.json"',
            'const SOURCE_ASSET_ROOT := "res://assets/external"',
            "FileAccess.get_sha256(source_path)",
            "actual_sha != expected_sha",
            "ASSET-SHA256SUMS",
            "ASSET-PROVENANCE.json",
            "IOM_INTERNAL_ASSET_PROVENANCE",
        ):
            with self.subTest(token=token):
                self.assertIn(token, capture)
        self.assertIn("sha256sum frame_*.rgba render.log > SHA256SUMS", workflow)
        self.assertIn("path: ${{ runner.temp }}/coastal-fx-frames/", workflow)


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

    def test_opaque_terrain_depth_path_is_preserved(self):
        """Keep the existing Mobile opaque depth-write path and terrain depth source."""
        self.assertRegex(
            self.code,
            r"render_mode\s+cull_back\s*,\s*depth_draw_opaque\s*,\s*diffuse_burley\s*,\s*specular_schlick_ggx\s*;",
        )
        self.assertNotIn("blend_mix", self.code)
        self.assertNotIn("hint_depth_texture", self.code)
        self.assertNotIn("ALPHA =", self.code)
        self.assertRegex(
            self.code,
            r"uniform\s+bool\s+shoremap_bound\s*=\s*false\s*;",
        )

    def test_terrain_heightfield_drives_depth_attenuation(self):
        """Use the live coastal heightfield for depth tint and foam without alpha blending."""
        fragment_body = shader_stage_body(self.code, "fragment")
        self.assertIn("float depth_m = max(SEA_LEVEL - floor_y, 0.0);", fragment_body)
        self.assertIn("float depth_factor = 1.0 - smoothstep(0.15, 6.5, depth_m);", fragment_body)
        self.assertIn("float shallow_factor = coverage * depth_factor * seabed_variation;", fragment_body)
        self.assertIn("float depth_contact = coverage * (1.0 - smoothstep(0.08, 1.35, depth_m));", fragment_body)
        self.assertNotIn("scene_thickness", fragment_body)
        self.assertNotIn("depth_texture", self.code)

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
            r"float\s+depth_factor\s*=\s*1\.0\s*-\s*smoothstep\s*\(\s*0\.15\s*,\s*6\.5\s*,\s*depth_m\s*\)\s*;",
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
            r"float\s+contact\s*=\s*max\s*\(\s*terrain_contact\s*,\s*depth_contact\s*\)\s*;",
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
            r"float\s+depth_contact\s*=\s*coverage\s*\*\s*\(\s*1\.0\s*-\s*smoothstep\s*\(\s*0\.08\s*,\s*1\.35\s*,\s*depth_m\s*\)\s*\)\s*;",
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
        fragment_symbols = (
            "vessel_xz",
            "vessel_forward",
            "wake_strength",
            "foam_amount",
            "NORMAL_MAP",
            "ROUGHNESS",
        )
        for symbol in fragment_symbols:
            with self.subTest(stage="fragment", symbol=symbol):
                self.assertIn(symbol, fragment_body)
        self.assertIn("vec3 world_base_offset = vec3(0.0, 0.18, 0.0);", vertex_body)
        self.assertIn("displacement + vertical_displacement", vertex_body)
        self.assertIn("VERTEX += transpose(MODEL_NORMAL_MATRIX)", vertex_body)
        self.assertRegex(vertex_body, r"NORMAL\s*=\s*normalize")


    def test_shoreline_foam_uses_heightfield_ring_mask_and_aperiodic_breakup(self):
        """Keep shoreline foam tied to nearby land without a repeating sine lattice."""
        for token in (
            "const vec2 RING_DIRS[12]",
            "float foam_hash(vec2 q)",
            "float shore_land_fraction(vec2 p, float radius_m)",
            "for (int i = 0; i < 12; i++)",
            "shore_terrain_height(sample_position)",
        ):
            with self.subTest(token=token):
                self.assertIn(token, self.code)

        fragment_body = shader_stage_body(self.code, "fragment")
        for token in (
            "if (water_here > 0.0 && contact > 0.0)",
            "shore_land_fraction(p, 1.1)",
            "shore_land_fraction(p, 2.6)",
            "float shore_band = clamp(land_near * 1.1 + land_far * 0.35, 0.0, 1.0);",
            "float breakup = 0.78 + 0.22 * breakup_noise;",
            "mix(0.55, 1.0, foam_motion)",
            "contact * shore_band * breakup",
        ):
            with self.subTest(token=token):
                self.assertIn(token, fragment_body)
        self.assertNotIn("contact * foam_motion * foam_amount", fragment_body)

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
        fragment_body = shader_stage_body(self.code, "fragment")
        normal_expression = shader_assignment_expression(fragment_body, "NORMAL_MAP")
        self.assertIn("normalize(vec3(", normal_expression)
        self.assertRegex(normal_expression, r"\\)\\s*\\*\\s*0\\.5\\s*\\+\\s*0\\.5$")

    def test_wake_is_derived_from_vessel_position_direction_and_strength(self):
        """Require the final wake value to depend on vessel position, heading and strength."""
        fragment_body = shader_stage_body(self.code, "fragment")
        expressions = {
            name: shader_assignment_expression(fragment_body, name)
            for name in ("p", "fwd", "rel", "along", "across", "wake")
        }
        self.assertIn("surface_world.xz", expressions["p"])
        self.assertIn("vessel_forward", expressions["fwd"])
        self.assertIn("p - vessel_xz", expressions["rel"])
        self.assertIn("dot(rel, -fwd)", expressions["along"])
        self.assertIn("dot(rel, side)", expressions["across"])
        for symbol in ("wake_band", "lane", "wake_noise", "bow", "wake_strength"):
            with self.subTest(symbol=symbol):
                self.assertIn(symbol, expressions["wake"])

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
        """Require terrain depth and vessel/shore foam to reach the final surface color."""
        fragment_body = shader_stage_body(self.code, "fragment")
        expressions = {
            name: shader_assignment_expression(fragment_body, name)
            for name in (
                "floor_y",
                "depth_m",
                "depth_factor",
                "shallow_factor",
                "terrain_contact",
                "depth_contact",
                "contact",
                "sea",
                "shore_foam",
                "wake",
                "foam",
                "ALBEDO",
            )
        }
        dataflow = (
            ("floor_y", "shore_terrain_height(p)"),
            ("depth_m", "SEA_LEVEL - floor_y"),
            ("depth_factor", "depth_m"),
            ("shallow_factor", "depth_factor"),
            ("terrain_contact", "floor_y"),
            ("depth_contact", "depth_m"),
            ("contact", "terrain_contact"),
            ("contact", "depth_contact"),
            ("sea", "shallow_factor"),
            ("shore_foam", "contact"),
            ("shore_foam", "shore_band"),
            ("shore_foam", "foam_amount"),
            ("foam", "shore_foam"),
            ("foam", "wake"),
            ("ALBEDO", "sea"),
            ("ALBEDO", "foam"),
        )
        for assignment, dependency in dataflow:
            with self.subTest(assignment=assignment, dependency=dependency):
                self.assertIn(dependency, expressions[assignment])

    def test_scene_does_not_suppress_mobile_wave_motion_or_normals(self):
        """Keep scene overrides strong enough to expose swell and moving normal detail."""
        coast = COAST_SCRIPT.read_text(encoding="utf-8")
        settings = WAVE_SETTINGS.read_text(encoding="utf-8")
        def scene_value(name):
            match = re.search(
                rf'set_shader_parameter\("{re.escape(name)}",\s*([0-9.]+)\)',
                coast,
            )
            self.assertIsNotNone(match, f"missing scene parameter {name}")
            return float(match.group(1))
        def exported_value(name):
            match = re.search(
                rf'var\s+{re.escape(name)}\s*:\s*float\s*=\s*([0-9.]+)',
                settings,
            )
            self.assertIsNotNone(match, f"missing exported wave setting {name}")
            return float(match.group(1))
        self.assertGreaterEqual(scene_value("swell_scale"), 0.80)
        self.assertGreaterEqual(scene_value("ripple_detail"), 0.80)
        self.assertGreaterEqual(scene_value("foam_amount"), 1.00)
        self.assertGreaterEqual(scene_value("wake_strength"), 1.00)
        self.assertGreaterEqual(exported_value("wave_speed"), 1.30)
        self.assertGreaterEqual(exported_value("wave_amplitude"), 0.80)
        self.assertGreaterEqual(exported_value("wave_steepness_a"), 0.75)
        self.assertGreaterEqual(exported_value("wave_steepness_b"), 0.60)


    def test_wake_uses_the_ocean_analytic_wave_contract(self):
        """Keep the transparent wake ribbon on the same displaced water surface."""
        wake = strip_shader_comments(WAKE_SHADER.read_text(encoding="utf-8"))
        shared = strip_shader_comments(WAVE_INCLUDE.read_text(encoding="utf-8"))
        shared_tokens = (
            "float wave_k_a = max(wave_frequency, 0.05);",
            "float wave_k_b = wave_k_a * 1.55;",
            "float safe_wave_speed = max(wave_speed, 0.0);",
            "float amplitude_a = amplitude * 0.65;",
            "float amplitude_b = amplitude * 0.35;",
            "float legacy_displacement = (",
            "float coastal_ocean_wave_envelope(",
            "return vec3(",
        )
        for token in shared_tokens:
            with self.subTest(token=token):
                self.assertIn(token, shared)
        ocean_tokens = (
            "float wave_k_a = max(wave_frequency, 0.05);",
            "float wave_k_b = wave_k_a * 1.55;",
            "float safe_wave_speed = max(wave_speed, 0.0);",
            "float amplitude_a = amplitude * 0.65;",
            "float amplitude_b = amplitude * 0.35;",
            "float wave_phase_a = dot(xz, direction_a) * wave_k_a - ocean_time * safe_wave_speed;",
        )
        for token in ocean_tokens:
            with self.subTest(ocean_token=token):
                self.assertIn(token, self.code)
        for token in (
            '#include "res://shaders/coastal_ocean_wave.gdshaderinc"',
            "coastal_ocean_wave_displacement(",
            "coastal_ocean_wave_envelope(",
            "VERTEX += transpose(MODEL_NORMAL_MATRIX) * displacement * envelope;",
        ):
            with self.subTest(wake_token=token):
                self.assertIn(token, wake)

    def test_wake_wave_parameters_and_capture_clock_are_synchronised(self):
        """Prevent the wake from drifting below the ocean or using wall-clock capture time."""
        wake = strip_shader_comments(WAKE_SHADER.read_text(encoding="utf-8"))
        wake_script = WAKE_SCRIPT.read_text(encoding="utf-8")
        settings = WAVE_SETTINGS.read_text(encoding="utf-8")
        capture = CAPTURE_SCRIPT.read_text(encoding="utf-8")
        for token in (
            "uniform bool deterministic_capture = false;",
            "uniform float capture_time_seconds = 0.0;",
            "deterministic_capture ? capture_time_seconds : TIME",
        ):
            with self.subTest(shader_token=token):
                self.assertIn(token, wake)
        for token in (
            "func sync_ocean_wave_parameters(",
            "func set_deterministic_capture(",
            "func set_capture_time(",
            '"wave_speed"',
            '"wave_amplitude"',
            '"wave_frequency"',
            '"wave_steepness_a"',
            '"wave_steepness_b"',
            '"swell_scale"',
        ):
            with self.subTest(script_token=token):
                self.assertIn(token, wake_script)
        self.assertIn('call_deferred("_sync_wake_material", coast, material)', settings)
        self.assertIn('wake.call("sync_ocean_wave_parameters", ocean_material)', settings)
        self.assertIn("integration.wake.sync_ocean_wave_parameters(ocean_material)", capture)
        self.assertIn("integration.wake.set_deterministic_capture(true, 0.0)", capture)
        self.assertIn("integration.wake.set_capture_time(capture_time)", capture)
        self.assertIn("integration.wake.get_triangle_count() < 8", capture)
        self.assertIn("scene.cinematic_camera.position = Vector3(-15.0, 5.5, -5.8)", capture)


    def test_coastal_capture_requires_visible_foam_pixels(self):
        """Geometry alone cannot pass the shoreline/wake visual-effect regression."""
        capture = CAPTURE_SCRIPT.read_text(encoding="utf-8")
        for token in (
            "func _capture_visible_foam_report(",
            "func _measure_foam_pixel_change(",
            "func _shoreline_probe_regions(",
            "func _ocean_wake_probe_regions(",
            "func _ribbon_probe_regions(",
            'directory.path_join("FOAM_PIXEL_REPORT.json")',
            "IOM_INTERNAL_FOAM_PIXELS channel=shoreline",
            "await _capture_visible_foam_report(scene, integration, ocean_material, directory)",
        ):
            with self.subTest(token=token):
                self.assertIn(token, capture)
        self.assertIn("integration.wake.get_triangle_count() < 8", capture)

    @staticmethod
    def _continuity_module():
        spec = importlib.util.spec_from_file_location("iom_capture_continuity", CONTINUITY_SCRIPT)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        return module

    @staticmethod
    def _valid_foam_report(module):
        thresholds = {
            name: dict(values)
            for name, values in module.FOAM_PIXEL_THRESHOLDS.items()
        }
        channels = {}
        for name, threshold in thresholds.items():
            changed = threshold["min_pixels"] + 20
            roi = 10000
            channels[name] = {
                "changed_pixels": changed,
                "roi_pixels": roi,
                "coverage": changed / roi,
                "mean_luma_delta": threshold["min_mean_luma_delta"] + 0.02,
                "max_luma_delta": threshold["min_mean_luma_delta"] + 0.08,
            }
        return {
            "schema_version": 1,
            "status": "PASS",
            "thresholds": thresholds,
            "channels": channels,
            "errors": [],
        }

    def _write_foam_artifact(self, directory, report, logged_sha=None, logged_status="PASS"):
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True)
        report_bytes = json.dumps(report, sort_keys=True).encode("utf-8")
        (directory / "FOAM_PIXEL_REPORT.json").write_bytes(report_bytes)
        digest = logged_sha or hashlib.sha256(report_bytes).hexdigest()
        (directory / "render.log").write_text(
            f"IOM_INTERNAL_FOAM_REPORT sha256={digest} status={logged_status}\n",
            encoding="utf-8",
        )

    def test_foam_pixel_report_is_hash_anchored_and_validated(self):
        module = self._continuity_module()
        with tempfile.TemporaryDirectory() as folder:
            artifact = Path(folder) / "frames" / "internal-coastal-frames"
            self._write_foam_artifact(artifact, self._valid_foam_report(module))
            result = module.verify_foam_pixel_report(artifact)
            self.assertEqual(
                result["result"], "PASS_PIXEL_FOAM_SCREENING_NOT_VISUAL_ACCEPTANCE"
            )
            self.assertEqual(set(result["channels"]), {"shoreline", "ocean_wake", "ribbon_wake"})

    def test_foam_pixel_report_rejects_hash_mismatch(self):
        module = self._continuity_module()
        with tempfile.TemporaryDirectory() as folder:
            artifact = Path(folder)
            self._write_foam_artifact(
                artifact, self._valid_foam_report(module), logged_sha="0" * 64
            )
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                module.verify_foam_pixel_report(artifact)

    def test_foam_pixel_report_rejects_missing_file(self):
        module = self._continuity_module()
        with tempfile.TemporaryDirectory() as folder:
            artifact = Path(folder)
            (artifact / "render.log").write_text("", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "missing foam pixel report"):
                module.verify_foam_pixel_report(artifact)

    def test_foam_pixel_report_rejects_failed_renderer_status(self):
        module = self._continuity_module()
        with tempfile.TemporaryDirectory() as folder:
            artifact = Path(folder)
            report = self._valid_foam_report(module)
            report["status"] = "FAIL"
            self._write_foam_artifact(artifact, report, logged_status="FAIL")
            with self.assertRaisesRegex(ValueError, "reported FAIL"):
                module.verify_foam_pixel_report(artifact)

    def test_foam_pixel_report_cannot_weaken_thresholds(self):
        module = self._continuity_module()
        with tempfile.TemporaryDirectory() as folder:
            artifact = Path(folder)
            report = self._valid_foam_report(module)
            report["thresholds"]["shoreline"]["min_pixels"] = 1
            self._write_foam_artifact(artifact, report)
            with self.assertRaisesRegex(ValueError, "thresholds were weakened"):
                module.verify_foam_pixel_report(artifact)

    def test_foam_pixel_report_rejects_insufficient_coverage(self):
        module = self._continuity_module()
        with tempfile.TemporaryDirectory() as folder:
            artifact = Path(folder)
            report = self._valid_foam_report(module)
            report["channels"]["shoreline"]["changed_pixels"] = 1
            report["channels"]["shoreline"]["coverage"] = 0.0001
            self._write_foam_artifact(artifact, report)
            with self.assertRaisesRegex(ValueError, "below pixel minimum"):
                module.verify_foam_pixel_report(artifact)

    def test_continuity_screen_requires_report_when_raw_artifact_exists(self):
        module = self._continuity_module()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            ordered = root / "ordered-frames"
            ordered.mkdir()
            for index, value in enumerate([20, 21, 22, 23, 24, 25]):
                (ordered / f"frame_{index:04d}.rgba").write_bytes(
                    bytes((value, value, value, 255)) * (8 * 8)
                )
            artifact = root / "frames" / "internal-coastal-frames"
            self._write_foam_artifact(artifact, self._valid_foam_report(module))
            result = module.verify(module.CaptureSpec(
                folder=ordered, frames=6, width=8, height=8, segment_size=2
            ))
            self.assertEqual(
                result["foam_pixels"]["result"],
                "PASS_PIXEL_FOAM_SCREENING_NOT_VISUAL_ACCEPTANCE",
            )
            (artifact / "FOAM_PIXEL_REPORT.json").unlink()
            with self.assertRaisesRegex(ValueError, "missing foam pixel report"):
                module.verify(module.CaptureSpec(
                    folder=ordered, frames=6, width=8, height=8, segment_size=2
                ))


if __name__ == "__main__":
    unittest.main()
