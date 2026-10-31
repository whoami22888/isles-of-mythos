#!/usr/bin/env python3
"""Validate rendered ship pixel occupancy from the four Godot camera beats."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

FRAMES = (0, 24, 48, 71)
PIXEL_COUNT = 1280 * 720


def read_samples(root: Path) -> tuple[dict[int, dict], dict[int, str]]:
    samples: dict[int, dict] = {}
    frame_hashes: dict[int, str] = {}
    for frame in FRAMES:
        segment = frame // 24
        directory = root / f"internal-coastal-frames-{segment}"
        sample_path = directory / f"ship-occupancy-frame-{frame:04d}.json"
        frame_path = directory / f"frame_{frame:04d}.rgba"
        manifest_path = directory / "SHA256SUMS"
        if not sample_path.is_file() or not frame_path.is_file() or not manifest_path.is_file():
            raise ValueError(f"Missing occupancy evidence for frame {frame}")
        sample = json.loads(sample_path.read_text(encoding="utf-8"))
        digest = hashlib.sha256(frame_path.read_bytes()).hexdigest()
        manifest = dict(
            (line.split("  ", 1)[1], line.split("  ", 1)[0])
            for line in manifest_path.read_text(encoding="utf-8").splitlines()
            if "  " in line
        )
        if manifest.get(frame_path.name) != digest:
            raise ValueError(f"Frame {frame} does not match its worker SHA256SUMS")
        if sample.get("composite_frame_sha256") != digest:
            raise ValueError(f"Frame {frame} occupancy is not bound to its composite frame")
        samples[frame] = sample
        frame_hashes[frame] = digest
    return samples, frame_hashes


def validate_samples(samples: dict[int, dict]) -> list[str]:
    errors: list[str] = []
    if set(samples) != set(FRAMES):
        return ["Expected exactly the wide, two approach and detail frame samples"]
    for frame in FRAMES:
        sample = samples[frame]
        if sample.get("frame") != frame:
            errors.append(f"Occupancy frame label mismatch at {frame}")
        for count_key, fraction_key in (
            ("hull_pixels", "hull_fraction"),
            ("sail_pixels", "sail_fraction"),
            ("ship_pixels", "ship_fraction"),
        ):
            count = sample.get(count_key)
            fraction = sample.get(fraction_key)
            if not isinstance(count, int) or count <= 0 or not isinstance(fraction, (int, float)):
                errors.append(f"No visible {count_key.removesuffix('_pixels')} pixels at frame {frame}")
                continue
            if abs(float(fraction) - count / PIXEL_COUNT) > 1.0 / PIXEL_COUNT:
                errors.append(f"Pixel fraction does not match {count_key} at frame {frame}")
        for digest_key in ("composite_frame_sha256", "mask_frame_sha256"):
            digest = sample.get(digest_key)
            if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
                errors.append(f"Frame {frame} occupancy lacks valid {digest_key} binding")

    wide, approach, late_approach, detail = (samples[frame] for frame in FRAMES)
    if wide.get("hull_fraction", 0.0) < 0.003 or wide.get("sail_fraction", 0.0) < 0.005:
        errors.append("Wide shot hull/sail pixel occupancy is below the minimum visible threshold")
    if approach.get("ship_fraction", 0.0) <= wide.get("ship_fraction", 0.0):
        errors.append("Approach shot does not increase rendered ship pixel occupancy")
    if detail.get("ship_fraction", 0.0) <= late_approach.get("ship_fraction", 0.0):
        errors.append("Detail shot does not increase rendered ship pixel occupancy")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path, help="Root containing the four internal-coastal-frames-N folders")
    args = parser.parse_args()
    try:
        samples, hashes = read_samples(args.root)
        errors = validate_samples(samples)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"FAIL ship pixel occupancy: {error}")
        return 1
    if errors:
        for error in errors:
            print(f"FAIL ship pixel occupancy: {error}")
        return 1
    report = {
        "status": "PASS_SCREENING_NOT_VISUAL_ACCEPTANCE",
        "frames": [
            {
                "frame": frame,
                "hull_fraction": samples[frame]["hull_fraction"],
                "sail_fraction": samples[frame]["sail_fraction"],
                "ship_fraction": samples[frame]["ship_fraction"],
                "composite_sha256": hashes[frame],
            }
            for frame in FRAMES
        ],
    }
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
