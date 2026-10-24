#!/usr/bin/env python3
"""Stage hash-pinned Poly Haven GLTF model closures for visual review.

This command only writes to IOM_STAGE_DIR (default: asset-staging/models). It
never edits client-godot or the production asset manifest. Every file is
restricted to the official Poly Haven download host and verified by SHA-256.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs/graphics/polyhaven-model-candidates.json"
OUTPUT = Path(os.environ.get("IOM_STAGE_DIR", "asset-staging/models")).resolve()
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
    rel = PurePosixPath(path)
    if rel.is_absolute() or ".." in rel.parts or "\\" in path:
        raise ValueError("Unsafe staged model path")
    return OUTPUT / rel


def download(entry: dict) -> dict:
    target = validate_path(entry["path"])
    approved_url(entry["download_url"])
    expected = entry["sha256"]
    if len(expected) != 64 or any(c not in "0123456789abcdef" for c in expected):
        raise ValueError("Invalid SHA-256 in model manifest")
    target.parent.mkdir(parents=True, exist_ok=True)
    request = Request(entry["download_url"], headers={"User-Agent": UA, "Accept": "*/*"})
    digest = hashlib.sha256()
    size = 0
    with OPENER.open(request, timeout=45) as response:
        approved_url(response.url)
        with target.open("wb") as output:
            while chunk := response.read(65536):
                size += len(chunk)
                if size > MAX_BYTES:
                    raise ValueError("Staged model file exceeds byte limit")
                digest.update(chunk)
                output.write(chunk)
    actual = digest.hexdigest()
    if actual != expected:
        target.unlink(missing_ok=True)
        raise ValueError(f"SHA-256 mismatch for {entry['path']}: {actual}")
    return {"path": entry["path"], "sha256": actual, "bytes": size}


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
    (OUTPUT / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"Staged {len(staged)} model-closure files for visual/import review")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"Model staging blocked: {exc}", file=sys.stderr)
        raise SystemExit(1)
