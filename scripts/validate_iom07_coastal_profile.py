#!/usr/bin/env python3
"""Validate a complete Godot coastal profile before removing partial diagnostics."""
import json
import math
import os
import sys
from pathlib import Path

INCOMPLETE = "INCOMPLETE_NOT_ACCEPTED.json"
GODOT_VERSION = "4.7.2-stable (official)"

def require(condition, message):
    if not condition:
        raise ValueError(message)

def validate_profile(path: Path, expected_sha: str):
    data = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(data, dict), "profile must be an object")
    require(data["exact_git_sha"] == expected_sha, "source SHA mismatch")
    require(data["source"] == "actual_godot_renderer", "not actual Godot evidence")
    require(data["godot"] == GODOT_VERSION, "Godot version mismatch")
    require(data["renderer"] == "mobile", "renderer mismatch")
    require(data["physical_android_measurement"] is False, "unverified Android claim")
    require(data["graphics_reference_parity"] == "NOT_VERIFIED", "unverified visual claim")
    require(data["device_thermal_memory_input_latency"] == "NOT_MEASURED", "unverified device claim")
    require(data["samples_each_phase"] == 30, "30 samples per phase required")
    require(data["same_camera_fixed_pose"] is True, "camera must be fixed")
    require(data["camera_mode"] == "cinematic_ship_framed_fixed_pose", "camera mode mismatch")
    distance = data["ship_motion_distance_units"]
    require(type(distance) in (int, float) and math.isfinite(distance) and distance > 0.2,
            "actual ship motion required")
    for phase in ("static", "moving"):
        stage = data[phase]
        require(isinstance(stage, dict), phase + " stage malformed")
        require(stage["valid"] is True, phase + " stage invalid")
        calls = stage["peak_draw_calls"]
        require(type(calls) is int and calls > 0,
                phase + " 3D draw calls missing")
        frame_report = stage["frame_interval_ms"]
        require(isinstance(frame_report, dict) and frame_report["valid"] is True and
                type(frame_report["samples"]) is int and frame_report["samples"] == 30,
                phase + " frame interval missing required samples")
        frame_values = [frame_report[key] for key in ("min_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms")]
        require(all(type(v) in (int, float) and math.isfinite(v) and v > 0 for v in frame_values)
                and frame_values == sorted(frame_values), phase + " frame interval quantiles invalid")
        cpu_report = stage.get("visual_update_cpu_wall_ms")
        if phase == "static":
            require(cpu_report is None and
                    stage.get("visual_update_cpu_wall_status") == "NOT_APPLICABLE_STATIC_PHASE",
                    "static phase must not fabricate visual-update CPU samples")
        else:
            require(stage.get("visual_update_cpu_wall_status") == "MEASURED" and
                    isinstance(cpu_report, dict) and cpu_report.get("valid") is True and
                    type(cpu_report.get("samples")) is int and cpu_report["samples"] == 30,
                    "moving visual-update CPU workload requires 30 samples")
            cpu_values = [cpu_report[key] for key in ("min_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms")]
            require(all(type(v) in (int, float) and math.isfinite(v) and v > 0 for v in cpu_values)
                    and cpu_values == sorted(cpu_values), "moving visual-update CPU quantiles invalid")
    return (data["static"]["frame_interval_ms"]["p95_ms"],
            data["moving"]["frame_interval_ms"]["p95_ms"])

def validate_and_finalize(path: Path, expected_sha: str):
    result = validate_profile(path, expected_sha)
    # Preserve checkpoint if profiling stopped, report is missing, or validation failed.
    marker = path.parent / INCOMPLETE
    marker.unlink(missing_ok=True)
    require(not marker.exists(), "incomplete marker cleanup failed")
    return result

def main():
    if len(sys.argv) != 2 or not os.environ.get("IOM_GIT_SHA"):
        print("Usage: IOM_GIT_SHA=<exact commit> validate_iom07_coastal_profile.py <report>",
              file=sys.stderr)
        return 2
    try:
        static, moving = validate_and_finalize(Path(sys.argv[1]), os.environ["IOM_GIT_SHA"])
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"Profile FAILED (diagnostics retained): {exc}", file=sys.stderr)
        return 1
    print(f"REAL GODOT LINUX COAST: static p95={static:.2f}ms, moving p95={moving:.2f}ms; Android metrics NOT MEASURED")
    return 0

if __name__ == "__main__":
    sys.exit(main())
