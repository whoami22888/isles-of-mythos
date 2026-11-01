#!/usr/bin/env python3
"""Conservative boundary continuity screen; never visual acceptance."""
import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from statistics import median
from typing import Dict, List, Optional, Tuple

Region = Tuple[int, int, int, int]


@dataclass(frozen=True)
class CaptureSpec:
    """Capture layout and lighting-screen configuration."""

    folder: Path
    frames: int = 72
    width: int = 1280
    height: int = 720
    segment_size: int = 24
    lighting_roi: Optional[Region] = None
    max_luma_jump: float = 5.0

    def validate(self) -> None:
        """Reject layouts that cannot produce meaningful boundary metrics."""
        invalid_geometry = (
            self.frames < 4
            or self.width <= 0
            or self.height <= 0
            or self.segment_size < 2
            or self.frames % self.segment_size != 0
        )
        if invalid_geometry:
            raise ValueError("invalid capture geometry/partition")
        if self.lighting_roi is None:
            return
        left, top, right, bottom = self.lighting_roi
        valid_roi = (
            0 <= left < right <= self.width
            and 0 <= top < bottom <= self.height
            and math.isfinite(self.max_luma_jump)
            and self.max_luma_jump > 0
        )
        if not valid_roi:
            raise ValueError("invalid lighting ROI or threshold")


def delta(first: bytes, second: bytes, stride: int = 4096) -> float:
    """Return a sparse mean RGB delta for two equally sized RGBA frames."""
    if len(first) != len(second) or not first:
        raise ValueError("inconsistent frame sizes")
    total = samples = 0
    for offset in range(0, len(first) - 2, stride):
        total += sum(
            abs(first[offset + channel] - second[offset + channel])
            for channel in range(3)
        )
        samples += 3
    return total / samples


def region_luma(frame: bytes, width: int, region: Region) -> float:
    """Sample a stable scene region so global sky/water cannot hide a lighting seam."""
    left, top, right, bottom = region
    total = samples = 0
    for y_coord in range(top, bottom, 4):
        for x_coord in range(left, right, 4):
            offset = (y_coord * width + x_coord) * 4
            total += (
                54 * frame[offset]
                + 183 * frame[offset + 1]
                + 19 * frame[offset + 2]
            ) / 256
            samples += 1
    return total / samples


def _read_frame_metrics(spec: CaptureSpec) -> Tuple[List[float], List[float]]:
    """Load the bounded frame set and calculate adjacent-frame metrics."""
    expected_size = spec.width * spec.height * 4
    deltas: List[float] = []
    lumas: List[float] = []
    previous: Optional[bytes] = None
    for index in range(spec.frames):
        path = spec.folder / f"frame_{index:04d}.rgba"
        if not path.is_file() or path.stat().st_size != expected_size:
            raise ValueError(f"missing or malformed frame {index}")
        current = path.read_bytes()
        if spec.lighting_roi is not None:
            lumas.append(region_luma(current, spec.width, spec.lighting_roi))
        if previous is not None:
            deltas.append(delta(previous, current))
        previous = current
    return deltas, lumas


def _lighting_boundaries(
    spec: CaptureSpec, boundaries: List[int], lumas: List[float]
) -> Dict[str, float]:
    """Build and validate luminance jumps at worker partition boundaries."""
    if spec.lighting_roi is None:
        return {}
    jumps = {
        f"{index}->{index + 1}": round(abs(lumas[index] - lumas[index + 1]), 3)
        for index in boundaries
    }
    if any(jump > spec.max_luma_jump for jump in jumps.values()):
        raise ValueError(
            "capture boundary lighting discontinuity "
            f"{jumps}; threshold={spec.max_luma_jump:.3f}"
        )
    return jumps


def verify(spec: CaptureSpec) -> Dict[str, object]:
    """Screen a complete capture for motion and lighting partition seams."""
    spec.validate()
    deltas, lumas = _read_frame_metrics(spec)
    boundaries = [
        index - 1 for index in range(spec.segment_size, spec.frames, spec.segment_size)
    ]
    baseline = median(
        value for index, value in enumerate(deltas) if index not in boundaries
    )
    threshold = max(15.0, baseline * 4.0)
    failures = [
        (index, deltas[index])
        for index in boundaries
        if deltas[index] > threshold
    ]
    if failures:
        raise ValueError(
            f"capture boundary discontinuity {failures}; threshold={threshold:.3f}"
        )
    lighting = _lighting_boundaries(spec, boundaries, lumas)
    return {
        "result": "PASS_SCREENING_NOT_VISUAL_ACCEPTANCE",
        "frames": spec.frames,
        "interior_median": round(baseline, 3),
        "threshold": round(threshold, 3),
        "boundaries": {
            f"{index}->{index + 1}": round(deltas[index], 3)
            for index in boundaries
        },
        "lighting_boundaries": lighting,
    }


def _parse_roi(raw_roi: Optional[str]) -> Optional[Region]:
    """Parse the CLI rectangle without accepting partial coordinates."""
    if raw_roi is None:
        return None
    values = tuple(map(int, raw_roi.split(",")))
    if len(values) != 4:
        raise ValueError("lighting ROI requires x0,y0,x1,y1")
    return values


def main() -> int:
    """Run the continuity screen from command-line arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    parser.add_argument("--frames", type=int, default=72)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--segment-size", type=int, default=24)
    parser.add_argument(
        "--lighting-roi",
        type=str,
        help="Stable-scene rectangle x0,y0,x1,y1 for boundary lighting checks",
    )
    parser.add_argument("--max-luma-jump", type=float, default=5.0)
    args = parser.parse_args()
    try:
        spec = CaptureSpec(
            folder=args.folder,
            frames=args.frames,
            width=args.width,
            height=args.height,
            segment_size=args.segment_size,
            lighting_roi=_parse_roi(args.lighting_roi),
            max_luma_jump=args.max_luma_jump,
        )
        print(json.dumps(verify(spec), sort_keys=True))
        return 0
    except ValueError as exc:
        print(f"CAPTURE_CONTINUITY_FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
