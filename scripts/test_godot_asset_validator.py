#!/usr/bin/env python3
"""Regression tests for the external art manifest validator; no external network."""
from contextlib import ExitStack
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / "validate_godot_assets.py"
spec = importlib.util.spec_from_file_location("godot_asset_validator", SCRIPT)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class AssetValidatorTests(unittest.TestCase):
    """Validate manifest metadata, hashes, paths, and symlink rejection."""

    def setUp(self):
        """Create isolated asset fixtures."""
        contexts = ExitStack()
        self.addCleanup(contexts.close)
        self.temp = contexts.enter_context(tempfile.TemporaryDirectory())
        root = Path(self.temp)
        self.assets = root / "external"
        self.assets.mkdir()
        self.manifest = root / "external-assets.json"
        self.old_manifest, self.old_assets = validator.MANIFEST, validator.ASSETS
        validator.MANIFEST, validator.ASSETS = self.manifest, self.assets
        self.addCleanup(self.restore)
        self.sample = b"verified test bytes"
        self.entry = {
            "id": "terrain-test",
            "path": "terrain.glb",
            "sha256": hashlib.sha256(self.sample).hexdigest(),
            "source_url": "https://polyhaven.com/a/test",
            "download_url": "https://dl.polyhaven.org/terrain.glb",
            "license": "CC0-1.0",
            "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
            "attribution": "Test fixture only",
        }

    def restore(self):
        """Restore module globals."""
        validator.MANIFEST, validator.ASSETS = self.old_manifest, self.old_assets

    def write(self, entries):
        """Write an isolated manifest."""
        self.manifest.write_text(
            json.dumps({"schema_version": 1, "assets": entries}), encoding="utf-8"
        )


    def bounded_lod_fixture(self):
        """Create four source models, their LODs, one texture output and aggregate metadata."""
        asset_names = (
            "tree_small_02",
            "island_tree_01",
            "island_tree_02",
            "coast_rocks_05",
        )
        entries = []
        sources = {}
        outputs = {}
        metadata_rows = []

        for asset in asset_names:
            source_path = f"polyhaven/{asset}/{asset}_1k.gltf"
            source_bytes = f"source-model:{asset}".encode()
            source_file = self.assets / source_path
            source_file.parent.mkdir(parents=True, exist_ok=True)
            source_file.write_bytes(source_bytes)
            source = {
                "id": f"source-{asset}",
                "path": source_path,
                "sha256": hashlib.sha256(source_bytes).hexdigest(),
                "source_url": f"https://polyhaven.com/a/{asset}",
                "download_url": (
                    "https://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/"
                    f"{asset}/{asset}_1k.gltf"
                ),
                "license": "CC0-1.0",
                "license_url": "https://polyhaven.com/license",
                "attribution": "Poly Haven",
                "upstream_md5": "a" * 32,
            }
            entries.append(source)
            sources[asset] = source

            output_path = f"generated/bounded_lods/{asset}.glb"
            output_bytes = f"bounded-lod:{asset}".encode()
            output_file = self.assets / output_path
            output_file.parent.mkdir(parents=True, exist_ok=True)
            output_file.write_bytes(output_bytes)
            output = {
                "id": f"lod-{asset}",
                "path": output_path,
                "sha256": hashlib.sha256(output_bytes).hexdigest(),
                "source_url": source["source_url"],
                "download_url": source["download_url"],
                "license": source["license"],
                "license_url": source["license_url"],
                "attribution": source["attribution"],
                "generated_from": [source_path],
                "generation_note": f"Bounded LOD derived from {source_path}",
            }
            entries.append(output)
            outputs[asset] = output
            metadata_rows.append({
                "asset": asset,
                "before": 1000,
                "after": 900,
                "source_sha256": source["sha256"],
                "output_sha256": output["sha256"],
                "blender": "4.3.2",
            })

        texture_path = (
            "generated/bounded_lods/"
            "island_tree_01_island_tree_01_leaves_diff_1k.jpg"
        )
        texture_bytes = b"derived tree texture"
        texture_file = self.assets / texture_path
        texture_file.write_bytes(texture_bytes)
        texture_source = sources["island_tree_01"]
        texture_entry = {
            "id": "lod-island-tree-01-leaves",
            "path": texture_path,
            "sha256": hashlib.sha256(texture_bytes).hexdigest(),
            "source_url": texture_source["source_url"],
            "download_url": texture_source["download_url"],
            "license": texture_source["license"],
            "license_url": texture_source["license_url"],
            "attribution": texture_source["attribution"],
            "generated_from": [texture_source["path"]],
            "generation_note": "Texture bundled with the island_tree_01 bounded LOD",
        }
        entries.append(texture_entry)

        metadata_path = "generated/bounded_lods/metadata.json"
        metadata_bytes = json.dumps(metadata_rows, indent=2).encode()
        metadata_file = self.assets / metadata_path
        metadata_file.write_bytes(metadata_bytes)
        primary_source = sources["tree_small_02"]
        metadata_entry = {
            "id": "bounded-lod-metadata",
            "path": metadata_path,
            "sha256": hashlib.sha256(metadata_bytes).hexdigest(),
            "source_url": primary_source["source_url"],
            "download_url": primary_source["download_url"],
            "license": primary_source["license"],
            "license_url": primary_source["license_url"],
            "attribution": primary_source["attribution"],
            "generated_from": [sources[name]["path"] for name in asset_names],
            "generation_note": "Aggregate metadata for all four bounded LOD source models",
        }
        entries.append(metadata_entry)
        self.write(entries)
        return entries, sources, outputs, texture_entry, metadata_entry, metadata_file

    def test_empty_manifest(self):
        """Regression: empty manifest."""
        self.write([])
        self.assertEqual(validator.validate(), 0)

    def test_missing_download_url_rejected(self):
        """An approved manifest must be consumable by the pinned fetcher."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        del self.entry["download_url"]
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "missing mandatory"):
            validator.validate()

    def test_unapproved_download_origin_rejected(self):
        """Use the same origin allowlist for validation and acquisition."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        self.entry["download_url"] = "https://evil.test/terrain.glb"
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "Unapproved"):
            validator.validate()

    def test_matching_hash(self):
        """Regression: matching hash."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        self.write([self.entry])
        self.assertEqual(validator.validate(), 0)

    def test_hash_mismatch_rejected(self):
        """Regression: hash mismatch rejected."""
        (self.assets / "terrain.glb").write_bytes(b"tampered")
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            validator.validate()

    def test_unknown_license_rejected(self):
        """Regression: unknown license rejected."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        self.entry["license"] = "unknown"
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "not allowlisted"):
            validator.validate()

    def test_unregistered_file_rejected(self):
        """Regression: unregistered file rejected."""
        self.write([])
        (self.assets / "unsourced.glb").write_bytes(b"unverified")
        with self.assertRaisesRegex(ValueError, "Unregistered"):
            validator.validate()

    def test_import_sidecar_allowed(self):
        """Godot's import and UID sidecars do not count as source art."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        (self.assets / "terrain.glb.import").write_text("[remap]\n")
        (self.assets / "terrain.glb.uid").write_text("uid://test\n")
        self.write([self.entry])
        self.assertEqual(validator.validate(), 0)

    def test_unregistered_hidden_file_rejected(self):
        """Unknown hidden files must not bypass provenance scanning."""
        self.write([])
        (self.assets / ".unreviewed.glb").write_bytes(b"unverified")
        with self.assertRaisesRegex(ValueError, "Unregistered"):
            validator.validate()

    def test_import_texture_copy_requires_registered_source_hash(self):
        """Only byte-identical copies of registered cliff textures are allowed."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        source = (self.assets / "polyhaven/coastal_cliff_01/textures"
                  / "coastal_cliff_01_diff_1k.jpg")
        source.parent.mkdir(parents=True)
        source.write_bytes(b"source texture")
        source_entry = dict(
            self.entry,
            id="texture",
            path=str(source.relative_to(self.assets)),
            sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
            source_url="https://polyhaven.com/a/coastal_cliff_01",
            download_url=("https://dl.polyhaven.org/coastal_cliff_01/"
                          "coastal_cliff_01_diff_1k.jpg"),
            upstream_md5="a" * 32,
        )
        output = (self.assets / "generated/coastal_cliff_blender"
                  / "coastal_cliff_lod1_coastal_cliff_01_diff_1k.jpg")
        output.parent.mkdir(parents=True)
        output.write_bytes(source.read_bytes())
        self.write([self.entry, source_entry])
        self.assertEqual(validator.validate(), 0)
        output.write_bytes(b"unverified bytes")
        with self.assertRaisesRegex(ValueError, "Unregistered"):
            validator.validate()

    def test_tree_lod_extraction_requires_registered_identical_texture(self):
        """Godot's LOD2 extraction cannot admit a modified or unrelated PNG."""
        source_model_path = "polyhaven/island_tree_01/island_tree_01_1k.gltf"
        source_model_bytes = b"verified source model"
        source_model_file = self.assets / source_model_path
        source_model_file.parent.mkdir(parents=True)
        source_model_file.write_bytes(source_model_bytes)
        source_model_entry = {
            "id": "source-island-tree-01",
            "path": source_model_path,
            "sha256": hashlib.sha256(source_model_bytes).hexdigest(),
            "source_url": "https://polyhaven.com/a/island_tree_01",
            "download_url": (
                "https://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/"
                "island_tree_01/island_tree_01_1k.gltf"
            ),
            "license": "CC0-1.0",
            "license_url": "https://polyhaven.com/license",
            "attribution": "Poly Haven",
            "upstream_md5": "a" * 32,
        }
        source = (self.assets / "generated/bounded_lods"
                  / "island_tree_01_island_tree_01_leaves_diff_1k.png")
        source.parent.mkdir(parents=True)
        source.write_bytes(b"approved leaf texture")
        entry = {
            "id": "bounded-lod-island-tree-texture",
            "path": source.relative_to(self.assets).as_posix(),
            "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "source_url": source_model_entry["source_url"],
            "download_url": source_model_entry["download_url"],
            "license": source_model_entry["license"],
            "license_url": source_model_entry["license_url"],
            "attribution": source_model_entry["attribution"],
            "generated_from": [source_model_path],
            "generation_note": "Extracted from the admitted island-tree source model",
        }
        output = (self.assets / "generated/foliage"
                  / "island_tree_01_lod2_island_tree_01_leaves_diff_1k.png")
        output.parent.mkdir(parents=True)
        output.write_bytes(source.read_bytes())
        self.write([source_model_entry, entry])
        self.assertEqual(validator.validate(), 0)
        output.write_bytes(b"different texture")
        with self.assertRaisesRegex(ValueError, "Unregistered"):
            validator.validate()

    def test_path_traversal_rejected(self):
        """Regression: path traversal rejected."""
        self.entry["path"] = "../outside.glb"
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "unsafe path"):
            validator.validate()

    def test_symlinked_file_inside_root_rejected(self):
        """Regression: symlinked file inside root rejected."""
        (self.assets / "real.glb").write_bytes(self.sample)
        (self.assets / "terrain.glb").symlink_to("real.glb")
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "symlinked"):
            validator.validate()

    def test_symlinked_parent_directory_rejected(self):
        """Regression: symlinked parent directory rejected."""
        real = self.assets / "real"
        real.mkdir()
        (real / "terrain.glb").write_bytes(self.sample)
        (self.assets / "alias").symlink_to(real, target_is_directory=True)
        self.entry["path"] = "alias/terrain.glb"
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "symlinked"):
            validator.validate()

    def test_unregistered_symlink_alias_to_registered_file_rejected(self):
        """A symlink alias must not disappear when paths are resolved."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        (self.assets / "alias.glb").symlink_to("terrain.glb")
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "Symlinked"):
            validator.validate()

    def test_symlinked_asset_root_rejected(self):
        """The entire asset root cannot be redirected to another directory."""
        real_root = Path(self.temp) / "actual-assets"
        real_root.mkdir()
        self.assets.rmdir()
        self.assets.symlink_to(real_root, target_is_directory=True)
        self.write([])
        with self.assertRaisesRegex(ValueError, "Symlinked external assets root"):
            validator.validate()

    def test_duplicate_asset_path_rejected(self):
        """Regression: duplicate asset path rejected."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        self.write([self.entry, dict(self.entry, id="duplicate")])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            validator.validate()


    def test_polyhaven_rejects_generic_source_page(self):
        """A generic publisher page cannot establish package provenance."""
        self.entry.update({
            "path": "polyhaven/coast_rocks_05/coast_rocks_05.bin",
            "source_url": "https://polyhaven.com/a/polyhaven",
            "download_url": (
                "https://dl.polyhaven.org/file/ph-assets/Models/gltf/8k/"
                "coast_rocks_05/coast_rocks_05.bin"
            ),
            "upstream_md5": "a" * 32,
        })
        with self.assertRaisesRegex(ValueError, "source does not match"):
            validator.validate_metadata(0, self.entry, set(), set())

    def test_polyhaven_rejects_wrong_package_download(self):
        """Do not accept an asset from a different package just by host."""
        self.entry.update({
            "path": "polyhaven/coast_rocks_05/coast_rocks_05.bin",
            "source_url": "https://polyhaven.com/a/coast_rocks_05",
            "download_url": (
                "https://dl.polyhaven.org/file/ph-assets/Models/gltf/8k/"
                "other_asset/coast_rocks_05.bin"
            ),
            "upstream_md5": "a" * 32,
        })
        with self.assertRaisesRegex(ValueError, "not bound"):
            validator.validate_metadata(0, self.entry, set(), set())

    def test_generated_asset_dependency_must_be_manifested(self):
        """Committed derivatives cannot point to missing source textures."""
        (self.assets / "terrain.glb").write_bytes(self.sample)
        self.entry.update({
            "path": "polyhaven/coast_rocks_05/coast_rocks_05.bin",
            "source_url": "https://polyhaven.com/a/coast_rocks_05",
            "download_url": (
                "https://dl.polyhaven.org/file/ph-assets/Models/gltf/8k/"
                "coast_rocks_05/coast_rocks_05.bin"
            ),
            "generated_from": ["polyhaven/coast_rocks_05/missing-source.png"],
            "generation_note": "Derived locally",
        })
        destination = self.assets / self.entry["path"]
        destination.parent.mkdir(parents=True)
        destination.write_bytes(self.sample)
        (self.assets / "terrain.glb").unlink()
        self.write([self.entry])
        with self.assertRaisesRegex(ValueError, "dependency is absent"):
            validator.validate()


    def test_bounded_lod_lineage_accepts_matching_sources_and_metadata(self):
        """Every bounded LOD output and aggregate row must bind to its actual model."""
        self.bounded_lod_fixture()
        self.assertEqual(validator.validate(), 0)

    def test_bounded_lod_texture_rejects_swapped_source_family(self):
        """A tree texture cannot claim the unrelated coast-rocks source model."""
        entries, sources, _, texture_entry, _, _ = self.bounded_lod_fixture()
        wrong_source = sources["coast_rocks_05"]
        texture_entry["generated_from"] = [wrong_source["path"]]
        texture_entry["source_url"] = wrong_source["source_url"]
        texture_entry["download_url"] = wrong_source["download_url"]
        self.write(entries)
        with self.assertRaisesRegex(ValueError, "Bounded LOD source lineage mismatch"):
            validator.validate()

    def test_bounded_lod_metadata_requires_all_four_source_models(self):
        """Aggregate LOD metadata must record all four source model parents."""
        entries, _, _, _, metadata_entry, _ = self.bounded_lod_fixture()
        metadata_entry["generated_from"] = [
            "polyhaven/coast_rocks_05/coast_rocks_05_1k.gltf"
        ]
        self.write(entries)
        with self.assertRaisesRegex(ValueError, "must list all four source models"):
            validator.validate()

    def test_bounded_lod_metadata_source_sha_must_match_manifest(self):
        """Metadata source hashes must match the admitted source model records."""
        entries, _, _, _, metadata_entry, metadata_file = self.bounded_lod_fixture()
        records = json.loads(metadata_file.read_text(encoding="utf-8"))
        records[0]["source_sha256"] = "0" * 64
        metadata_bytes = json.dumps(records, indent=2).encode()
        metadata_file.write_bytes(metadata_bytes)
        metadata_entry["sha256"] = hashlib.sha256(metadata_bytes).hexdigest()
        self.write(entries)
        with self.assertRaisesRegex(ValueError, "metadata source SHA-256 mismatch"):
            validator.validate()

    def test_bounded_lod_metadata_output_sha_must_match_manifest(self):
        """Metadata output hashes must match the manifested generated GLB."""
        entries, _, _, _, metadata_entry, metadata_file = self.bounded_lod_fixture()
        records = json.loads(metadata_file.read_text(encoding="utf-8"))
        records[0]["output_sha256"] = "f" * 64
        metadata_bytes = json.dumps(records, indent=2).encode()
        metadata_file.write_bytes(metadata_bytes)
        metadata_entry["sha256"] = hashlib.sha256(metadata_bytes).hexdigest()
        self.write(entries)
        with self.assertRaisesRegex(ValueError, "metadata output SHA-256 mismatch"):
            validator.validate()

    def metadata_free_bounded_lod_fixture(self, output_path, source_asset):
        """Create one generated texture and its claimed source without aggregate metadata."""
        source_path = f"polyhaven/{source_asset}/{source_asset}_1k.gltf"
        source = {
            "id": f"source-{source_asset}",
            "path": source_path,
            "sha256": "a" * 64,
            "source_url": f"https://polyhaven.com/a/{source_asset}",
            "download_url": (
                "https://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/"
                f"{source_asset}/{source_asset}_1k.gltf"
            ),
            "license": "CC0-1.0",
            "license_url": "https://polyhaven.com/license",
            "attribution": "Poly Haven",
        }
        output = {
            "id": "bounded-lod-texture-test",
            "path": output_path,
            "sha256": "b" * 64,
            "source_url": source["source_url"],
            "download_url": source["download_url"],
            "license": source["license"],
            "license_url": source["license_url"],
            "attribution": source["attribution"],
            "generated_from": [source_path],
            "generation_note": "Texture-only bounded LOD regression fixture",
        }
        return {source_path: source, output_path: output}

    def test_bounded_lod_texture_only_fixture_requires_matching_source(self):
        """A partial texture fixture remains valid only with its matching source."""
        output_path = (
            "generated/bounded_lods/"
            "island_tree_01_island_tree_01_leaves_diff_1k.jpg"
        )
        registered = self.metadata_free_bounded_lod_fixture(
            output_path, "island_tree_01"
        )
        validator.validate_generated_dependencies(registered)
        self.assertIsNone(validator.validate_bounded_lod_lineage(registered))

    def test_bounded_lod_texture_rejects_wrong_manifested_parent_without_expected_source(self):
        """An unrelated manifested parent cannot stand in for the expected tree model."""
        output_path = (
            "generated/bounded_lods/"
            "island_tree_01_island_tree_01_leaves_diff_1k.jpg"
        )
        registered = self.metadata_free_bounded_lod_fixture(
            output_path, "coast_rocks_05"
        )
        validator.validate_generated_dependencies(registered)
        with self.assertRaisesRegex(
            ValueError, "Bounded LOD source model is not manifested"
        ):
            validator.validate_bounded_lod_lineage(registered)

    def test_bounded_lod_rejects_unknown_texture_family_without_metadata(self):
        """Unknown files cannot bypass lineage checks in the partial bundle path."""
        output_path = "generated/bounded_lods/unlisted_asset_lod1.jpg"
        registered = self.metadata_free_bounded_lod_fixture(
            output_path, "coast_rocks_05"
        )
        validator.validate_generated_dependencies(registered)
        with self.assertRaisesRegex(
            ValueError, "Unknown bounded LOD output family"
        ):
            validator.validate_bounded_lod_lineage(registered)



if __name__ == "__main__":
    unittest.main()
