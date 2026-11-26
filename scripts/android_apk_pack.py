#!/usr/bin/env python3
"""Inspect and repair Godot Android APK project-pack packaging.

Godot 4.7 template/Gradle exports can ZIP-DEFLATE assets/project.binary.
The Android loader cannot reliably AAsset/mmap a compressed project.binary,
which surfaces as: Couldn't load project data at path "". Is the .pck file missing?

Commands:
  check <apk>   Exit 0 only if a project pack is present and project.binary
                (when present) is ZIP-stored (compress_type 0).
  store <apk>   Rewrite the APK so project.binary / *.pck / *.sparsepck / _cl_
                are ZIP-stored. Optionally zipalign + apksigner resign.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

PROJECT_BINARY = "assets/project.binary"
SPARSE_PCK = "assets/assets.sparsepck"
CMDLINE = "assets/_cl_"
STORE_ALWAYS = {PROJECT_BINARY, SPARSE_PCK, CMDLINE}

ZIP_STORED = zipfile.ZIP_STORED


def iter_pack_names(names: list[str]) -> list[str]:
    found = []
    for name in names:
        lower = name.lower()
        if name == PROJECT_BINARY or name == SPARSE_PCK:
            found.append(name)
        elif lower.endswith(".pck") or lower.endswith(".sparsepck"):
            if name.startswith("assets/") or "/" not in name:
                found.append(name)
    return found


def inspect_apk(apk: Path) -> dict:
    if not apk.is_file() or apk.stat().st_size <= 0:
        return {"ok": False, "errors": [f"APK is missing or empty: {apk}"], "entries": {}}
    errors: list[str] = []
    entries: dict[str, dict] = {}
    try:
        with zipfile.ZipFile(apk) as zf:
            names = zf.namelist()
            packs = iter_pack_names(names)
            if PROJECT_BINARY in names:
                info = zf.getinfo(PROJECT_BINARY)
                entries[PROJECT_BINARY] = {
                    "compress_type": info.compress_type,
                    "file_size": info.file_size,
                    "compress_size": info.compress_size,
                }
                if info.file_size <= 0:
                    errors.append("assets/project.binary is empty")
                if info.compress_type != ZIP_STORED:
                    errors.append(
                        "assets/project.binary is DEFLATE-compressed "
                        f"(compress_type={info.compress_type}); it must be ZIP-stored"
                    )
                header = zf.read(PROJECT_BINARY)[:4]
                if header != b"ECFG":
                    errors.append(
                        f"assets/project.binary has unexpected header {header!r} (expected ECFG)"
                    )
            elif not packs:
                errors.append(
                    "APK is missing a Godot project pack: expected assets/project.binary "
                    "and/or assets/*.pck / assets/*.sparsepck"
                )
            if not packs and PROJECT_BINARY not in names:
                pass  # already reported
            elif not packs and PROJECT_BINARY in names:
                # project.binary alone is the exported config; sparse/classic pck should also exist
                # for a complete Godot 4.7 Android export, but allow config-only if ECFG is present.
                pass
            for name in packs:
                info = zf.getinfo(name)
                entries[name] = {
                    "compress_type": info.compress_type,
                    "file_size": info.file_size,
                    "compress_size": info.compress_size,
                }
                if info.file_size <= 0:
                    errors.append(f"{name} is empty")
            if PROJECT_BINARY not in names and packs:
                # A sidecar .pck is fine, but this project's export uses project.binary + sparsepck.
                errors.append("assets/project.binary is missing")
    except zipfile.BadZipFile as exc:
        errors.append(f"APK is not a valid zip: {exc}")
    return {"ok": not errors, "errors": errors, "entries": entries}


def rewrite_stored(src: Path, dst: Path) -> list[str]:
    forced: list[str] = []
    tmp = dst.with_suffix(dst.suffix + ".partial")
    if tmp.exists():
        tmp.unlink()
    with zipfile.ZipFile(src, "r") as zin, zipfile.ZipFile(tmp, "w") as zout:
        for info in zin.infolist():
            name = info.filename
            if name.startswith("META-INF/"):
                continue
            data = zin.read(name)
            new = zipfile.ZipInfo(filename=name, date_time=info.date_time)
            new.external_attr = info.external_attr
            new.create_system = info.create_system
            new.flag_bits = info.flag_bits & ~0x8
            store = (
                name in STORE_ALWAYS
                or name.lower().endswith(".pck")
                or name.lower().endswith(".sparsepck")
            )
            new.compress_type = ZIP_STORED if store else info.compress_type
            if store and info.compress_type != ZIP_STORED:
                forced.append(f"{name} {info.compress_type}->0 {info.file_size}b")
            zout.writestr(new, data)
    tmp.replace(dst)
    return forced


def default_debug_keystore() -> tuple[Path, str, str] | None:
    password = "android"
    alias = "androiddebugkey"
    candidates = [
        Path.home() / ".android" / "debug.keystore",
        Path.home() / ".local/share/godot/keystores/debug.keystore",
    ]
    for path in candidates:
        if path.is_file():
            return path, alias, password
    return None


def find_build_tool(name: str, build_tools: str | None) -> str:
    if build_tools:
        candidate = Path(build_tools) / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    android_home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or ""
    if android_home:
        tools = sorted(Path(android_home).joinpath("build-tools").glob(f"*/{name}"))
        if tools:
            return str(tools[-1])
    which = shutil.which(name)
    if which:
        return which
    raise SystemExit(f"{name} not found (set --build-tools or ANDROID_HOME)")


def resign(apk: Path, keystore: Path, alias: str, password: str, build_tools: str | None) -> None:
    zipalign = find_build_tool("zipalign", build_tools)
    apksigner = find_build_tool("apksigner", build_tools)
    with tempfile.TemporaryDirectory(prefix="apkpack-") as td:
        aligned = Path(td) / "aligned.apk"
        subprocess.check_call([zipalign, "-f", "-p", "4", str(apk), str(aligned)])
        signed = Path(td) / "signed.apk"
        shutil.copy2(aligned, signed)
        subprocess.check_call(
            [
                apksigner,
                "sign",
                "--ks",
                str(keystore),
                "--ks-key-alias",
                alias,
                "--ks-pass",
                f"pass:{password}",
                "--key-pass",
                f"pass:{password}",
                "--v2-signing-enabled",
                "true",
                "--v3-signing-enabled",
                "true",
                str(signed),
            ]
        )
        subprocess.check_call([apksigner, "verify", str(signed)])
        shutil.copy2(signed, apk)
        idsig = Path(str(signed) + ".idsig")
        if idsig.exists():
            shutil.copy2(idsig, Path(str(apk) + ".idsig"))


def cmd_check(apk: Path) -> int:
    result = inspect_apk(apk)
    for name, meta in result["entries"].items():
        print(
            f"{name}: compress_type={meta['compress_type']} "
            f"size={meta['file_size']} compressed={meta['compress_size']}"
        )
    if result["ok"]:
        print(f"OK: {apk} has a stored Godot project pack")
        return 0
    for error in result["errors"]:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1


def cmd_store(args: argparse.Namespace) -> int:
    src = Path(args.apk).resolve()
    out = Path(args.output).resolve() if args.output else src
    if not src.is_file():
        print(f"ERROR: APK not found: {src}", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory(prefix="apkstore-") as td:
        rewritten = Path(td) / "rewritten.apk"
        forced = rewrite_stored(src, rewritten)
        for line in forced:
            print(f"stored {line}")
        if not forced:
            print("project pack entries were already ZIP-stored")
        keystore = Path(args.keystore).resolve() if args.keystore else None
        alias = args.alias
        password = None
        if args.storepass_file:
            password = Path(args.storepass_file).read_text().strip()
        elif args.storepass:
            password = args.storepass
        if args.debug_keystore or (args.resign and not keystore):
            discovered = default_debug_keystore()
            if discovered:
                keystore, alias, password = discovered
                print(f"using debug keystore {keystore}")
            elif not keystore:
                print("ERROR: no debug keystore found; pass --keystore", file=sys.stderr)
                return 1
        if args.resign or keystore:
            if not keystore or not password or not alias:
                print("ERROR: resign requires --keystore/--debug-keystore and a password", file=sys.stderr)
                return 1
            resign(rewritten, keystore, alias, password, args.build_tools)
        if out.exists() and out.samefile(src):
            # replace in place
            tmp_out = out.with_suffix(out.suffix + ".new")
            shutil.copy2(rewritten, tmp_out)
            tmp_out.replace(out)
        else:
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(rewritten, out)
    result = inspect_apk(out)
    if not result["ok"]:
        for error in result["errors"]:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"OK: wrote stored pack to {out}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    check = sub.add_parser("check", help="Fail if the project pack is missing or project.binary is DEFLATE")
    check.add_argument("apk")

    store = sub.add_parser("store", help="Rewrite project.binary / packs as ZIP-stored and optionally resign")
    store.add_argument("apk")
    store.add_argument("--output")
    store.add_argument("--keystore")
    store.add_argument("--storepass")
    store.add_argument("--storepass-file")
    store.add_argument("--alias", default="androiddebugkey")
    store.add_argument("--debug-keystore", action="store_true")
    store.add_argument("--resign", action="store_true")
    store.add_argument("--build-tools")

    args = parser.parse_args(argv)
    if args.command == "check":
        return cmd_check(Path(args.apk))
    return cmd_store(args)


if __name__ == "__main__":
    sys.exit(main())
