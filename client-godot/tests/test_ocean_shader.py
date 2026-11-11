"""Prompt 006: non-rendering regression guard for the existing mobile ocean.

These tests protect existing shader contracts while a real Godot 4.7.2
Mobile-rendered visual and Android acceptance suite is developed.
They are NOT shader compilation or visual-quality evidence.
"""
from pathlib import Path
import re
import unittest

SHADER = Path(__file__).resolve().parents[1] / "shaders" / "ocean_surface.gdshader"


class OceanShaderContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SHADER.read_text(encoding="utf-8")
        cls.code = re.sub(r"/\*.*?\*/|//[^\n]*", "", cls.source, flags=re.S)

    def test_mobile_opaque_depth_path_is_preserved(self):
        self.assertRegex(self.code, r"render_mode\s+cull_back\s*,\s*depth_draw_opaque\s*;")
        self.assertNotRegex(self.code, r"\bALPHA\s*=")

    def test_deterministic_capture_controls_both_stages(self):
        self.assertIn("uniform bool deterministic_capture", self.code)
        self.assertIn("uniform float capture_time_seconds", self.code)
        self.assertEqual(
            len(re.findall(r"deterministic_capture\s*\?\s*capture_time_seconds\s*:\s*TIME", self.code)),
            2,
        )

    def test_terrain_derived_shoreline_and_unbound_guard(self):
        self.assertIn('#include "res://shaders/coastal_shore_sampler.gdshaderinc"', self.code)
        self.assertRegex(self.code, r"shore_terrain_coverage\s*\(p\)\s*\*\s*float\s*\(shoremap_bound\)")
        self.assertRegex(self.code, r"shore_terrain_height\s*\(p\)")
        self.assertRegex(self.code, r"shallow_factor\s*=\s*coverage\s*\*\s*depth_factor")
        self.assertRegex(self.code, r"contact\s*=\s*coverage\s*\*")

    def test_existing_wave_normals_and_wake_are_not_lost(self):
        for symbol in ("swell_scale", "near_patch_half_extent", "swell_crest",
                       "NORMAL = normalize", "vessel_forward", "wake_strength",
                       "foam_amount", "NORMAL_MAP", "ROUGHNESS"):
            with self.subTest(symbol=symbol):
                self.assertIn(symbol, self.code)
        self.assertRegex(self.code, r"VERTEX\.y\s*\+=\s*0\.18\s*\+\s*displacement\s*\*\s*envelope")

    def test_foam_is_bounded(self):
        self.assertRegex(self.code, r"foam\s*=\s*clamp\s*\(shore_foam\s*\+\s*wake\s*,\s*0\.0\s*,\s*0\.82\s*\)")


if __name__ == "__main__":
    unittest.main()
