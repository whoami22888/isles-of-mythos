import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import graphics_quality_preflight as preflight


class QualitySlidePreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "client-godot").mkdir()

    def _png(self, name="slide.png"):
        # Valid 320x180 PNG header plus a tiny body; the preflight checks the
        # header, dimensions and digest without pretending to judge pixels.
        data = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + (320).to_bytes(4, "big") + (180).to_bytes(4, "big") + b"\x08\x06\x00\x00\x00" + b"fixture"
        path = self.root / name
        path.write_bytes(data)
        return path

    def _manifest(self, image, source="abc123"):
        digest = hashlib.sha256(image.read_bytes()).hexdigest()
        manifest = {
            "image": image.name,
            "sha256": digest,
            "source_sha": source,
            "reference_sha256": preflight.REFERENCE_SHA256,
            "review_status": "reviewed",
        }
        path = self.root / "quality-test-slide.json"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        return path

    def test_missing_manifest_blocks_before_render(self):
        errors = preflight.validate(self.root / "missing.json", "abc123", self.root / "client-godot")
        self.assertTrue(any("missing" in item for item in errors))

    def test_valid_hash_pinned_slide_passes_presence_screen(self):
        image = self._png()
        manifest = self._manifest(image)
        self.assertEqual([], preflight.validate(manifest, "abc123", self.root / "client-godot"))

    def test_source_sha_mismatch_blocks(self):
        image = self._png()
        manifest = self._manifest(image, source="old")
        self.assertTrue(any("does not match" in item for item in preflight.validate(manifest, "new", self.root / "client-godot")))

    def test_digest_mismatch_blocks(self):
        image = self._png()
        manifest = self._manifest(image)
        image.write_bytes(image.read_bytes() + b"changed")
        self.assertTrue(any("sha256" in item for item in preflight.validate(manifest, "abc123", self.root / "client-godot")))


if __name__ == "__main__":
    unittest.main()
