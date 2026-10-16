#!/usr/bin/env python3
"""Offline regression checks for hash-pinned external asset downloads."""
# pylint: disable=invalid-name  # CLI entrypoint filenames are referenced by CI.

import hashlib
import importlib.util
from pathlib import Path
from urllib.request import Request
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "asset_fetcher", Path(__file__).parent / "fetch-verified-godot-assets.py"
)
fetcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetcher)


class Response:
    """Mock an HTTP response without contacting a network."""

    def __init__(self, payload, url="https://dl.polyhaven.org/approved"):
        self.payload = payload
        self.url = url
        self.reads = 0

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self, _count):
        self.reads += 1
        return self.payload if self.reads == 1 else b""


class Opener:
    """Inject a controlled response into urllib's opener interface."""

    def __init__(self, response):
        self.response = response

    def open(self, _request, timeout):
        if timeout != 45:
            raise ValueError("Unexpected request timeout")
        return self.response


class FetcherTests(unittest.TestCase):
    """Protect origin checks, digest matching, cleanup and atomic imports."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.old_dest = fetcher.DEST
        fetcher.DEST = Path(self.temp.name) / "external"
        fetcher.DEST.mkdir()
        self.addCleanup(lambda: setattr(fetcher, "DEST", self.old_dest))
        self.target = fetcher.DEST / "terrain.glb"
        self.payload = b"premium-fixture"
        self.digest = hashlib.sha256(self.payload).hexdigest()

    def test_allowed_origin(self):
        """Regression: allowed origin."""
        fetcher.validate_origin("https://dl.polyhaven.org/approved")

    def test_reject_bad_origins(self):
        """Regression: reject bad origins."""
        for url in ("file:///tmp/x", "http://polyhaven.com/x",
                    "https://evil.test/x", "https://evil.test@polyhaven.com/x"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                fetcher.validate_origin(url)

    def test_reject_redirect(self):
        """Regression: reject redirect."""
        with self.assertRaises(ValueError):
            fetcher.ApprovedRedirects().redirect_request(
                Request("https://dl.polyhaven.org/x"), None,
                302, "redirect", {}, "https://evil.test/asset"
            )

    def test_good_hash(self):
        """Regression: good hash."""
        fetcher.download(
            self.target, self.digest, "https://dl.polyhaven.org/approved",
            opener=Opener(Response(self.payload))
        )
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_reject_symlinked_destination(self):
        """A symlink in the asset destination cannot receive downloaded bytes."""
        original_dest = fetcher.DEST
        with tempfile.TemporaryDirectory() as root:
            root_path = Path(root)
            (root_path / "external").mkdir()
            (root_path / "outside").mkdir()
            (root_path / "external" / "linked").symlink_to(
                root_path / "outside", target_is_directory=True
            )
            try:
                fetcher.DEST = root_path / "external"
                with self.assertRaisesRegex(ValueError, "Symlinked"):
                    fetcher.download(
                        fetcher.DEST / "linked" / "terrain.glb", self.digest,
                        "https://dl.polyhaven.org/approved",
                        opener=Opener(Response(self.payload)),
                    )
                self.assertFalse((root_path / "outside" / "terrain.glb").exists())
            finally:
                fetcher.DEST = original_dest

    def test_wrong_digest_cleanup(self):
        """Regression: wrong digest cleanup."""
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            fetcher.download(
                self.target, self.digest, "https://dl.polyhaven.org/approved",
                opener=Opener(Response(b"wrong"))
            )
        self.assertFalse(self.target.exists())
        self.assertEqual(list(self.target.parent.glob(".asset-*")), [])

    def test_oversize_cleanup(self):
        """Regression: oversize cleanup."""
        with self.assertRaisesRegex(ValueError, "byte limit"):
            fetcher.download(
                self.target, self.digest, "https://dl.polyhaven.org/approved",
                opener=Opener(Response(b"x" * (fetcher.MAX_BYTES + 1)))
            )
        self.assertFalse(self.target.exists())

    def test_response_redirect_to_unapproved_host(self):
        """Regression: response redirect to unapproved host."""
        with self.assertRaisesRegex(ValueError, "Unapproved"):
            fetcher.download(
                self.target, self.digest, "https://dl.polyhaven.org/approved",
                opener=Opener(Response(self.payload, "https://evil.test/x"))
            )
        self.assertFalse(self.target.exists())


if __name__ == "__main__":
    unittest.main()
