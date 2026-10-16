#!/usr/bin/env python3
"""Offline origin and redirect security checks for the Poly Haven staging script."""
import importlib.util
from pathlib import Path
import unittest
from urllib.request import Request

SCRIPT = Path(__file__).parent / "stage-polyhaven-coast.py"
spec = importlib.util.spec_from_file_location("polyhaven_staging", SCRIPT)
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


class StageOriginTests(unittest.TestCase):
    """Fail closed before contacting a non-approved origin."""

    def test_approved_origin(self):
        """Both official API and distribution hosts are accepted."""
        stage.approved_url("https://api.polyhaven.com/files/aerial_beach_01",
                           {"api.polyhaven.com"})
        stage.approved_url("https://dl.polyhaven.org/assets/test.png",
                           {"dl.polyhaven.org"})

    def test_unsafe_origin(self):
        """Reject insecure scheme, impostor domain, credentials and odd port."""
        for address in [
            "http://dl.polyhaven.org/test.png",
            "file:///etc/passwd",
            "https://dl.polyhaven.org.evil.test/test.png",
            "https://user:pass@dl.polyhaven.org/test.png",
            "https://dl.polyhaven.org:444/test.png",
        ]:
            with self.subTest(address=address), self.assertRaises(ValueError):
                stage.approved_url(address, {"dl.polyhaven.org"})

    def test_redirect_does_not_cross_host_boundary(self):
        """Reject a redirect outside approved hosts before following it."""
        for address in ("https://evil.test/file", "file:///etc/passwd"):
            with self.subTest(address=address), self.assertRaises(ValueError):
                stage.ApprovedRedirects().redirect_request(
                    Request("https://dl.polyhaven.org/file"),
                    None, 302, "Found", {}, address
                )

    def test_candidate_allowlist(self):
        """Unscreened asset IDs never enter the staging pipeline."""
        with self.assertRaisesRegex(ValueError, "allowlist"):
            stage.main("../unapproved")


if __name__ == "__main__":
    unittest.main()
