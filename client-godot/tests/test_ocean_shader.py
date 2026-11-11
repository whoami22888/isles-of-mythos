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

    def test_mobile_opaque_depth_path_is_preserved(self):
        """Keep the mobile opaque depth path without fragment alpha writes."""
        self.assertRegex(
            self.code, r"render_mode\s+cull_back\s*,\s*depth_draw_opaque\s*;"
        )
        self.assertNotRegex(self.code, r"\bALPHA\s*=")

    def test_deterministic_capture_controls_both_stages(self):
        """Require explicit capture time in vertex and fragment stages."""
        self.assertIn("uniform bool deterministic_capture", self.code)
        self.assertIn("uniform float capture_time_seconds", self.code)
        self.assertEqual(
            len(
                re.findall(
                    r"deterministic_capture\s*\?\s*capture_time_seconds\s*:\s*TIME",
                    self.code,
                )
            ),
            2,
        )

    def test_terrain_derived_shoreline_and_unbound_guard(self):
        """Require terrain-derived foam and protection for unbound shore maps."""
        self.assertIn(
            '#include "res://shaders/coastal_shore_sampler.gdshaderinc"',
            self.code,
        )
        self.assertRegex(
            self.code,
            r"shore_terrain_coverage\s*\(p\)\s*\*\s*float\s*\(shoremap_bound\)",
        )
        self.assertRegex(self.code, r"shore_terrain_height\s*\(p\)")
        self.assertRegex(
            self.code, r"shallow_factor\s*=\s*coverage\s*\*\s*depth_factor"
        )
        self.assertRegex(self.code, r"contact\s*=\s*coverage\s*\*")

    def test_existing_wave_normals_and_wake_are_not_lost(self):
        """Protect wave displacement, normal mapping, and vessel wakes."""
        for symbol in (
            "swell_scale",
            "near_patch_half_extent",
            "swell_crest",
            "NORMAL = normalize",
            "vessel_forward",
            "wake_strength",
            "foam_amount",
            "NORMAL_MAP",
            "ROUGHNESS",
        ):
            with self.subTest(symbol=symbol):
                self.assertIn(symbol, self.code)
        self.assertRegex(
            self.code,
            r"VERTEX\.y\s*\+=\s*0\.18\s*\+\s*displacement\s*\*\s*envelope",
        )

    def test_mobile_normal_map_is_encoded_in_unsigned_tangent_space(self):
        """Prevent signed tangent normals from corrupting mobile water lighting."""
        self.assertRegex(
            self.code,
            r"NORMAL_MAP\s*=\s*normalize\s*\(\s*vec3\s*\(",
        )
        self.assertRegex(
            self.code,
            r"\)\s*\)\s*\*\s*0\.5\s*\+\s*0\.5\s*;",
        )

    def test_foam_is_bounded(self):
        """Keep the shoreline and wake foam blend within its existing limit."""
        self.assertRegex(
            self.code,
            r"foam\s*=\s*clamp\s*\(shore_foam\s*\+\s*wake\s*,\s*0\.0\s*,\s*0\.82\s*\)",
        )


if __name__ == "__main__":
    unittest.main()
