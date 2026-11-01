#!/usr/bin/env python3
"""Fail-closed provenance and integrity checks for imported third-party Godot art."""
import hashlib
import json
import pathlib
import re
import sys
from urllib.parse import urlparse

from fetch_verified_godot_assets import validate_origin

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "client-godot" / "assets" / "external-assets.json"
ASSETS = ROOT / "client-godot" / "assets" / "external"
GODOT_SIDECARS = {".import", ".uid"}
TEXTURE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".ktx", ".ktx2"}
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
    # Poly Haven metadata must identify the actual package and an approved
    # source-file path. A generic /a/polyhaven page or /1k/polyhaven/ URL
    # is not enough to prove commercial redistribution provenance.
    relative = pathlib.PurePosixPath(item["path"])
    if relative.parts and relative.parts[0] == "polyhaven":
        if len(relative.parts) < 3:
            fail(f"Asset {index}: missing Poly Haven package path")
        package = relative.parts[1]
        expected_source = f"https://polyhaven.com/a/{package}"
        if item["source_url"] != expected_source:
            fail(f"Asset {index}: Poly Haven source does not match package")
        download = urlparse(item["download_url"])
        if (download.hostname != "dl.polyhaven.org"
                or f"/{package}/" not in download.path):
            fail(f"Asset {index}: download URL not bound to Poly Haven package")
        if "generated_from" in item:
            parents = item["generated_from"]
            if (not isinstance(parents, list) or not parents
                    or not all(isinstance(p, str) and p and p != item["path"]
                               for p in parents)
                    or not isinstance(item.get("generation_note"), str)
                    or not item["generation_note"].strip()):
                fail(f"Asset {index}: invalid generated source metadata")
        else:
            if pathlib.PurePosixPath(download.path).name != relative.name:
                fail(f"Asset {index}: upstream filename mismatch")
            md5 = item.get("upstream_md5")
            if not isinstance(md5, str) or not re.fullmatch(r"[a-f0-9]{32}", md5):
                fail(f"Asset {index}: missing upstream catalogue MD5")


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


def validate(post_import: bool = False) -> int:
    """Validate source provenance and, after import, all registered texture bytes."""
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
    if post_import:
        # Imported source textures are still the redistributable inputs. Godot's
        # generated cache and sidecars are not provenance records for their bytes.
        for index, item in enumerate(data["assets"]):
            if pathlib.PurePosixPath(item["path"]).suffix.lower() in TEXTURE_EXTENSIONS:
                validate_path(index, item, root)
    # Generated outputs are verified in-place, and must have fully recorded
    # source dependencies. They are never downloaded as if upstream provided
    # a binary with the derived SHA-256.
    for entry in data["assets"]:
        for source in entry.get("generated_from", []):
            if source not in seen_paths:
                fail(f"Generated asset dependency is absent: {source}")
    if ASSETS.exists():
        actual = set()
        for candidate in ASSETS.rglob("*"):
            # Do not resolve before checking: an unregistered symlink alias
            # to an approved file would otherwise collapse into its digest.
            if candidate.is_symlink():
                fail("Symlinked file(s) under client-godot/assets/external")
            if candidate.is_file():
                if candidate.suffix.lower() in GODOT_SIDECARS:
                    continue
                actual.add(candidate.resolve())
        if actual != registered:
            fail("Unregistered file(s) under client-godot/assets/external")
    print(f"Asset provenance validation PASS: {len(registered)} registered asset files")
    return 0


if __name__ == "__main__":
    try:
        if len(sys.argv) > 2 or (len(sys.argv) == 2 and sys.argv[1] != "--post-import"):
            fail("Usage: validate_godot_assets.py [--post-import]")
        sys.exit(validate(post_import="--post-import" in sys.argv))
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"Asset provenance validation FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
