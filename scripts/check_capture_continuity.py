#!/usr/bin/env python3
"""Conservative boundary continuity screen; never visual acceptance."""
import argparse
import json
from pathlib import Path
from statistics import median

def delta(a: bytes, b: bytes, stride: int = 4096) -> float:
    if len(a) != len(b) or not a:
        raise ValueError("inconsistent frame sizes")
    total = samples = 0
    for offset in range(0, len(a) - 2, stride):
        total += sum(abs(a[offset + channel] - b[offset + channel]) for channel in range(3))
        samples += 3
    return total / samples

def region_luma(frame: bytes, width: int, region: tuple[int, int, int, int]) -> float:
    """Sample a stable scene region so global sky/water cannot hide a lighting seam."""
    left, top, right, bottom = region
    total = samples = 0
    for y in range(top, bottom, 4):
        for x in range(left, right, 4):
            offset = (y * width + x) * 4
            total += (54 * frame[offset] + 183 * frame[offset + 1] + 19 * frame[offset + 2]) / 256
            samples += 1
    return total / samples


def verify(folder: Path, frames: int = 72, width: int = 1280, height: int = 720,
           segment_size: int = 24, lighting_roi: tuple[int, int, int, int] | None = None,
           max_luma_jump: float = 5.0) -> dict:
    if frames < 4 or width <= 0 or height <= 0 or segment_size < 2 or frames % segment_size:
        raise ValueError("invalid capture geometry/partition")
    if lighting_roi is not None:
        left, top, right, bottom = lighting_roi
        if not (0 <= left < right <= width and 0 <= top < bottom <= height and max_luma_jump > 0):
            raise ValueError("invalid lighting ROI or threshold")
    expected = width * height * 4
    deltas = []
    lumas = []
    previous = None
    for i in range(frames):
        path = folder / f"frame_{i:04d}.rgba"
        if not path.is_file() or path.stat().st_size != expected:
            raise ValueError(f"missing or malformed frame {i}")
        current = path.read_bytes()
        if lighting_roi is not None:
            lumas.append(region_luma(current, width, lighting_roi))
        if previous is not None:
            deltas.append(delta(previous, current))
        previous = current
    boundaries = [i - 1 for i in range(segment_size, frames, segment_size)]
    baseline = median(d for i, d in enumerate(deltas) if i not in boundaries)
    threshold = max(15.0, baseline * 4.0)
    failures = [(i, deltas[i]) for i in boundaries if deltas[i] > threshold]
    if failures:
        raise ValueError(f"capture boundary discontinuity {failures}; threshold={threshold:.3f}")
    luma_boundaries = {f"{i}->{i+1}": round(abs(lumas[i] - lumas[i+1]), 3)
                       for i in boundaries} if lighting_roi is not None else {}
    if any(jump > max_luma_jump for jump in luma_boundaries.values()):
        raise ValueError(f"capture boundary lighting discontinuity {luma_boundaries}; threshold={max_luma_jump:.3f}")
    return {"result": "PASS_SCREENING_NOT_VISUAL_ACCEPTANCE", "frames": frames,
            "interior_median": round(baseline, 3), "threshold": round(threshold, 3),
            "boundaries": {f"{i}->{i+1}": round(deltas[i], 3) for i in boundaries},
            "lighting_boundaries": luma_boundaries}

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    parser.add_argument("--frames", type=int, default=72)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--segment-size", type=int, default=24)
    parser.add_argument("--lighting-roi", type=str,
                        help="Stable-scene rectangle x0,y0,x1,y1 for boundary lighting checks")
    parser.add_argument("--max-luma-jump", type=float, default=5.0)
    args = parser.parse_args()
    try:
        roi = tuple(map(int, args.lighting_roi.split(","))) if args.lighting_roi else None
        if roi is not None and len(roi) != 4:
            raise ValueError("lighting ROI requires x0,y0,x1,y1")
        print(json.dumps(verify(args.folder, args.frames, args.width, args.height,
                                args.segment_size, roi, args.max_luma_jump), sort_keys=True))
        return 0
    except ValueError as exc:
        parser.exit(1, f"CAPTURE_CONTINUITY_FAIL: {exc}\n")

if __name__ == "__main__":
    raise SystemExit(main())
