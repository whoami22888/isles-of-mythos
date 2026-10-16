#!/usr/bin/env python3
"""Fail-closed provenance and integrity checks for imported third-party Godot art."""
# pylint: disable=invalid-name  # Hyphenated CLI script name is required by CI.
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "client-godot" / "assets" / "external-assets.json"
ASSETS = ROOT / "client-godot" / "assets" / "external"
HASH = re.compile(r"^[0-9a-f]{64}$")
REQUIRED = {"id", "path", "sha256", "source_url", "license", "license_url", "attribution"}
LICENSES = {"CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "MIT", "Apache-2.0", "OFL-1.1"}

def fail(message: str) -> None:
    """Reject an asset candidate without weakening the admission gate."""
    raise ValueError(message)

def validate() -> int:  # pylint: disable=too-many-branches
    """Validate approved manifest entries against filesystem and digest evidence."""
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if (not isinstance(data, dict) or data.get("schema_version") != 1
            or not isinstance(data.get("assets"), list)):
        fail("Manifest must contain schema_version=1 and assets array")
    seen_ids, seen_paths = set(), set()
    root = ASSETS.resolve()
    registered = set()
    for index, item in enumerate(data["assets"]):
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
        registered.add(path)
    if ASSETS.exists():
        actual = {p.resolve() for p in ASSETS.rglob("*") if p.is_file() or p.is_symlink()}
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
