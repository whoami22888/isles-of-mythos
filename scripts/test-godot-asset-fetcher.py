#!/usr/bin/env python3
"""Offline regression checks for hash-pinned external asset downloads."""

import hashlib
import importlib.util
from pathlib import Path
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
        assert timeout == 45
        return self.response


class FetcherTests(unittest.TestCase):
    """Protect origin checks, digest matching, cleanup and atomic imports."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.target = Path(self.temp.name) / "terrain.glb"
        self.payload = b"premium-fixture"
        self.digest = hashlib.sha256(self.payload).hexdigest()

    def test_allowed_origin(self):
        fetcher.validate_origin("https://dl.polyhaven.org/approved")

    def test_reject_bad_origins(self):
        for url in ("file:///tmp/x", "http://polyhaven.com/x",
                    "https://evil.test/x", "https://evil.test@polyhaven.com/x"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                fetcher.validate_origin(url)

    def test_reject_redirect(self):
        from urllib.request import Request
        with self.assertRaises(ValueError):
            fetcher.ApprovedRedirects().redirect_request(
                Request("https://dl.polyhaven.org/x"), None,
                302, "redirect", {}, "https://evil.test/asset"
            )

    def test_good_hash(self):
        fetcher.download(
            self.target, self.digest, "https://dl.polyhaven.org/approved",
            opener=Opener(Response(self.payload))
        )
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_wrong_digest_cleanup(self):
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            fetcher.download(
                self.target, self.digest, "https://dl.polyhaven.org/approved",
                opener=Opener(Response(b"wrong"))
            )
        self.assertFalse(self.target.exists())
        self.assertEqual(list(self.target.parent.glob(".asset-*")), [])

    def test_oversize_cleanup(self):
        with self.assertRaisesRegex(ValueError, "byte limit"):
            fetcher.download(
                self.target, self.digest, "https://dl.polyhaven.org/approved",
                opener=Opener(Response(b"x" * (fetcher.MAX_BYTES + 1)))
            )
        self.assertFalse(self.target.exists())

    def test_response_redirect_to_unapproved_host(self):
        with self.assertRaisesRegex(ValueError, "Unapproved"):
            fetcher.download(
                self.target, self.digest, "https://dl.polyhaven.org/approved",
                opener=Opener(Response(self.payload, "https://evil.test/x"))
            )
        self.assertFalse(self.target.exists())


if __name__ == "__main__":
    unittest.main()
