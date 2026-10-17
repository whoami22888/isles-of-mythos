#!/usr/bin/env python3
"""Fail-closed validation for the admitted Quaternius starter package."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "client-godot/assets/pirate-kit"
MANIFEST = ASSET_ROOT / "manifest.json"


def validate() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 2 or manifest.get("license") != "CC0-1.0":
        raise ValueError("unexpected asset manifest or licence")
    files = manifest.get("files")
    if not isinstance(files, list) or len(files) != 4:
        raise ValueError("manifest must contain exactly four admitted files")
    names = set()
    for entry in files:
        name = entry["name"]
        if name in names or Path(name).name != name:
            raise ValueError("duplicate or unsafe asset name")
        names.add(name)
        path = ASSET_ROOT / name
        data = path.read_bytes()
        if len(data) != entry["bytes"]:
            raise ValueError(f"byte count mismatch: {name}")
        if hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise ValueError(f"SHA-256 mismatch: {name}")
        if name.endswith(".gltf"):
            payload = json.loads(data)
            if any(not str(buf.get("uri", "")).startswith("data:")
                   for buf in payload.get("buffers", [])):
                raise ValueError(f"external buffer dependency: {name}")
            if any(image.get("uri", "") and not image["uri"].startswith("data:")
                   for image in payload.get("images", [])):
                raise ValueError(f"external image dependency: {name}")
    print(f"PASS admitted pirate assets: {len(files)} files")


if __name__ == "__main__":
    validate()
