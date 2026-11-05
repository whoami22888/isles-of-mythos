#!/usr/bin/env python3
"""Negative regressions for typed frame-evidence acceptance."""
import copy
import unittest

from scripts.validate_iom07_frame_evidence import GODOT_VERSION, validate

SHA = "a" * 40


def fixture():
    metric = {"valid": True, "samples": 180, "p50_ms": 16.0, "p95_ms": 18.0,
              "p99_ms": 20.0, "max_ms": 22.0}
    return {"source": "actual_godot_scene", "commit_sha": SHA,
            "godot_version": GODOT_VERSION, "renderer": "gl_compatibility",
            "physical_android_measurement": False, "graphics_quality_verdict": "NOT_VERIFIED",
            "mobile_acceptance_verdict": "NOT_VERIFIED", "peak_3d_draw_calls": 12,
            "frame_interval_ms": copy.deepcopy(metric), "engine_process_ms": copy.deepcopy(metric),
            "engine_process_clock_check": {"comparable": True, "reason": "CONSISTENT"}}


class FrameEvidenceValidation(unittest.TestCase):
    def test_valid_exact_report(self):
        validate(fixture(), SHA)

    def test_draw_calls_reject_bool_zero_negative_malformed_and_missing(self):
        for value in (True, False, 0, -1, "12", None, 12.5):
            with self.subTest(value=value):
                report = fixture()
                report["peak_3d_draw_calls"] = value
                with self.assertRaises(ValueError):
                    validate(report, SHA)
        report = fixture()
        del report["peak_3d_draw_calls"]
        with self.assertRaises(ValueError):
            validate(report, SHA)

    def test_engine_version_requires_exact_pinned_build(self):
        for value in ("4.7.20-stable (official)", "4.7.2-stable (custom)",
                      "4.7.2", "4.7.2.stable.official.ed1daf0bf"):
            with self.subTest(value=value):
                report = fixture()
                report["godot_version"] = value
                with self.assertRaises(ValueError):
                    validate(report, SHA)

    def test_boolean_quantile_and_sample_count_are_rejected(self):
        report = fixture()
        report["frame_interval_ms"]["p95_ms"] = True
        with self.assertRaises(ValueError):
            validate(report, SHA)
        report = fixture()
        report["engine_process_ms"]["samples"] = True
        with self.assertRaises(ValueError):
            validate(report, SHA)

    def test_nan_and_stale_sha_are_rejected(self):
        report = fixture()
        report["frame_interval_ms"]["p95_ms"] = float("nan")
        with self.assertRaises(ValueError):
            validate(report, SHA)
        with self.assertRaises(ValueError):
            validate(fixture(), "b" * 40)


if __name__ == "__main__":
    unittest.main()
