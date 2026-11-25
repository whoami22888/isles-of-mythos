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
HASH = re.compile(r"^[0-9a-f]{64}$")
REQUIRED = {
    "id", "path", "sha256", "source_url", "download_url",
    "license", "license_url", "attribution",
}
LICENSES = {"CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "MIT", "Apache-2.0", "OFL-1.1"}
GODOT_SIDECARS = {".import", ".uid"}
BOUNDED_LOD_ASSETS = ("tree_small_02", "island_tree_01", "island_tree_02", "coast_rocks_05")
BOUNDED_LOD_TRIANGLE_CAPS = {
    "tree_small_02": 90_000,
    "island_tree_01": 72_000,
    "island_tree_02": 72_000,
    "coast_rocks_05": 30_000,
}


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



def validate_generated_dependencies(registered_by_path):
    """Require every generated asset to declare unique, manifested source paths."""
    for entry in registered_by_path.values():
        if "generated_from" not in entry:
            continue
        parents = entry["generated_from"]
        if (not isinstance(parents, list) or not parents
                or not all(isinstance(parent, str) and parent
                           and parent != entry["path"] for parent in parents)
                or len(set(parents)) != len(parents)
                or not isinstance(entry.get("generation_note"), str)
                or not entry["generation_note"].strip()):
            fail(f"Generated asset has invalid source lineage: {entry['path']}")
        for source in parents:
            if source not in registered_by_path:
                fail(f"Generated asset dependency is absent: {source}")


def require_source_provenance(entry, source, output_path):
    """Bind a generated output's source and license fields to its source model."""
    for field in ("source_url", "download_url", "license", "license_url", "attribution"):
        if entry.get(field) != source.get(field):
            fail(
                f"Bounded LOD source lineage mismatch for {output_path}: "
                f"{field} does not match {source['path']}"
            )


def validate_bounded_lod_lineage(registered_by_path):
    """Fail closed when a complete bounded LOD bundle cites the wrong model."""
    prefix = "generated/bounded_lods/"
    bounded_paths = sorted(
        path for path in registered_by_path if path.startswith(prefix)
    )
    if not bounded_paths:
        return

    metadata_path = f"{prefix}metadata.json"
    metadata_entry = registered_by_path.get(metadata_path)
    has_model_output = any(
        f"{prefix}{asset}.glb" in registered_by_path
        for asset in BOUNDED_LOD_ASSETS
    )
    if metadata_entry is None:
        if has_model_output:
            fail("Bounded LOD aggregate metadata is not manifested")
        # Texture-only importer fixtures are valid without the four-model
        # bundle. If their source model is present, still verify its lineage.
        for output_path in bounded_paths:
            filename = pathlib.PurePosixPath(output_path).name
            asset = next(
                (
                    name for name in BOUNDED_LOD_ASSETS
                    if filename.startswith(f"{name}_")
                ),
                None,
            )
            if asset is None:
                fail(f"Unknown bounded LOD output family: {output_path}")
            if pathlib.PurePosixPath(output_path).suffix.lower() not in {
                ".jpg", ".jpeg", ".png"
            }:
                fail(f"Bounded LOD output must be a texture: {output_path}")
            source_path = f"polyhaven/{asset}/{asset}_1k.gltf"
            source = registered_by_path.get(source_path)
            if source is None:
                fail(f"Bounded LOD source model is not manifested: {source_path}")
            entry = registered_by_path[output_path]
            if entry.get("generated_from") != [source_path]:
                fail(
                    f"Bounded LOD source lineage mismatch for {output_path}: "
                    f"expected only {source_path}"
                )
            require_source_provenance(entry, source, output_path)
        return

    expected_sources = [
        f"polyhaven/{asset}/{asset}_1k.gltf"
        for asset in BOUNDED_LOD_ASSETS
    ]
    for asset, source_path in zip(BOUNDED_LOD_ASSETS, expected_sources):
        if source_path not in registered_by_path:
            fail(f"Bounded LOD source model is not manifested: {source_path}")
        output_path = f"{prefix}{asset}.glb"
        if output_path not in registered_by_path:
            fail(f"Bounded LOD output is not manifested: {output_path}")

    if metadata_entry.get("generated_from") != expected_sources:
        fail("Bounded LOD metadata must list all four source models in generated_from")
    require_source_provenance(
        metadata_entry,
        registered_by_path[expected_sources[0]],
        metadata_path,
    )

    for output_path in bounded_paths:
        if output_path == metadata_path:
            continue
        filename = pathlib.PurePosixPath(output_path).name
        asset = next(
            (
                name for name in BOUNDED_LOD_ASSETS
                if filename == f"{name}.glb" or filename.startswith(f"{name}_")
            ),
            None,
        )
        if asset is None:
            fail(f"Unknown bounded LOD output family: {output_path}")
        source_path = f"polyhaven/{asset}/{asset}_1k.gltf"
        entry = registered_by_path[output_path]
        if entry.get("generated_from") != [source_path]:
            fail(
                f"Bounded LOD source lineage mismatch for {output_path}: "
                f"expected only {source_path}"
            )
        require_source_provenance(entry, registered_by_path[source_path], output_path)

    metadata_file = ASSETS / metadata_path
    records = json.loads(metadata_file.read_text(encoding="utf-8"))
    if not isinstance(records, list):
        fail("Bounded LOD metadata must be a JSON array")
    rows_by_asset = {}
    for row in records:
        if not isinstance(row, dict):
            fail("Bounded LOD metadata contains a non-object record")
        asset = row.get("asset")
        if asset not in BOUNDED_LOD_ASSETS or asset in rows_by_asset:
            fail(f"Bounded LOD metadata has an unknown or duplicate asset: {asset}")
        source_path = f"polyhaven/{asset}/{asset}_1k.gltf"
        output_path = f"{prefix}{asset}.glb"
        source = registered_by_path[source_path]
        output = registered_by_path[output_path]
        if row.get("source_sha256") != source.get("sha256"):
            fail(f"Bounded LOD metadata source SHA-256 mismatch for {asset}")
        if row.get("output_sha256") != output.get("sha256"):
            fail(f"Bounded LOD metadata output SHA-256 mismatch for {asset}")
        before = row.get("before")
        after = row.get("after")
        if (type(before) is not int or type(after) is not int
                or before <= 0 or after <= 0 or after > before
                or after > BOUNDED_LOD_TRIANGLE_CAPS[asset]):
            fail(f"Bounded LOD metadata triangle counts are invalid for {asset}")
        blender = row.get("blender")
        if not isinstance(blender, str) or not blender.strip():
            fail(f"Bounded LOD metadata is missing Blender provenance for {asset}")
        rows_by_asset[asset] = row

    if set(rows_by_asset) != set(BOUNDED_LOD_ASSETS):
        fail("Bounded LOD metadata must contain exactly the four admitted source models")

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
    registered_by_path = {}
    for index, item in enumerate(data["assets"]):
        validate_metadata(index, item, seen_ids, seen_paths)
        registered.add(validate_path(index, item, root))
        registered_by_path[item["path"]] = item
    # Generated outputs are verified in-place, and must have fully recorded
    # source dependencies. They are never downloaded as if upstream provided
    # a binary with the derived SHA-256.
    validate_generated_dependencies(registered_by_path)
    validate_bounded_lod_lineage(registered_by_path)
    if ASSETS.exists():
        actual = set()
        for candidate in ASSETS.rglob("*"):
            # Do not resolve before checking: an unregistered symlink alias
            # to an approved file would otherwise collapse into its digest.
            if candidate.is_symlink():
                fail("Symlinked file(s) under client-godot/assets/external")
            if candidate.is_file():
                if candidate.resolve() in registered:
                    actual.add(candidate.resolve())
                    continue
                if candidate.suffix in GODOT_SIDECARS:
                    continue
                # Godot extracts the coastal cliff's authored textures beside
                # each derived LOD. Admit only byte-identical copies of the
                # exact manifested upstream texture, never arbitrary JPGs.
                relative = candidate.relative_to(ASSETS).as_posix()
                match = re.fullmatch(
                    r"generated/coastal_cliff_blender/coastal_cliff_lod[12]_"
                    r"(coastal_cliff_01_[^/]+\.jpg)",
                    relative,
                )
                if match:
                    source = registered_by_path.get(
                        f"polyhaven/coastal_cliff_01/textures/{match.group(1)}"
                    )
                    if (source and hashlib.sha256(candidate.read_bytes()).hexdigest()
                            == source["sha256"]):
                        continue
                # Godot also extracts the two self-contained tree LOD2 GLBs.
                # Accept only exact copies of their already manifested source
                # textures; a changed or additional file remains unregistered.
                tree_match = re.fullmatch(
                    r"generated/foliage/(island_tree_0[12])_lod2_\1_(.+\.(?:jpg|png))",
                    relative,
                )
                if tree_match:
                    tree, texture = tree_match.groups()
                    source = registered_by_path.get(
                        f"generated/bounded_lods/{tree}_{tree}_{texture}"
                    )
                    if (source and hashlib.sha256(candidate.read_bytes()).hexdigest()
                            == source["sha256"]):
                        continue
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
