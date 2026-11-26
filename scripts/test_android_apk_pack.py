#!/usr/bin/env python3
"""Unit tests for the Godot Android APK project-pack inspector and store rewrite."""
from __future__ import annotations

import tempfile
import unittest
import zipfile
from pathlib import Path

import android_apk_pack as pack


def write_apk(path: Path, entries: dict[str, tuple[bytes, int]]) -> None:
    with zipfile.ZipFile(path, "w") as zf:
        for name, (data, compress) in entries.items():
            info = zipfile.ZipInfo(name)
            info.compress_type = compress
            zf.writestr(info, data)


class AndroidApkPackTests(unittest.TestCase):
    def test_deflate_project_binary_fails_check(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            apk = Path(td) / "bad.apk"
            write_apk(
                apk,
                {
                    "assets/project.binary": (b"ECFG" + b"\x00" * 8, zipfile.ZIP_DEFLATED),
                    "assets/assets.sparsepck": (b"GDPC" + b"\x00" * 8, zipfile.ZIP_STORED),
                },
            )
            result = pack.inspect_apk(apk)
            self.assertFalse(result["ok"])
            self.assertTrue(any("DEFLATE" in error for error in result["errors"]))
            self.assertEqual(pack.cmd_check(apk), 1)

    def test_stored_project_binary_and_sparsepck_pass(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            apk = Path(td) / "good.apk"
            write_apk(
                apk,
                {
                    "assets/project.binary": (b"ECFG" + b"\x00" * 8, zipfile.ZIP_STORED),
                    "assets/assets.sparsepck": (b"GDPC" + b"\x00" * 8, zipfile.ZIP_STORED),
                    "assets/_cl_": (b"\x00" * 4, zipfile.ZIP_STORED),
                },
            )
            result = pack.inspect_apk(apk)
            self.assertEqual(result["errors"], [])
            self.assertTrue(result["ok"])
            self.assertEqual(pack.cmd_check(apk), 0)

    def test_missing_pack_fails_check(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            apk = Path(td) / "empty.apk"
            write_apk(apk, {"assets/readme.txt": (b"no pack", zipfile.ZIP_STORED)})
            result = pack.inspect_apk(apk)
            self.assertFalse(result["ok"])
            self.assertTrue(any("missing" in error for error in result["errors"]))

    def test_store_rewrites_deflate_project_binary(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            src = Path(td) / "in.apk"
            out = Path(td) / "out.apk"
            write_apk(
                src,
                {
                    "META-INF/CERT.SF": (b"sig", zipfile.ZIP_STORED),
                    "assets/project.binary": (b"ECFG" + b"payload", zipfile.ZIP_DEFLATED),
                    "assets/assets.sparsepck": (b"GDPC" + b"index", zipfile.ZIP_STORED),
                    "lib/arm64-v8a/libgodot_android.so": (b"so", zipfile.ZIP_STORED),
                },
            )
            self.assertEqual(pack.main(["store", str(src), "--output", str(out)]), 0)
            with zipfile.ZipFile(out) as zf:
                names = zf.namelist()
                self.assertNotIn("META-INF/CERT.SF", names)
                info = zf.getinfo("assets/project.binary")
                self.assertEqual(info.compress_type, zipfile.ZIP_STORED)
                self.assertEqual(zf.read("assets/project.binary"), b"ECFG" + b"payload")
            self.assertEqual(pack.cmd_check(out), 0)


if __name__ == "__main__":
    unittest.main()
