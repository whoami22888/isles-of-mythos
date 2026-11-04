#!/usr/bin/env python3
"""Stage hash-pinned Poly Haven GLTF model closures for visual review.

This command only writes to IOM_STAGE_DIR (default: asset-staging/models). It
never edits client-godot or the production asset manifest. Every file is
restricted to the official Poly Haven download host and verified by SHA-256.
"""
from __future__ import annotations

import hashlib
import io
import json
import os
import secrets
import stat
from pathlib import Path, PurePosixPath
import sys
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs/graphics/polyhaven-model-candidates.json"
OUTPUT = Path(os.environ.get("IOM_STAGE_DIR", "asset-staging/models")).absolute()
MAX_BYTES = 128 * 1024 * 1024
HOSTS = {"dl.polyhaven.org"}
UA = "IslesOfMythos-CI/1.0 (Godot4.7.2-AssetPipeline)"


def approved_url(url: str) -> None:
    parsed = urlparse(url)
    if (parsed.scheme != "https" or parsed.hostname not in HOSTS
            or parsed.username or parsed.password
            or parsed.port not in (None, 443)):
        raise ValueError("Unapproved Poly Haven download origin")


class ApprovedRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: D401
        approved_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


OPENER = build_opener(ApprovedRedirects())


def validate_path(path: str) -> Path:
    if not isinstance(path, str) or not path or "\\" in path:
        raise ValueError("Unsafe staged model path")
    rel = PurePosixPath(path)
    if rel.is_absolute() or ".." in rel.parts or rel.name in ("", ".", ".."):
        raise ValueError("Unsafe staged model path")
    return OUTPUT / rel


def _stage_stream(path: str, source, expected: str | None = None) -> tuple[str, int]:
    """Verify a temporary download before atomic publication inside staging.

    Directory descriptors and O_NOFOLLOW reject parent and final-file symlinks,
    including attempts to redirect writes outside IOM_STAGE_DIR.
    """
    validate_path(path)
    if expected is not None and (not isinstance(expected, str) or len(expected) != 64
                                 or any(c not in "0123456789abcdef" for c in expected)):
        raise ValueError("Invalid SHA-256 in model manifest")
    rel = PurePosixPath(path)
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    directory = os.open(OUTPUT, directory_flags)
    temp_name = None
    created = False
    try:
        for part in rel.parts[:-1]:
            try:
                os.mkdir(part, dir_fd=directory)
            except FileExistsError:
                pass
            child = os.open(part, directory_flags, dir_fd=directory)
            os.close(directory)
            directory = child
        try:
            existing = os.stat(rel.name, dir_fd=directory, follow_symlinks=False)
        except FileNotFoundError:
            existing = None
        if existing is not None and not stat.S_ISREG(existing.st_mode):
            raise ValueError("Staged model destination must be a regular file")
        temp_name = f".{rel.name}.{secrets.token_hex(12)}.tmp"
        fd = os.open(temp_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=directory)
        created = True
        digest = hashlib.sha256()
        size = 0
        with os.fdopen(fd, "wb") as output:
            while chunk := source.read(65536):
                size += len(chunk)
                if size > MAX_BYTES:
                    raise ValueError("Staged model file exceeds byte limit")
                digest.update(chunk)
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        actual = digest.hexdigest()
        if expected is not None and actual != expected:
            raise ValueError(f"SHA-256 mismatch for {path}: {actual}")
        try:
            existing = os.stat(rel.name, dir_fd=directory, follow_symlinks=False)
        except FileNotFoundError:
            existing = None
        if existing is not None and not stat.S_ISREG(existing.st_mode):
            raise ValueError("Staged model destination must be a regular file")
        os.replace(temp_name, rel.name, src_dir_fd=directory, dst_dir_fd=directory)
        created = False
        os.fsync(directory)
        return actual, size
    finally:
        if created:
            os.unlink(temp_name, dir_fd=directory)
        os.close(directory)


def download(entry: dict) -> dict:
    path = entry["path"]
    validate_path(path)
    approved_url(entry["download_url"])
    expected = entry["sha256"]
    if not isinstance(expected, str) or len(expected) != 64 or any(
            c not in "0123456789abcdef" for c in expected):
        raise ValueError("Invalid SHA-256 in model manifest")
    request = Request(entry["download_url"], headers={"User-Agent": UA, "Accept": "*/*"})
    with OPENER.open(request, timeout=45) as response:
        approved_url(response.url)
        actual, size = _stage_stream(path, response, expected)
    return {"path": path, "sha256": actual, "bytes": size}


def main() -> int:
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1 or payload.get("license") != "CC0-1.0":
        raise ValueError("Model candidate manifest is not an explicit CC0 v1 manifest")
    entries = payload.get("files")
    if not entries or not isinstance(entries, list):
        raise ValueError("Model candidate manifest has no files")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    staged = [download(entry) for entry in entries]
    receipt = {"status": "candidate-not-approved", "source": payload["source"],
               "license": payload["license"], "license_url": payload["license_url"],
               "files": staged}
    _stage_stream("receipt.json", io.BytesIO((json.dumps(receipt, indent=2) + "\n").encode()))
    print(f"Staged {len(staged)} model-closure files for visual/import review")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"Model staging blocked: {exc}", file=sys.stderr)
        raise SystemExit(1)
