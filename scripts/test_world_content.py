"""Tests-first for the independent Isle population/presentation catalogue."""
import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from world_content import (ContentError, select_visible, validate_catalog,
                           verify_admitted_assets, verify_downloaded_bytes)


class ContentTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = {
            "schema_version": 1,
            "archetypes": [
                {"id": "seafarer", "kind": "character", "biomes": ["harbour"], "asset_id": None},
                {"id": "brig", "kind": "vessel", "biomes": ["harbour"], "asset_id": None},
                {"id": "serpent", "kind": "creature", "biomes": ["reef"], "asset_id": None},
            ],
            "asset_records": [],
            "lighting_candidates": [],
            "encounter_shots": [{"id": "harbour_skirmish", "biome": "harbour",
                                 "cast": ["seafarer", "brig"], "lighting": "harbour_sunset"}],
            "light_profiles": [{"id": "harbour_sunset", "candidate_asset": None,
                                "time": "sunset", "exposure": 0.85}],
        }

    def approved(self):
        blob = b"[gd_scene format=3]\n[node name='CREW' type='Node3D']\n"
        scene = self.root / "ship.tscn"
        scene.write_bytes(blob)
        record = {"id": "approved-ship", "status": "approved", "path": "ship.tscn",
                  "sha256": hashlib.sha256(blob).hexdigest(), "bytes": len(blob),
                  "license": "CC0-1.0", "source_url": "https://example.org/creator/ship",
                  "attribution": "Demo fixture", "pbr": True, "lod_levels": 2,
                  "rigged": True, "visual_review": "approved"}
        self.base["asset_records"] = [record]
        self.base["archetypes"][1]["asset_id"] = record["id"]
        return record

    def test_unadmitted_archetypes_do_not_spawn(self):
        validate_catalog(self.base)
        events = [{"id": "v1", "archetype": "brig", "position": [2, 0, 0]}]
        self.assertEqual([], select_visible(self.base, events, [0, 0, 0], self.root))

    def test_rejects_unknown_archetype_reference(self):
        self.base["encounter_shots"][0]["cast"].append("alien")
        with self.assertRaises(ContentError):
            validate_catalog(self.base)

    def test_rejects_duplicate_ids(self):
        self.base["archetypes"].append(dict(self.base["archetypes"][0]))
        with self.assertRaises(ContentError):
            validate_catalog(self.base)

    def test_rejects_unapproved_premium_placeholder(self):
        record = self.approved()
        record["status"] = "candidate"
        with self.assertRaises(ContentError):
            validate_catalog(self.base)

    def test_requires_content_digest_for_approved_asset(self):
        record = self.approved()
        del record["sha256"]
        with self.assertRaises(ContentError):
            validate_catalog(self.base)

    def test_blocks_symlink_and_byte_tampering(self):
        self.approved()
        self.assertEqual(["ship.tscn"], verify_admitted_assets(self.base, self.root))
        scene = self.root / "ship.tscn"
        scene.write_bytes(b"tampered")
        with self.assertRaises(ContentError):
            verify_admitted_assets(self.base, self.root)
        scene.unlink()
        outside = self.root.parent / "outside-content-fixture.tscn"
        outside.write_bytes(b"outside")
        self.addCleanup(lambda: outside.unlink(missing_ok=True))
        scene.symlink_to(outside)
        with self.assertRaises(ContentError):
            verify_admitted_assets(self.base, self.root)

    def test_deterministic_distance_order_and_budget(self):
        self.approved()
        entities = [
            {"id": "far", "archetype": "brig", "position": [9, 0, 0]},
            {"id": "nearB", "archetype": "brig", "position": [2, 0, 0]},
            {"id": "nearA", "archetype": "brig", "position": [2, 0, 0]},
        ]
        a = select_visible(self.base, entities, [0, 0, 0], self.root, max_total=2)
        b = select_visible(self.base, list(reversed(entities)), [0, 0, 0], self.root, max_total=2)
        self.assertEqual(["nearA", "nearB"], [x["id"] for x in a])
        self.assertEqual(a, b)

    def test_distance_cull_and_low_lod_selection(self):
        self.approved()
        entities = [{"id": "a", "archetype": "brig", "position": [80, 0, 0]},
                    {"id": "b", "archetype": "brig", "position": [250, 0, 0]}]
        selection = select_visible(self.base, entities, [0, 0, 0], self.root,
                                   max_distance=100, near_distance=30)
        self.assertEqual(["a"], [x["id"] for x in selection])
        self.assertEqual(1, selection[0]["lod_hint"])

    def test_rejects_nonfinite_and_invalid_positions(self):
        self.approved()
        for position in ([float("nan"), 0, 0], [0, "2", 0], [1, 2], [float("inf"), 0, 0]):
            self.assertEqual([], select_visible(self.base, [{"id": "x", "archetype": "brig",
                                                         "position": position}], [0, 0, 0], self.root))

    def test_blocks_path_escape(self):
        self.approved()["path"] = "../outside.tscn"
        with self.assertRaises(ContentError):
            validate_catalog(self.base)

    def test_rejects_improper_license_or_missing_provenance(self):
        self.approved()["license"] = "unknown"
        with self.assertRaises(ContentError):
            validate_catalog(self.base)

    def test_rejects_duplicate_entities_without_double_render(self):
        self.approved()
        entry = {"id": "same", "archetype": "brig", "position": [1, 0, 1]}
        self.assertEqual(1, len(select_visible(self.base, [entry, entry], [0, 0, 0], self.root)))

    def test_hdri_metadata_and_safety(self):
        candidate = {"id": "sunset", "status": "candidate", "path": "lighting/sunset.hdr",
                     "source_url": "https://polyhaven.com/a/venice_sunset",
                     "download_url": "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/venice_sunset_1k.hdr",
                     "bytes": 4, "md5": hashlib.md5(b"ABCD").hexdigest(),
                     "sha256": hashlib.sha256(b"ABCD").hexdigest(),
                     "license": "CC0-1.0", "format": "hdr"}
        self.base["lighting_candidates"] = [candidate]
        validate_catalog(self.base)
        verify_downloaded_bytes(candidate, b"ABCD")
        with self.assertRaises(ContentError):
            verify_downloaded_bytes(candidate, b"ABCE")
        candidate["download_url"] = "https://evil.com/content"
        with self.assertRaises(ContentError):
            validate_catalog(self.base)

    def test_publisher_md5_passes_but_sha256_mismatch_is_rejected(self):
        candidate = {"id": "sunset", "status": "candidate", "path": "lighting/sunset.hdr",
                     "source_url": "https://polyhaven.com/a/venice_sunset",
                     "download_url": "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/venice_sunset_1k.hdr",
                     "bytes": 4, "md5": hashlib.md5(b"ABCD").hexdigest(),
                     "sha256": hashlib.sha256(b"ABCE").hexdigest(),
                     "license": "CC0-1.0", "format": "hdr"}
        with self.assertRaises(ContentError):
            verify_downloaded_bytes(candidate, b"ABCD")

    def test_receipt_requires_matching_api_asset_slug(self):
        candidate = {"id": "night", "status": "candidate", "path": "lighting/night.hdr",
                     "source_url": "https://polyhaven.com/a/rogland_moonlit_night",
                     "download_url": "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/other_1k.hdr",
                     "bytes": 4, "md5": hashlib.md5(b"ABCD").hexdigest(),
                     "sha256": hashlib.sha256(b"ABCD").hexdigest(),
                     "license": "CC0-1.0", "format": "hdr"}
        self.base["lighting_candidates"] = [candidate]
        with self.assertRaises(ContentError):
            validate_catalog(self.base)


if __name__ == "__main__":
    unittest.main()
