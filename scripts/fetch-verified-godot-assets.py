#!/usr/bin/env python3
"""Download explicitly approved SHA-256-pinned Poly Haven files, never arbitrary URLs."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys
import tempfile
from urllib.parse import urlparse
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "client-godot/assets/external-assets.json"
DEST = ROOT / "client-godot/assets/external"
ALLOWED_HOSTS = {"dl.polyhaven.org", "polyhaven.com", "cdn.polyhaven.com"}
MAX_BYTES = 80 * 1024 * 1024

def fetch() -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("assets"), list):
        raise ValueError("Invalid asset manifest")
    for item in data["assets"]:
        relative = item["path"]
        p = PurePosixPath(relative)
        if p.is_absolute() or ".." in p.parts or "\\" in relative:
            raise ValueError("Unsafe asset path")
        digest = item["sha256"]
        if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            raise ValueError("Invalid SHA-256")
        url = item.get("download_url")
        if not isinstance(url, str):
            raise ValueError("download_url required")
        parsed = urlparse(url)
        if parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS or parsed.username or parsed.password:
            raise ValueError("Unapproved asset download host")
        out = (DEST / relative).resolve()
        if not out.is_relative_to(DEST.resolve()) or out.is_symlink():
            raise ValueError("Unsafe output path")
        if out.is_file():
            if hashlib.sha256(out.read_bytes()).hexdigest() != digest:
                raise ValueError(f"Existing asset hash mismatch: {relative}")
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".asset-", dir=out.parent)
        try:
            sha = hashlib.sha256()
            size = 0
            with os.fdopen(fd, "wb") as target, urlopen(Request(url, headers={"User-Agent": "IslesOfMythosAssetImporter/1.0"}), timeout=45) as response:
                final = urlparse(response.url)
                if final.scheme != "https" or final.hostname not in ALLOWED_HOSTS:
                    raise ValueError("Unapproved redirect host")
                while True:
                    chunk = response.read(65536)
                    if not chunk:
                        break
                    size += len(chunk)
                    if size > MAX_BYTES:
                        raise ValueError("Asset exceeds 80 MiB limit")
                    sha.update(chunk)
                    target.write(chunk)
            if sha.hexdigest() != digest:
                raise ValueError(f"Downloaded hash mismatch: {relative}")
            os.replace(tmp, out)
            print(f"OK {relative}: {size} bytes")
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

if __name__ == "__main__":
    try:
        fetch()
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        print(f"Asset download blocked: {error}", file=sys.stderr)
        sys.exit(1)
