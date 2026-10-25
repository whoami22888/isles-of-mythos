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

def verify(folder: Path, frames: int = 72, width: int = 1280, height: int = 720, segment_size: int = 24) -> dict:
    if frames < 4 or width <= 0 or height <= 0 or segment_size < 2 or frames % segment_size:
        raise ValueError("invalid capture geometry/partition")
    expected = width * height * 4
    deltas = []
    previous = None
    for i in range(frames):
        path = folder / f"frame_{i:04d}.rgba"
        if not path.is_file() or path.stat().st_size != expected:
            raise ValueError(f"missing or malformed frame {i}")
        current = path.read_bytes()
        if previous is not None:
            deltas.append(delta(previous, current))
        previous = current
    boundaries = [i - 1 for i in range(segment_size, frames, segment_size)]
    baseline = median(d for i, d in enumerate(deltas) if i not in boundaries)
    threshold = max(15.0, baseline * 4.0)
    failures = [(i, deltas[i]) for i in boundaries if deltas[i] > threshold]
    if failures:
        raise ValueError(f"capture boundary discontinuity {failures}; threshold={threshold:.3f}")
    return {"result": "PASS_SCREENING_NOT_VISUAL_ACCEPTANCE", "frames": frames,
            "interior_median": round(baseline, 3), "threshold": round(threshold, 3),
            "boundaries": {f"{i}->{i+1}": round(deltas[i], 3) for i in boundaries}}

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    parser.add_argument("--frames", type=int, default=72)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--segment-size", type=int, default=24)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.folder, args.frames, args.width, args.height, args.segment_size), sort_keys=True))
        return 0
    except ValueError as exc:
        parser.exit(1, f"CAPTURE_CONTINUITY_FAIL: {exc}\n")

if __name__ == "__main__":
    raise SystemExit(main())
