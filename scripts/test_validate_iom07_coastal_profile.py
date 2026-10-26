#!/usr/bin/env python3
"""Regression tests: completed profiles clean up; failed profiles retain diagnostics."""
import copy
import json
import tempfile
import unittest
from pathlib import Path

from validate_iom07_coastal_profile import GODOT_VERSION, INCOMPLETE, validate_and_finalize

SHA = "a" * 40

def fixture():
    stats = {"valid": True, "samples": 30, "min_ms": 1.0, "p50_ms": 2.0,
             "p95_ms": 3.0, "p99_ms": 4.0, "max_ms": 5.0}
    static = {"valid": True, "peak_draw_calls": 12, "frame_interval_ms": copy.deepcopy(stats),
              "visual_update_cpu_wall_ms": None,
              "visual_update_cpu_wall_status": "NOT_APPLICABLE_STATIC_PHASE"}
    moving = {"valid": True, "peak_draw_calls": 12, "frame_interval_ms": copy.deepcopy(stats),
              "visual_update_cpu_wall_ms": copy.deepcopy(stats),
              "visual_update_cpu_wall_status": "MEASURED"}
    return {"exact_git_sha": SHA, "source": "actual_godot_renderer", "godot": GODOT_VERSION,
            "renderer": "mobile", "physical_android_measurement": False,
            "graphics_reference_parity": "NOT_VERIFIED",
            "device_thermal_memory_input_latency": "NOT_MEASURED",
            "samples_each_phase": 30, "same_camera_fixed_pose": True,
            "camera_mode": "cinematic_ship_framed_fixed_pose",
            "ship_motion_distance_units": 1.0,
            "static": static, "moving": moving}

class ProfileLifecycleRegression(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.report = Path(self.temp.name) / "moving-coastal-profile.json"
        self.diagnostic = self.report.parent / INCOMPLETE
        self.diagnostic.write_text('{"status":"INCOMPLETE_DIAGNOSTIC_ONLY","phase":"moving"}')

    def store(self, data):
        self.report.write_text(json.dumps(data))

    def test_valid_complete_report_clears_obsolete_marker(self):
        self.store(fixture())
        self.assertEqual(validate_and_finalize(self.report, SHA), (3.0, 3.0))
        self.assertFalse(self.diagnostic.exists())
        self.assertTrue(self.report.exists())

    def test_valid_report_without_checkpoint_is_allowed(self):
        self.diagnostic.unlink()
        self.store(fixture())
        self.assertEqual(validate_and_finalize(self.report, SHA), (3.0, 3.0))

    def test_static_phase_does_not_fabricate_cpu_update_samples(self):
        data = fixture()
        self.assertIsNone(data["static"]["visual_update_cpu_wall_ms"])
        self.assertEqual(data["static"]["visual_update_cpu_wall_status"],
                         "NOT_APPLICABLE_STATIC_PHASE")
        self.assertEqual(data["moving"]["visual_update_cpu_wall_ms"]["samples"], 30)
        self.store(data)
        self.assertEqual(validate_and_finalize(self.report, SHA), (3.0, 3.0))

    def test_static_phase_rejects_fabricated_cpu_update_samples(self):
        data = fixture()
        data["static"]["visual_update_cpu_wall_ms"] = copy.deepcopy(
            data["moving"]["visual_update_cpu_wall_ms"])
        self.store(data)
        with self.assertRaises(ValueError):
            validate_and_finalize(self.report, SHA)
        self.assertTrue(self.diagnostic.exists())

    def test_static_phase_requires_explicit_not_applicable_value(self):
        data = fixture()
        del data["static"]["visual_update_cpu_wall_ms"]
        self.store(data)
        with self.assertRaises(ValueError):
            validate_and_finalize(self.report, SHA)
        self.assertTrue(self.diagnostic.exists())

    def test_missing_full_report_keeps_checkpoint(self):
        with self.assertRaises(OSError):
            validate_and_finalize(self.report, SHA)
        self.assertTrue(self.diagnostic.exists())

    def test_malformed_full_report_keeps_checkpoint(self):
        self.report.write_text("{invalid")
        with self.assertRaises(ValueError):
            validate_and_finalize(self.report, SHA)
        self.assertTrue(self.diagnostic.exists())

    def test_incomplete_samples_keeps_checkpoint(self):
        data = fixture()
        data["moving"]["frame_interval_ms"]["samples"] = 29
        self.store(data)
        with self.assertRaises(ValueError):
            validate_and_finalize(self.report, SHA)
        self.assertTrue(self.diagnostic.exists())

    def test_wrong_sha_keeps_checkpoint(self):
        self.store(fixture())
        with self.assertRaises(ValueError):
            validate_and_finalize(self.report, "b" * 40)
        self.assertTrue(self.diagnostic.exists())

    def test_unrendered_scene_keeps_checkpoint(self):
        data = fixture()
        data["static"]["peak_draw_calls"] = 0
        self.store(data)
        with self.assertRaises(ValueError):
            validate_and_finalize(self.report, SHA)
        self.assertTrue(self.diagnostic.exists())

    def test_spoofed_visual_parity_keeps_checkpoint(self):
        data = fixture()
        data["graphics_reference_parity"] = "PASS"
        self.store(data)
        with self.assertRaises(ValueError):
            validate_and_finalize(self.report, SHA)
        self.assertTrue(self.diagnostic.exists())

    def test_nonfinite_quantile_keeps_checkpoint(self):
        data = fixture()
        data["moving"]["frame_interval_ms"]["p95_ms"] = float("nan")
        self.store(data)
        with self.assertRaises(ValueError):
            validate_and_finalize(self.report, SHA)
        self.assertTrue(self.diagnostic.exists())

    def test_camera_mismatch_keeps_checkpoint(self):
        data = fixture()
        data["same_camera_fixed_pose"] = False
        self.store(data)
        with self.assertRaises(ValueError):
            validate_and_finalize(self.report, SHA)
        self.assertTrue(self.diagnostic.exists())

    def test_boolean_numeric_values_are_rejected(self):
        for phase, field, value in (("static", "peak_draw_calls", True),
                                    ("moving", "peak_draw_calls", False),
                                    ("static", "ship_motion_distance_units", True),
                                    ("moving", "ship_motion_distance_units", False),
                                    ("moving", "p95_ms", True)):
            with self.subTest(phase=phase, field=field):
                data = fixture()
                if field == "ship_motion_distance_units":
                    data[field] = value
                elif field == "p95_ms":
                    data[phase]["frame_interval_ms"][field] = value
                else:
                    data[phase][field] = value
                self.store(data)
                with self.assertRaises(ValueError):
                    validate_and_finalize(self.report, SHA)
                self.assertTrue(self.diagnostic.exists())

    def test_engine_version_must_match_exact_pinned_build(self):
        for version in ("4.7.20-stable (official)", "4.7.2-stable (custom)",
                        "4.7.2", "4.7.2.stable.official.ed1daf0bf"):
            with self.subTest(version=version):
                data = fixture()
                data["godot"] = version
                self.store(data)
                with self.assertRaises(ValueError):
                    validate_and_finalize(self.report, SHA)
                self.assertTrue(self.diagnostic.exists())

    def test_malformed_nested_values_keep_checkpoint(self):
        for key, value in (("static", None), ("moving", "bad")):
            with self.subTest(key=key):
                data = fixture()
                data[key] = value
                self.store(data)
                with self.assertRaises((ValueError, TypeError)):
                    validate_and_finalize(self.report, SHA)
                self.assertTrue(self.diagnostic.exists())

if __name__ == "__main__":
    unittest.main()
