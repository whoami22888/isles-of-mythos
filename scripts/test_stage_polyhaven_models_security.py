"""Offline security regressions for the Poly Haven candidate staging writer."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).parent / "stage_polyhaven_models.py"
spec = importlib.util.spec_from_file_location("model_stage", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class StageSecurityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.old = mod.OUTPUT
        self.addCleanup(lambda: setattr(mod, "OUTPUT", self.old))
        mod.OUTPUT = Path(self.tmp.name) / "stage"
        mod.OUTPUT.mkdir()
        self.outside = Path(self.tmp.name) / "outside"
        self.outside.mkdir()
        self.sample = b"gltf safe bytes"
        self.sha = hashlib.sha256(self.sample).hexdigest()

    def test_reject_parent_symlink_even_inside_stage(self):
        (mod.OUTPUT / "real").mkdir()
        (mod.OUTPUT / "link").symlink_to(mod.OUTPUT / "real", target_is_directory=True)
        with self.assertRaises(OSError):
            mod._stage_stream("link/test.bin", io.BytesIO(self.sample), self.sha)
        self.assertFalse((mod.OUTPUT / "real/test.bin").exists())

    def test_reject_parent_symlink_escaping_staging(self):
        (mod.OUTPUT / "link").symlink_to(self.outside, target_is_directory=True)
        with self.assertRaises(OSError):
            mod._stage_stream("link/test.bin", io.BytesIO(self.sample), self.sha)
        self.assertEqual(list(self.outside.iterdir()), [])

    def test_reject_final_file_symlink_preserve_outside(self):
        target = self.outside / "original.bin"
        target.write_bytes(b"leave me alone")
        (mod.OUTPUT / "linked.bin").symlink_to(target)
        with self.assertRaisesRegex(ValueError, "regular file"):
            mod._stage_stream("linked.bin", io.BytesIO(self.sample), self.sha)
        self.assertEqual(target.read_bytes(), b"leave me alone")

    def test_reject_symlinked_receipt(self):
        target = self.outside / "report"
        target.write_bytes(b"report untouched")
        (mod.OUTPUT / "receipt.json").symlink_to(target)
        with self.assertRaisesRegex(ValueError, "regular file"):
            mod._stage_stream("receipt.json", io.BytesIO(self.sample))
        self.assertEqual(target.read_bytes(), b"report untouched")

    def test_hash_mismatch_retains_prior_and_cleans_temp(self):
        existing = mod.OUTPUT / "nested/model.gltf"
        existing.parent.mkdir()
        existing.write_bytes(b"previous")
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            mod._stage_stream("nested/model.gltf", io.BytesIO(self.sample), "0" * 64)
        self.assertEqual(existing.read_bytes(), b"previous")
        self.assertEqual(sorted(p.name for p in existing.parent.iterdir()), ["model.gltf"])

    def test_exceeds_limit_cleans_temp_and_existing(self):
        before = mod.MAX_BYTES
        self.addCleanup(lambda: setattr(mod, "MAX_BYTES", before))
        mod.MAX_BYTES = 3
        existing = mod.OUTPUT / "model.bin"
        existing.write_bytes(b"untouched")
        with self.assertRaisesRegex(ValueError, "byte limit"):
            mod._stage_stream("model.bin", io.BytesIO(self.sample), self.sha)
        self.assertEqual(existing.read_bytes(), b"untouched")
        self.assertEqual([x.name for x in mod.OUTPUT.iterdir()], ["model.bin"])

    def test_correct_digest_commits_atomically(self):
        actual, size = mod._stage_stream("nested/model.gltf", io.BytesIO(self.sample), self.sha)
        self.assertEqual((actual, size), (self.sha, len(self.sample)))
        self.assertEqual((mod.OUTPUT / "nested/model.gltf").read_bytes(), self.sample)
        self.assertEqual(len(list((mod.OUTPUT / "nested").iterdir())), 1)

    def test_unsafe_lexical_paths_rejected(self):
        for path in ("../foo", "/absolute", "folder/../../escape", "", "\\bad"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                mod.validate_path(path)


if __name__ == "__main__":
    unittest.main()
