#!/usr/bin/env python3
"""Fail-closed structural checks for Godot visual capture evidence.

This verifies bytes and capture metadata. It NEVER certifies artistic parity,
engine authenticity, licensing, or physical Android performance.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import subprocess
import sys
import zlib
from urllib.parse import urlparse

MASTER_SHA256 = "713cd6e90c6f7d589a06eb3bd4b9b2d5ebeb9c0ff711b5de527a68460dfbcb05"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
MAX_BYTES = 512 * 1024 * 1024


class EvidenceError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def evidence_file(root: Path, value: str) -> Path:
    require(isinstance(value, str) and value and "\\" not in value and "\x00" not in value,
            "invalid evidence path")
    path = PurePosixPath(value)
    require(not path.is_absolute() and all(part not in (".", "..") for part in value.split("/")),
            "unsafe evidence path")
    target = root / value
    require(target.resolve().is_relative_to(root.resolve()), "path escapes evidence bundle")
    current = target
    while current != root:
        require(not current.is_symlink(), "symlink in evidence path")
        current = current.parent
    require(target.is_file(), f"missing evidence file: {value}")
    require(0 < target.stat().st_size <= MAX_BYTES, f"invalid file size: {value}")
    return target


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check_png(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        require(stream.read(8) == PNG_MAGIC, "invalid PNG signature")
        width = height = channels = 0
        seen_ihdr = seen_idat = seen_iend = False
        compressed = bytearray()
        while True:
            header = stream.read(8)
            require(len(header) == 8, "truncated PNG chunk header")
            size, kind = struct.unpack(">I4s", header)
            require(size <= MAX_BYTES, "oversized PNG chunk")
            payload = stream.read(size)
            crc_bytes = stream.read(4)
            require(len(payload) == size and len(crc_bytes) == 4, "truncated PNG chunk")
            actual_crc = zlib.crc32(kind + payload) & 0xffffffff
            require(actual_crc == struct.unpack(">I", crc_bytes)[0], "PNG CRC mismatch")
            if kind == b"IHDR":
                require(not seen_ihdr and size == 13, "invalid PNG IHDR")
                width, height = struct.unpack(">II", payload[:8])
                depth, color_type, compression, filtering, interlace = payload[8:]
                require(depth == 8 and color_type in (2, 6) and compression == 0
                        and filtering == 0 and interlace == 0, "unsupported PNG format")
                channels = 3 if color_type == 2 else 4
                require(640 <= width <= 8192 and 360 <= height <= 8192,
                        "PNG dimensions below capture minimum or implausible")
                seen_ihdr = True
            elif kind == b"IDAT":
                require(seen_ihdr, "PNG IDAT before IHDR")
                seen_idat = True
                compressed.extend(payload)
            elif kind == b"IEND":
                require(size == 0 and seen_idat and seen_ihdr, "incomplete PNG")
                seen_iend = True
                break
        require(seen_iend and not stream.read(1), "PNG trailing data")
    expected_length = height * (1 + width * channels)
    try:
        decoder = zlib.decompressobj()
        raw = decoder.decompress(bytes(compressed), expected_length + 1)
        require(decoder.eof and not decoder.unused_data and len(raw) == expected_length,
                "invalid or incomplete PNG pixel data")
        stride = 1 + width * channels
        require(all(raw[offset] <= 4 for offset in range(0, len(raw), stride)),
                "invalid PNG row filter")
    except zlib.error as exc:
        raise EvidenceError(f"corrupt PNG pixel data: {exc}") from exc
    return width, height


def check_mp4(path: Path) -> tuple[int, int, float]:
    ffprobe = shutil.which("ffprobe")
    require(ffprobe is not None, "ffprobe unavailable: cannot verify MP4")
    try:
        proc = subprocess.run([ffprobe, "-v", "error", "-select_streams", "v:0",
                               "-show_entries", "stream=codec_name,width,height,nb_frames,duration",
                               "-show_entries", "format=duration", "-of", "json", str(path)],
                              check=True, capture_output=True, text=True, timeout=20)
        result = json.loads(proc.stdout)
        video = result["streams"][0]
        width, height = int(video["width"]), int(video["height"])
        duration = float(video.get("duration") or result["format"]["duration"])
        require(video["codec_name"] in {"h264", "hevc", "av1", "vp9"}, "unsupported MP4 video codec")
        require(640 <= width <= 8192 and 360 <= height <= 8192 and duration >= 0.5,
                "MP4 dimensions or duration insufficient")
        if video.get("nb_frames") not in (None, "N/A"):
            require(int(video["nb_frames"]) >= 12, "MP4 has too few frames")
        return width, height, duration
    except (OSError, subprocess.SubprocessError, KeyError, ValueError, IndexError) as exc:
        raise EvidenceError(f"unverifiable MP4: {exc}") from exc


def verify(root: Path, manifest_path: Path, expected_sha: str) -> dict:
    require(bool(HEX40.fullmatch(expected_sha)), "expected commit must be full lowercase SHA")
    require(manifest_path.is_file() and not manifest_path.is_symlink(), "manifest missing or symlink")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise EvidenceError(f"invalid manifest: {exc}") from exc
    require(isinstance(manifest, dict) and manifest.get("schema_version") == 1,
            "invalid manifest schema")
    require(manifest.get("commit_sha") == expected_sha, "capture commit does not match exact HEAD")
    require(manifest.get("reference_sha256") == MASTER_SHA256, "wrong owner reference digest")
    version = manifest.get("godot_version")
    require(isinstance(version, str) and re.match(r"^4\.7\.2(?:\.|$)", version) is not None,
            "Godot version is not 4.7.2")
    require(manifest.get("renderer") in ("mobile", "gl_compatibility", "gl_compatibility_3d"),
            "unsupported or unspecified renderer")
    scene = manifest.get("scene")
    require(isinstance(scene, str) and scene.startswith("res://") and scene.endswith(".tscn")
            and ".." not in scene, "missing or unsafe scene provenance")
    run_url = manifest.get("capture_run_url")
    parsed = urlparse(run_url) if isinstance(run_url, str) else None
    require(parsed is not None and parsed.scheme == "https" and parsed.netloc == "github.com"
            and re.fullmatch(r"/whoami22888/isles-of-mythos/actions/runs/[0-9]+", parsed.path),
            "missing GitHub capture-run provenance")
    require(manifest.get("capture_method") == "godot-engine", "not declared as engine capture")
    motion = manifest.get("motion_required")
    require(isinstance(motion, bool), "motion_required must be boolean")
    assets = manifest.get("source_assets")
    require(isinstance(assets, list), "source_assets must be explicit, even if empty")
    captures = manifest.get("captures")
    require(isinstance(captures, list) and captures, "missing capture artifacts")
    seen = set()
    frame_records = []
    mp4_count = 0
    dimensions = set()
    for is_capture, records in ((False, assets), (True, captures)):
        for record in records:
            require(isinstance(record, dict), "invalid evidence record")
            name, expected = record.get("path"), record.get("sha256")
            require(isinstance(name, str) and name not in seen, "duplicate or invalid file path")
            seen.add(name)
            require(isinstance(expected, str) and bool(HEX64.fullmatch(expected)), "missing SHA256")
            target = evidence_file(root, name)
            require(sha256(target) == expected, f"SHA256 mismatch: {name}")
            if is_capture:
                suffix = target.suffix.lower()
                require(suffix in (".png", ".mp4"), "capture must be PNG or MP4")
                if suffix == ".png":
                    dimensions.add(check_png(target))
                    timestamp = record.get("timestamp_ms")
                    require(isinstance(timestamp, int) and timestamp >= 0, "missing frame timestamp")
                    frame_records.append((timestamp, expected))
                else:
                    width, height, duration = check_mp4(target)
                    dimensions.add((width, height))
                    mp4_count += 1
    require(len(dimensions) == 1, "capture dimensions inconsistent")
    if motion and mp4_count == 0:
        require(len(frame_records) >= 12, "motion requires MP4 or >=12 actual frames")
        times = [t for t, _ in frame_records]
        require(times == sorted(set(times)), "frame timestamps not strictly increasing")
        require(times[-1] - times[0] >= 500, "motion frames cover less than 500 ms")
        require(all(0 < b-a <= 250 for a, b in zip(times, times[1:])),
                "frame sequence has gaps or duplicate timestamps")
        require(len({h for _, h in frame_records}) >= 3, "motion frames appear static")
    return {"result": "STRUCTURAL_EVIDENCE_VERIFIED_ONLY", "commit_sha": expected_sha,
            "captures": len(captures), "source_assets": len(assets), "motion_required": motion,
            "visual_parity": "NOT_ASSESSED", "engine_authenticity": "NOT_INDEPENDENTLY_PROVEN",
            "physical_android_performance": "NOT_ASSESSED"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path, help="directory containing captured files")
    parser.add_argument("manifest", type=Path, help="JSON manifest")
    parser.add_argument("--commit", required=True, help="exact 40-hex GitHub PR HEAD")
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.bundle.resolve(), args.manifest, args.commit), sort_keys=True))
        return 0
    except EvidenceError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
