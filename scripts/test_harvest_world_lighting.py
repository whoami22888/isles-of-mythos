"""Offline deterministic network tests for safe creator-HDRI staging."""
import hashlib
import io
from pathlib import Path
import tempfile
import unittest

from harvest_world_lighting import stage, PolyHavenRedirects
from world_content import ContentError


class BufferedResponse(io.BytesIO):
    def __init__(self, data, url):
        super().__init__(data)
        self.url = url

    def geturl(self):
        return self.url


class ControlledOpener:
    def __init__(self, data, url):
        self.data, self.url = data, url

    def open(self, request, timeout=None):
        return BufferedResponse(self.data, self.url)


class HarvestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        blob = b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n"
        self.blob = blob
        url = 'https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/venice_sunset_1k.hdr'
        self.candidate = {'id': 'harbour_sunset', 'status': 'candidate',
                          'path': 'lighting/venice_sunset_1k.hdr',
                          'source_url': 'https://polyhaven.com/a/venice_sunset',
                          'download_url': url, 'bytes': len(blob),
                          'md5': hashlib.md5(blob).hexdigest(),
                          'format': 'hdr', 'license': 'CC0-1.0'}

    def test_verified_bytes_are_staged_with_sha_receipt(self):
        receipt = stage(self.candidate, self.root, ControlledOpener(self.blob, self.candidate['download_url']))
        self.assertEqual('downloaded_unadmitted', receipt['status'])
        self.assertEqual(hashlib.sha256(self.blob).hexdigest(), receipt['sha256'])
        self.assertEqual(self.blob, (self.root / self.candidate['path']).read_bytes())

    def test_wrong_bytes_never_enter_destination(self):
        with self.assertRaises(ContentError):
            stage(self.candidate, self.root, ControlledOpener(self.blob[:-1], self.candidate['download_url']))
        self.assertFalse((self.root / self.candidate['path']).exists())

    def test_redirected_off_publisher_content_blocked(self):
        with self.assertRaises(ContentError):
            stage(self.candidate, self.root, ControlledOpener(self.blob, 'https://example.org/wrong.hdr'))
        self.assertFalse((self.root / self.candidate['path']).exists())

    def test_symlinked_staging_directory_blocked(self):
        (self.root / 'lighting').symlink_to(self.root.parent, target_is_directory=True)
        with self.assertRaises(ContentError):
            stage(self.candidate, self.root, ControlledOpener(self.blob, self.candidate['download_url']))

    def test_rejects_wrong_subdomain_even_with_name_match(self):
        self.candidate['download_url'] = 'https://dl.polyhaven.org.evil.example/file/ph-assets/HDRIs/hdr/1k/venice_sunset_1k.hdr'
        with self.assertRaises(ContentError):
            stage(self.candidate, self.root, ControlledOpener(self.blob, self.candidate['download_url']))


if __name__ == '__main__':
    unittest.main()
