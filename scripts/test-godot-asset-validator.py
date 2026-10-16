#!/usr/bin/env python3
"""Regression tests for the external art manifest validator; no external network."""
# pylint: disable=invalid-name  # CLI entrypoint filenames are referenced by CI.
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / "validate-godot-assets.py"
spec = importlib.util.spec_from_file_location("godot_asset_validator", SCRIPT)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class AssetValidatorTests(unittest.TestCase):
    """Validate manifest metadata, hashes, paths, and symlink rejection."""

    def setUp(self):
        """Create isolated asset fixtures."""
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.assets = root / "external"
        self.assets.mkdir()
        self.manifest = root / "external-assets.json"
        self.old_manifest, self.old_assets = validator.MANIFEST, validator.ASSETS
        validator.MANIFEST, validator.ASSETS = self.manifest, self.assets
        self.addCleanup(self.restore)
        self.sample = b"verified test bytes"
        self.entry = dict(id="terrain-test", path="terrain.glb",
            sha256=hashlib.sha256(self.sample).hexdigest(),
            source_url="https://polyhaven.com/a/test", license="CC0-1.0",
            license_url="https://creativecommons.org/publicdomain/zero/1.0/",
            attribution="Test fixture only")

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

    def test_duplicate_asset_path_rejected(self):
        """Regression: duplicate asset path rejected."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        self.write([self.entry, dict(self.entry, id="duplicate")])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            validator.validate()

if __name__ == "__main__":
    unittest.main()
