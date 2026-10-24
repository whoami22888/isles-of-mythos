#!/usr/bin/env python3
"""Offline regression checks for hash-pinned external asset downloads."""

from contextlib import ExitStack
import hashlib
import importlib.util
from pathlib import Path
from urllib.request import Request
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "asset_fetcher", Path(__file__).parent / "fetch_verified_godot_assets.py"
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
        """Enter the controlled response context."""
        return self

    def __exit__(self, *_args):
        """Propagate download exceptions."""
        return False

    def read(self, _count):
        """Return the fixture body once, then EOF."""
        self.reads += 1
        return self.payload if self.reads == 1 else b""


class Opener:  # pylint: disable=too-few-public-methods
    """Inject a controlled response into urllib's opener interface."""

    def __init__(self, response):
        self.response = response

    def open(self, _request, timeout):
        """Return the fixture response using the production timeout."""
        if timeout != 45:
            raise ValueError("Unexpected request timeout")
        return self.response


class FetcherTests(unittest.TestCase):
    """Protect origin checks, digest matching, cleanup and atomic imports."""

    def setUp(self):
        """Keep every test destination inside an isolated approved root."""
        contexts = ExitStack()
        self.addCleanup(contexts.close)
        self.temp = contexts.enter_context(tempfile.TemporaryDirectory())
        self.old_dest = fetcher.DEST
        fetcher.DEST = Path(self.temp) / "external"
        fetcher.DEST.mkdir()
        self.addCleanup(lambda: setattr(fetcher, "DEST", self.old_dest))
        self.target = fetcher.DEST / "terrain.glb"
        self.payload = b"premium-fixture"
        self.digest = hashlib.sha256(self.payload).hexdigest()

    @staticmethod
    def test_allowed_origin():
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

    def test_redirect_keyword_contract(self):
        """The urllib override validates keyword and positional redirect calls."""
        redirect = fetcher.ApprovedRedirects()
        request = Request("https://dl.polyhaven.org/x")
        with self.assertRaises(ValueError):
            redirect.redirect_request(
                request, None, 302, "redirect", {}, newurl="https://evil.test/asset"
            )
        allowed = "https://dl.polyhaven.org/asset"
        result = redirect.redirect_request(
            request, None, 302, "redirect", {}, newurl=allowed
        )
        self.assertEqual(result.full_url, allowed)

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

    def test_reject_symlinked_asset_root(self):
        """Reject a redirected root before reading existing or writing new bytes."""
        outside = Path(self.temp) / "outside"
        outside.mkdir()
        fetcher.DEST.rmdir()
        fetcher.DEST.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Symlinked"):
            fetcher.download(
                self.target, self.digest, "https://dl.polyhaven.org/approved",
                opener=Opener(Response(self.payload)),
            )
        self.assertEqual(list(outside.iterdir()), [])

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


    def test_generated_asset_requires_committed_matching_bytes(self):
        """A derived RGBA output must not fetch a different upstream diffuse."""
        item = {
            "path": "terrain.glb",
            "generated_from": ["source-rgb.jpg", "source-mask.png"],
            "generation_note": "RGB and mask are composed offline",
        }
        with self.assertRaisesRegex(ValueError, "Generated asset missing"):
            fetcher.verify_generated(self.target, self.digest, item)
        self.target.write_bytes(self.payload)
        fetcher.verify_generated(self.target, self.digest, item)
        self.target.write_bytes(b"mismatched-image")
        with self.assertRaisesRegex(ValueError, "Generated asset hash mismatch"):
            fetcher.verify_generated(self.target, self.digest, item)

    def test_generated_asset_rejects_unrecorded_dependencies(self):
        """Never interpret a made-up upstream URL as a reproducible derivative."""
        self.target.write_bytes(self.payload)
        with self.assertRaisesRegex(ValueError, "Invalid generated"):
            fetcher.verify_generated(
                self.target, self.digest,
                {"path": "terrain.glb", "generated_from": ["terrain.glb"],
                 "generation_note": "not reproducible"}
            )

if __name__ == "__main__":
    unittest.main()
