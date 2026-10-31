#!/usr/bin/env python3
"""Stage the precisely qualified CC0 Pinnace in a NON-COMMITTED Godot quarantine.

The published source 1K GLTF, BIN and full declared PBR texture closure are
MD5 checked and SHA256 recorded. The upstream sail alpha is composed into an
RGBA atlas in quarantine, without altering upstream source bytes or the game
asset manifest. This is NOT production asset admission or mobile acceptance.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

from qualify_polyhaven_ship_geometry import (
    API_HOST, DATA_HOST, _download, _read,
)

ASSET = "ship_pinnace"
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "client-godot" / "assets" / "quarantine" / ASSET
SOURCE_SHA256 = "668298cada1731ec93886bb7ec2f170bbbf45575d341b838a09580199fdf5ec5"
BIN_SHA256 = "2066c551c756ca1bef9a03d8b2f7ee980b56f69eddf1682531899e9bcf2539db"


def _save(path: Path, content: bytes) -> None:
    if path.is_symlink() or any(parent.is_symlink() for parent in path.parents if parent != ROOT):
        raise ValueError("Quarantine destination must not be symlinked")
    if not path.resolve().is_relative_to(OUT.resolve()):
        raise ValueError("Destination outside quarantine")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def main() -> None:
    manifest = json.loads(_read(f"https://api.polyhaven.com/files/{ASSET}", API_HOST, 1_000_000))
    upstream = manifest["gltf"]["1k"]["gltf"]
    source, source_info = _download(upstream, DATA_HOST, 256_000)
    if source_info["sha256"] != SOURCE_SHA256:
        raise ValueError("The source glTF differs from approved geometry qualification")
    gltf = json.loads(source)
    included = upstream["include"]
    staged = []
    for rel, data in sorted(included.items()):
        if rel.startswith("/") or ".." in Path(rel).parts or "\\" in rel or not rel:
            raise ValueError("Invalid glTF dependency path")
        if rel.lower().endswith(".exr") or int(data["size"]) > 20_000_000:
            raise ValueError("Unexpected large dependency")
        content, info = _download(data, DATA_HOST, 20_000_000)
        if rel == gltf["buffers"][0]["uri"] and info["sha256"] != BIN_SHA256:
            raise ValueError("The source BIN differs from approved geometry qualification")
        _save(OUT / rel, content)
        staged.append({"path": rel, **info})

    # The upstream glTF declares alpha cutout on a JPEG, which does not have
    # alpha. Importing it directly makes the cloth opaque. Compose the official
    # separate alpha atlas with the source diffuse without modifying either.
    alpha_source = manifest["sails_alpha"]["1k"]["png"]
    alpha_bytes, alpha_receipt = _download(alpha_source, DATA_HOST, 10_000_000)
    _save(OUT / "textures/ship_pinnace_sails_alpha_1k.png", alpha_bytes)
    staged.append({"path": "textures/ship_pinnace_sails_alpha_1k.png", **alpha_receipt})

    diffuse_path = OUT / "textures/ship_pinnace_sails_diff_1k.jpg"
    with Image.open(diffuse_path) as rgb_file, Image.open(
        OUT / "textures/ship_pinnace_sails_alpha_1k.png"
    ) as alpha_file:
        atlas = rgb_file.convert("RGBA")
        mask = alpha_file.convert("L")
        if atlas.size != mask.size:
            raise ValueError("Sail alpha and diffuse dimensions differ")
        atlas.putalpha(mask)
        derived_path = OUT / "textures/ship_pinnace_sails_rgba_1k.png"
        atlas.save(derived_path)
    derived_hash = hashlib.sha256(derived_path.read_bytes()).hexdigest()

    changed_images = 0
    for image in gltf["images"]:
        if image["uri"].endswith("ship_pinnace_sails_diff_1k.jpg"):
            image["uri"] = "textures/ship_pinnace_sails_rgba_1k.png"
            image["mimeType"] = "image/png"
            changed_images += 1
    if changed_images != 1:
        raise ValueError("Unknown sail atlas image layout")
    # Preserve material/mesh topology and every other texture path.
    derived_gltf = json.dumps(gltf, indent=2) + "\n"
    _save(OUT / "ship_pinnace_1k.gltf", derived_gltf.encode("utf-8"))
    receipt = {
        "admission": "QUARANTINE_ONLY",
        "upstream_gltf": source_info,
        "pinned_upstream_gltf_sha256": SOURCE_SHA256,
        "pinned_bin_sha256": BIN_SHA256,
        "source": "https://polyhaven.com/a/ship_pinnace",
        "license": "CC0-1.0",
        "files": staged,
        "generated": {
            "path": "textures/ship_pinnace_sails_rgba_1k.png",
            "sha256": derived_hash,
            "generated_from": [
                "textures/ship_pinnace_sails_diff_1k.jpg",
                "textures/ship_pinnace_sails_alpha_1k.png",
            ],
            "note": "PIL RGBA composite; the original diffuse RGB and alpha mask are retained"
        },
        "patched_gltf_sha256": hashlib.sha256(derived_gltf.encode("utf-8")).hexdigest(),
    }
    (OUT / "QUARANTINE_RECEIPT.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Staged official Pinnace with", len(staged), "SHA256-recorded dependencies")
    print("Source SHA256:", SOURCE_SHA256)
    print("Patched quarantine glTF SHA256:", receipt["patched_gltf_sha256"])


if __name__ == "__main__":
    main()
