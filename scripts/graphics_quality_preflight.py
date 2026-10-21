#!/usr/bin/env python3
"""Cheap fail-closed preflight for expensive Godot visual captures.

This is an evidence-presence screen, not artistic acceptance.  A capture may
only start after a reviewer-supplied, hash-pinned test slide is available for
the exact source SHA and the owner's reference digest is recorded.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

REFERENCE_SHA256 = "713cd6e90c6f7d589a06eb3bd4b9b2d5ebeb9c0ff711b5de527a68460dfbcb05"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError("test slide must be a PNG with an IHDR header")
    return struct.unpack(">II", header[16:24])


def validate(manifest_path: Path, source_sha: str, client_root: Path) -> list[str]:
    errors: list[str] = []
    if not manifest_path.is_file():
        return [
            f"quality test slide manifest is missing: {manifest_path}",
            "refusing to install Godot or render captures until a reviewed slide is supplied",
        ]
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"quality test slide manifest is unreadable: {exc}"]
    if not isinstance(manifest, dict):
        return ["quality test slide manifest must be a JSON object"]
    required = ("image", "sha256", "source_sha", "reference_sha256", "review_status")
    for key in required:
        if not isinstance(manifest.get(key), str) or not manifest[key].strip():
            errors.append(f"manifest field {key!r} is required")
    if errors:
        return errors
    if manifest["source_sha"] != source_sha:
        errors.append(f"slide source_sha {manifest['source_sha']} does not match checked SHA {source_sha}")
    if manifest["reference_sha256"] != REFERENCE_SHA256:
        errors.append("slide reference_sha256 does not match the pinned owner reference")
    if manifest["review_status"].lower() not in {"reviewed", "pass-preflight"}:
        errors.append("slide review_status must be reviewed or pass-preflight")
    image = (manifest_path.parent / manifest["image"]).resolve()
    if not image.is_relative_to(client_root.resolve().parent):
        errors.append("test slide image escapes the repository workspace")
    elif not image.is_file():
        errors.append(f"test slide image is missing: {image}")
    else:
        try:
            width, height = _png_size(image)
            if width < 320 or height < 180:
                errors.append(f"test slide is too small ({width}x{height}); minimum is 320x180")
            if _sha256(image) != manifest["sha256"]:
                errors.append("test slide sha256 does not match manifest")
        except (OSError, ValueError) as exc:
            errors.append(f"test slide is invalid: {exc}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path("docs/graphics/quality-test-slide.json"))
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--client", type=Path, default=Path("client-godot"))
    args = parser.parse_args()
    errors = validate(args.manifest, args.source_sha, args.client)
    if errors:
        for error in errors:
            print(f"::error::{error}")
        print("QUALITY_SLIDE_PREFLIGHT=BLOCKED")
        return 1
    print("QUALITY_SLIDE_PREFLIGHT=PASS (evidence presence only; not visual acceptance)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
