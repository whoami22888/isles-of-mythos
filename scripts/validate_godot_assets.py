#!/usr/bin/env python3
"""Fail-closed provenance and integrity checks for imported third-party Godot art."""
import hashlib
import json
import pathlib
import re
import sys

from fetch_verified_godot_assets import validate_origin

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "client-godot" / "assets" / "external-assets.json"
ASSETS = ROOT / "client-godot" / "assets" / "external"
HASH = re.compile(r"^[0-9a-f]{64}$")
REQUIRED = {
    "id", "path", "sha256", "source_url", "download_url",
    "license", "license_url", "attribution",
}
LICENSES = {"CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "MIT", "Apache-2.0", "OFL-1.1"}


def fail(message: str) -> None:
    """Reject an asset candidate without weakening the admission gate."""
    raise ValueError(message)


def validate_metadata(index, item, seen_ids, seen_paths):
    """Check required provenance, uniqueness, license, URLs and digest syntax."""
    if not isinstance(item, dict) or not REQUIRED.issubset(item):
        fail(f"Asset {index}: missing mandatory provenance fields")
    if any(not isinstance(item[k], str) or not item[k].strip() for k in REQUIRED):
        fail(f"Asset {index}: blank or non-string metadata")
    if item["id"] in seen_ids or item["path"] in seen_paths:
        fail(f"Asset {index}: duplicate ID/path")
    seen_ids.add(item["id"])
    seen_paths.add(item["path"])
    if item["license"] not in LICENSES:
        fail(f"Asset {index}: license not allowlisted; manually review before admission")
    if not all(item[key].startswith("https://") for key in ("source_url", "license_url")):
        fail(f"Asset {index}: source and license URLs must use HTTPS")
    if not HASH.fullmatch(item["sha256"]):
        fail(f"Asset {index}: invalid SHA-256 digest")
    validate_origin(item["download_url"])


def validate_path(index, item, root):
    """Reject unsafe paths and symlinks before checking file content."""
    relative = pathlib.PurePosixPath(item["path"])
    if relative.is_absolute() or ".." in relative.parts or "\\" in item["path"]:
        fail(f"Asset {index}: unsafe path")
    raw_path = ASSETS / item["path"]
    # Inspect the original path, including intermediate directories, BEFORE
    # resolving it: resolve() otherwise hides symlinks to in-root files.
    current = ASSETS
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            fail(f"Asset {index}: symlinked asset or parent directory")
    path = raw_path.resolve()
    if not path.is_relative_to(root) or not path.is_file():
        fail(f"Asset {index}: missing or outside import directory")
    if hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]:
        fail(f"Asset {index}: content hash mismatch")
    return path


def validate() -> int:
    """Validate approved manifest entries against filesystem and digest evidence."""
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if (not isinstance(data, dict) or data.get("schema_version") != 1
            or not isinstance(data.get("assets"), list)):
        fail("Manifest must contain schema_version=1 and assets array")
    seen_ids, seen_paths = set(), set()
    if ASSETS.is_symlink():
        fail("Symlinked external assets root")
    root = ASSETS.resolve()
    registered = set()
    for index, item in enumerate(data["assets"]):
        validate_metadata(index, item, seen_ids, seen_paths)
        registered.add(validate_path(index, item, root))
    if ASSETS.exists():
        actual = set()
        for candidate in ASSETS.rglob("*"):
            # Do not resolve before checking: an unregistered symlink alias
            # to an approved file would otherwise collapse into its digest.
            if candidate.is_symlink():
                fail("Symlinked file(s) under client-godot/assets/external")
            if candidate.is_file():
                actual.add(candidate.resolve())
        if actual != registered:
            fail("Unregistered file(s) under client-godot/assets/external")
    print(f"Asset provenance validation PASS: {len(registered)} registered asset files")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(validate())
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"Asset provenance validation FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
