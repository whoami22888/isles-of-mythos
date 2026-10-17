import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).parent / "validate_pirate_assets.py"
SPEC = importlib.util.spec_from_file_location("validate_pirate_assets", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PirateAssetManifestTests(unittest.TestCase):
    def test_admitted_payloads_match_pinned_hashes_and_dependencies(self):
        MODULE.validate()


if __name__ == "__main__":
    unittest.main()
