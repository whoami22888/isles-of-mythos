#!/usr/bin/env python3
"""Fail-closed validation for the Linux Godot IOM-07 frame evidence."""
import json
import math
import re
import sys
from pathlib import Path

GODOT_VERSION = "4.7.2.stable.official.ed1daf0bf"


def positive_number(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def validate(data, expected_sha):
    require(isinstance(data, dict), "evidence must be an object")
    require(data.get("source") == "actual_godot_scene", "not actual Godot scene evidence")
    require(data.get("commit_sha") == expected_sha and re.fullmatch(r"[0-9a-f]{40}", expected_sha), "source SHA mismatch")
    require(data.get("godot_version") == GODOT_VERSION, "Godot version mismatch")
    require(data.get("renderer") == "gl_compatibility", "renderer mismatch")
    require(data.get("physical_android_measurement") is False, "unverified Android claim")
    require(data.get("graphics_quality_verdict") == "NOT_VERIFIED", "unverified graphics claim")
    require(data.get("mobile_acceptance_verdict") == "NOT_VERIFIED", "unverified mobile claim")
    require(type(data.get("peak_3d_draw_calls")) is int and data["peak_3d_draw_calls"] > 0,
            "positive numeric 3D draw-call evidence required")
    for metric_name in ("frame_interval_ms", "engine_process_ms"):
        metric = data.get(metric_name)
        require(isinstance(metric, dict), metric_name + " must be an object")
        require(metric.get("valid") is True and type(metric.get("samples")) is int and metric["samples"] == 180,
                metric_name + " requires 180 valid samples")
        values = [metric.get(key) for key in ("p50_ms", "p95_ms", "p99_ms", "max_ms")]
        require(all(positive_number(value) for value in values) and values == sorted(values),
                metric_name + " quantiles are malformed")
    clock_check = data.get("engine_process_clock_check")
    require(isinstance(clock_check, dict) and type(clock_check.get("comparable")) is bool and
            clock_check.get("reason") in ("CONSISTENT", "PROCESS_MONITOR_CLOCK_DIVERGENCE"),
            "engine/process clock comparison is malformed")
    return clock_check["comparable"]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    if len(sys.argv) != 3:
        print("Usage: validate_iom07_frame_evidence.py <report> <expected-sha>", file=sys.stderr)
        return 2
    try:
        clock_comparable = validate(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")), sys.argv[2])
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
        print(f"Frame evidence FAILED: {exc}", file=sys.stderr)
        return 1
    if not clock_comparable:
        print("WARNING: process monitor differs from frame clock; do not infer a CPU bottleneck.")
    print("Verified Godot frame evidence schema and exact source commit; Android quality remains NOT VERIFIED.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
