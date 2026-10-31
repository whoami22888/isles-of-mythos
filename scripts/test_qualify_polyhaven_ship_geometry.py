"""Regression checks for SHA-256-only quarantined ship admission."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import qualify_polyhaven_ship_geometry as qualifier


class ShipQualificationPins(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.lock = Path(self.temp.name) / "ship-lock.json"
        self.blob = b"known verified bytes"
        self.record = {
            "schema_version": 1,
            "license": "CC0-1.0",
            "files": {"approved.bin": hashlib.sha256(self.blob).hexdigest()},
        }
        self.lock.write_text(json.dumps(self.record), encoding="utf-8")

    def test_verified_source_matches_explicit_sha256(self):
        with patch.object(qualifier, "SHA256_MANIFEST", self.lock), patch.object(
            qualifier, "_read", return_value=self.blob
        ):
            data, receipt = qualifier._download(
                {
                    "url": "https://dl.polyhaven.org/file/approved.bin",
                    "size": len(self.blob),
                    "md5": "this-untrusted-value-must-not-be-used",
                },
                qualifier.DATA_HOST,
                500,
            )
        self.assertEqual(data, self.blob)
        self.assertEqual(receipt["sha256"], self.record["files"]["approved.bin"])
        self.assertNotIn("md5", receipt)

    def test_modified_bytes_rejected_despite_catalogue_metadata(self):
        with patch.object(qualifier, "SHA256_MANIFEST", self.lock), patch.object(
            qualifier, "_read", return_value=b"malicious content"
        ):
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                qualifier._download(
                    {"url": "https://dl.polyhaven.org/file/approved.bin", "size": 17},
                    qualifier.DATA_HOST,
                    500,
                )

    def test_unknown_file_rejected_before_download(self):
        with patch.object(qualifier, "SHA256_MANIFEST", self.lock), patch.object(
            qualifier, "_read", side_effect=AssertionError("must not download")
        ):
            with self.assertRaisesRegex(ValueError, "Unpinned"):
                qualifier._download(
                    {"url": "https://dl.polyhaven.org/file/rogue.bin", "size": 10},
                    qualifier.DATA_HOST,
                    500,
                )

    def test_non_https_or_off_host_rejected(self):
        for url in (
            "http://dl.polyhaven.org/file/approved.bin",
            "https://example.com/file/approved.bin",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                qualifier._validate_url(url, qualifier.DATA_HOST)


if __name__ == "__main__":
    unittest.main()
