#!/usr/bin/env python3
"""Regression tests for the external art manifest validator; no external network."""
from contextlib import ExitStack
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / "validate_godot_assets.py"
spec = importlib.util.spec_from_file_location("godot_asset_validator", SCRIPT)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class AssetValidatorTests(unittest.TestCase):
    """Validate manifest metadata, hashes, paths, and symlink rejection."""

    def setUp(self):
        """Create isolated asset fixtures."""
        contexts = ExitStack()
        self.addCleanup(contexts.close)
        self.temp = contexts.enter_context(tempfile.TemporaryDirectory())
        root = Path(self.temp)
        self.assets = root / "external"
        self.assets.mkdir()
        self.manifest = root / "external-assets.json"
        self.old_manifest, self.old_assets = validator.MANIFEST, validator.ASSETS
        validator.MANIFEST, validator.ASSETS = self.manifest, self.assets
        self.addCleanup(self.restore)
        self.sample = b"verified test bytes"
        self.entry = {
            "id": "terrain-test",
            "path": "terrain.glb",
            "sha256": hashlib.sha256(self.sample).hexdigest(),
            "source_url": "https://polyhaven.com/a/test",
            "download_url": "https://dl.polyhaven.org/terrain.glb",
            "license": "CC0-1.0",
            "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
            "attribution": "Test fixture only",
        }

    def restore(self):
        """Restore module globals."""
        validator.MANIFEST, validator.ASSETS = self.old_manifest, self.old_assets

    def write(self, entries):
        """Write an isolated manifest."""
        self.manifest.write_text(
            json.dumps({"schema_version": 1, "assets": entries}), encoding="utf-8"
        )

    def test_empty_manifest(self):
        """Regression: empty manifest."""
        self.write([])
        self.assertEqual(validator.validate(), 0)

    def test_missing_download_url_rejected(self):
        """An approved manifest must be consumable by the pinned fetcher."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        del self.entry["download_url"]
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "missing mandatory"):
            validator.validate()

    def test_unapproved_download_origin_rejected(self):
        """Use the same origin allowlist for validation and acquisition."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        self.entry["download_url"] = "https://evil.test/terrain.glb"
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "Unapproved"):
            validator.validate()

    def test_matching_hash(self):
        """Regression: matching hash."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        self.write([self.entry])
        self.assertEqual(validator.validate(), 0)

    def test_hash_mismatch_rejected(self):
        """Regression: hash mismatch rejected."""
        (self.assets / "terrain.glb").write_bytes(b"tampered")
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            validator.validate()

    def test_unknown_license_rejected(self):
        """Regression: unknown license rejected."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        self.entry["license"] = "unknown"
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "not allowlisted"):
            validator.validate()

    def test_unregistered_file_rejected(self):
        """Regression: unregistered file rejected."""
        self.write([])
        (self.assets / "unsourced.glb").write_bytes(b"unverified")
        with self.assertRaisesRegex(ValueError, "Unregistered"):
            validator.validate()

    def test_import_sidecar_allowed(self):
        (self.assets / "terrain.glb").write_bytes(self.sample)
        (self.assets / "terrain.glb.import").write_text("[remap]\n")
        (self.assets / "terrain.glb.uid").write_text("uid://test\n")
        self.write([self.entry])
        self.assertEqual(validator.validate(), 0)

    def test_import_texture_copy_requires_registered_source_hash(self):
        (self.assets / "terrain.glb").write_bytes(self.sample)
        source = self.assets / "polyhaven/coastal_cliff_01/textures/coastal_cliff_01_diff_1k.jpg"
        source.parent.mkdir(parents=True)
        source.write_bytes(b"source texture")
        source_entry = dict(self.entry, id="texture", path=str(source.relative_to(self.assets)),
                            sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                            source_url="https://polyhaven.com/a/coastal_cliff_01",
                            download_url="https://dl.polyhaven.org/coastal_cliff_01/coastal_cliff_01_diff_1k.jpg",
                            upstream_md5="a" * 32)
        output = self.assets / "generated/coastal_cliff_blender/coastal_cliff_lod1_coastal_cliff_01_diff_1k.jpg"
        output.parent.mkdir(parents=True)
        output.write_bytes(source.read_bytes())
        self.write([self.entry, source_entry])
        self.assertEqual(validator.validate(), 0)
        output.write_bytes(b"unverified bytes")
        with self.assertRaisesRegex(ValueError, "Unregistered"):
            validator.validate()

    def test_path_traversal_rejected(self):
        """Regression: path traversal rejected."""
        self.entry["path"] = "../outside.glb"
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "unsafe path"):
            validator.validate()

    def test_symlinked_file_inside_root_rejected(self):
        """Regression: symlinked file inside root rejected."""
        (self.assets / "real.glb").write_bytes(self.sample)
        (self.assets / "terrain.glb").symlink_to("real.glb")
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "symlinked"):
            validator.validate()

    def test_symlinked_parent_directory_rejected(self):
        """Regression: symlinked parent directory rejected."""
        real = self.assets / "real"
        real.mkdir()
        (real / "terrain.glb").write_bytes(self.sample)
        (self.assets / "alias").symlink_to(real, target_is_directory=True)
        self.entry["path"] = "alias/terrain.glb"
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "symlinked"):
            validator.validate()

    def test_unregistered_symlink_alias_to_registered_file_rejected(self):
        """A symlink alias must not disappear when paths are resolved."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        (self.assets / "alias.glb").symlink_to("terrain.glb")
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "Symlinked"):
            validator.validate()

    def test_symlinked_asset_root_rejected(self):
        """The entire asset root cannot be redirected to another directory."""
        real_root = Path(self.temp) / "actual-assets"
        real_root.mkdir()
        self.assets.rmdir()
        self.assets.symlink_to(real_root, target_is_directory=True)
        self.write([])
        with self.assertRaisesRegex(ValueError, "Symlinked external assets root"):
            validator.validate()

    def test_duplicate_asset_path_rejected(self):
        """Regression: duplicate asset path rejected."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        self.write([self.entry, dict(self.entry, id="duplicate")])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            validator.validate()


    def test_polyhaven_rejects_generic_source_page(self):
        """A generic publisher page cannot establish package provenance."""
        self.entry.update({
            "path": "polyhaven/coast_rocks_05/coast_rocks_05.bin",
            "source_url": "https://polyhaven.com/a/polyhaven",
            "download_url": (
                "https://dl.polyhaven.org/file/ph-assets/Models/gltf/8k/"
                "coast_rocks_05/coast_rocks_05.bin"
            ),
            "upstream_md5": "a" * 32,
        })
        with self.assertRaisesRegex(ValueError, "source does not match"):
            validator.validate_metadata(0, self.entry, set(), set())

    def test_polyhaven_rejects_wrong_package_download(self):
        """Do not accept an asset from a different package just by host."""
        self.entry.update({
            "path": "polyhaven/coast_rocks_05/coast_rocks_05.bin",
            "source_url": "https://polyhaven.com/a/coast_rocks_05",
            "download_url": (
                "https://dl.polyhaven.org/file/ph-assets/Models/gltf/8k/"
                "other_asset/coast_rocks_05.bin"
            ),
            "upstream_md5": "a" * 32,
        })
        with self.assertRaisesRegex(ValueError, "not bound"):
            validator.validate_metadata(0, self.entry, set(), set())

    def test_generated_asset_dependency_must_be_manifested(self):
        """Committed derivatives cannot point to missing source textures."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        self.entry.update({
            "path": "polyhaven/coast_rocks_05/coast_rocks_05.bin",
            "source_url": "https://polyhaven.com/a/coast_rocks_05",
            "download_url": (
                "https://dl.polyhaven.org/file/ph-assets/Models/gltf/8k/"
                "coast_rocks_05/coast_rocks_05.bin"
            ),
            "generated_from": ["polyhaven/coast_rocks_05/missing-source.png"],
            "generation_note": "Derived locally",
        })
        destination = self.assets / self.entry["path"]
        destination.parent.mkdir(parents=True)
        destination.write_bytes(self.sample)
        (self.assets / "terrain.glb").unlink()
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "dependency is absent"):
            validator.validate()

if __name__ == "__main__":
    unittest.main()
