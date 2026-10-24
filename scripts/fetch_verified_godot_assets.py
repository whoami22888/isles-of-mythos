#!/usr/bin/env python3
"""Download pinned, provenance-checked third-party art from approved HTTPS origins."""

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys
import tempfile
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "client-godot/assets/external-assets.json"
DEST = ROOT / "client-godot/assets/external"
ALLOWED_HOSTS = {"dl.polyhaven.org", "polyhaven.com", "cdn.polyhaven.com"}
MAX_BYTES = 100 * 1024 * 1024


def validate_origin(url):
    """Reject unsafe schemes, credentials and hosts, including redirect targets."""
    parsed = urlparse(url)
    if (parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS
            or parsed.username or parsed.password or parsed.port not in (None, 443)):
        raise ValueError("Unapproved asset download origin")


class ApprovedRedirects(HTTPRedirectHandler):
    """Ensure urllib never follows an off-allowlist HTTP redirect."""

    # urllib requires this exact override signature.
    def redirect_request(  # pylint: disable=too-many-arguments
        self, req, fp, code, msg, headers, *args, **kwargs
    ):
        """Validate every redirect before opening the next URL."""
        newurl = args[0] if args else kwargs["newurl"]
        validate_origin(newurl)
        return super().redirect_request(req, fp, code, msg, headers, *args, **kwargs)


def validate_entry(item):
    """Validate the pinned digest, destination and approved origin."""
    relative = item["path"]
    parts = PurePosixPath(relative)
    if parts.is_absolute() or ".." in parts.parts or "\\" in relative:
        raise ValueError("Unsafe asset path")
    digest = item["sha256"]
    if len(digest) != 64 or any(ch not in "0123456789abcdef" for ch in digest):
        raise ValueError("Invalid SHA-256")
    url = item["download_url"]
    validate_origin(url)
    target = DEST / relative
    current = DEST
    if current.is_symlink():
        raise ValueError("Symlinked asset root")
    for part in parts.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError("Symlinked asset path")
    if not target.resolve().is_relative_to(DEST.resolve()):
        raise ValueError("Unsafe output path")
    return target, digest, url


def validate_destination(target):
    """Reject redirected roots and path components at the point of use."""
    current = DEST
    if current.is_symlink():
        raise ValueError("Symlinked asset root")
    if not target.is_relative_to(DEST):
        raise ValueError("Asset destination outside approved directory")
    for component in target.relative_to(DEST).parts:
        current = current / component
        if current.is_symlink():
            raise ValueError("Symlinked asset destination")


def download(target, digest, url, opener=None):
    """Atomically stream up to MAX_BYTES, verify SHA-256, and clean up on failure."""
    validate_destination(target)
    if target.is_file():
        if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
            raise ValueError("Existing asset hash mismatch")
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp_path = tempfile.mkstemp(prefix=".asset-", dir=target.parent)
    opener = opener or build_opener(ApprovedRedirects())
    try:
        computed = hashlib.sha256()
        count = 0
        request = Request(url, headers={"User-Agent": "IslesOfMythosAssetImporter/1.0"})
        with os.fdopen(descriptor, "wb") as output:
            with opener.open(request, timeout=45) as response:
                validate_origin(response.url)
                while True:
                    chunk = response.read(65536)
                    if not chunk:
                        break
                    count += len(chunk)
                    if count > MAX_BYTES:
                        raise ValueError("Asset exceeds byte limit")
                    computed.update(chunk)
                    output.write(chunk)
        if computed.hexdigest() != digest:
            raise ValueError("Downloaded hash mismatch")
        os.replace(temp_path, target)
        print(f"OK {target}: {count} bytes")
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def verify_generated(target, digest, item):
    """Verify committed derived outputs; never download upstream RGB into an RGBA path."""
    parents = item.get("generated_from")
    if not isinstance(parents, list) or not parents or not all(
        isinstance(parent, str) and parent and parent != item["path"]
        for parent in parents
    ):
        raise ValueError("Invalid generated asset dependencies")
    if not isinstance(item.get("generation_note"), str) or not item["generation_note"]:
        raise ValueError("Generated asset missing reproduction instructions")
    validate_destination(target)
    if not target.is_file():
        raise ValueError(
            "Generated asset missing: rebuild from pinned sources and re-verify SHA-256"
        )
    if target.stat().st_size > MAX_BYTES:
        raise ValueError("Generated asset exceeds byte limit")
    if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
        raise ValueError("Generated asset hash mismatch")


def fetch():
    """Fetch original source bytes; verify locally derived, SHA-pinned outputs."""
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1 or not isinstance(payload.get("assets"), list):
        raise ValueError("Invalid asset manifest")
    for entry in payload["assets"]:
        target, digest, url = validate_entry(entry)
        if "generated_from" in entry:
            verify_generated(target, digest, entry)
        else:
            download(target, digest, url)


if __name__ == "__main__":
    try:
        fetch()
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        print(f"Asset download blocked: {error}", file=sys.stderr)
        sys.exit(1)
