import importlib.util
from pathlib import Path
import tempfile
import unittest

# Run staging containment regressions through the existing model-test entrypoint.
from test_stage_polyhaven_models_security import StageSecurityTests  # noqa: F401

SCRIPT = Path(__file__).parent / 'stage_polyhaven_models.py'
spec = importlib.util.spec_from_file_location('model_stage', SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class ModelStageTests(unittest.TestCase):
    def test_official_origin_only(self):
        mod.approved_url('https://dl.polyhaven.org/file/model.gltf')
        for url in ('http://dl.polyhaven.org/model', 'https://evil.test/model', 'file:///tmp/model'):
            with self.assertRaises(ValueError): mod.approved_url(url)

    def test_path_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            old = mod.OUTPUT
            mod.OUTPUT = Path(tmp)
            try:
                with self.assertRaises(ValueError): mod.validate_path('../escape.gltf')
                with self.assertRaises(ValueError): mod.validate_path('/absolute.gltf')
            finally:
                mod.OUTPUT = old

    def test_manifest_has_dependency_closure_and_hashes(self):
        import json
        payload = json.loads(mod.MANIFEST.read_text())
        self.assertEqual(payload['license'], 'CC0-1.0')
        for asset in payload['assets']:
            names = [entry['path'] for entry in payload['files'] if entry['path'].startswith(asset + '/')]
            self.assertTrue(any(name.endswith('.gltf') for name in names))
            self.assertTrue(any(name.endswith('.bin') for name in names))
            self.assertTrue(any('/textures/' in name for name in names))
        for entry in payload['files']:
            self.assertEqual(len(entry['sha256']), 64)
            self.assertTrue(entry['download_url'].startswith('https://dl.polyhaven.org/'))

if __name__ == '__main__':
    unittest.main()
