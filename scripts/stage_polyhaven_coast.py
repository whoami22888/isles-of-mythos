#!/usr/bin/env python3
"""Stage a Poly Haven coastal texture for review, never auto-admit it to Godot."""
import hashlib
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

APPROVED = {
    "aerial_beach_01", "coast_sand_rocks_02", "seaside_rock"
}
MAPS = {"Diffuse", "Normal", "Rough", "AO", "Displacement"}
OUTPUT = Path(os.environ.get("IOM_STAGE_DIR", "asset-staging")).resolve()
MAX_BYTES = 16 * 1024 * 1024


def approved_url(url, hosts):
    """Enforce HTTPS and an exact expected domain."""
    parsed_url = urlparse(url)
    if (
        parsed_url.scheme != "https"
        or parsed_url.hostname not in hosts
        or parsed_url.username
        or parsed_url.password
        or parsed_url.port not in (None, 443)
    ):
        raise ValueError("Unapproved URL origin")


class ApprovedRedirects(HTTPRedirectHandler):
    """Reject redirects before opening an untrusted network location."""

    # The urllib redirect hook requires this seven-argument signature.
    def redirect_request(  # pylint: disable=too-many-arguments
        self, req, fp, code, msg, headers, newurl
    ):
        """Permit only approved Poly Haven download and API origins."""
        approved_url(newurl, {"api.polyhaven.com", "dl.polyhaven.org"})
        return super().redirect_request(req, fp, code, msg, headers, newurl)


OPENER = build_opener(ApprovedRedirects())


def get_json(url):
    """Read official API metadata with service-identifying user-agent."""
    approved_url(url, {"api.polyhaven.com"})
    req = Request(url, headers={"User-Agent": "IslesOfMythosAssetHarvester/1.0"})
    with OPENER.open(req, timeout=30) as response:
        approved_url(response.url, {"api.polyhaven.com"})
        return json.load(response)


def select_maps(tree):
    """Choose the official 1K PNG variants, excluding unknown metadata."""
    texture = tree.get("Diffuse") or tree.get("diffuse")
    if not isinstance(texture, dict):
        # Poly Haven texture file tree uses {map: {resolution: {format: metadata}}}.
        raise ValueError("No diffuse map available")
    result = {}
    for map_name in MAPS:
        maps = tree.get(map_name, {})
        entries = maps.get("1k", {}) if isinstance(maps, dict) else {}
        variant = entries.get("png") if isinstance(entries, dict) else None
        if isinstance(variant, dict) and variant.get("url"):
            result[map_name] = variant
    if "Diffuse" not in result:
        raise ValueError("Missing 1k PNG diffuse map; inspect API listing manually")
    return result


def main(asset_id):
    """Stage bytes and hashes; never modify the production asset manifest."""
    if asset_id not in APPROVED:
        raise ValueError("Asset not on candidate allowlist")
    files = get_json(f"https://api.polyhaven.com/files/{asset_id}")
    maps = select_maps(files)
    OUTPUT.mkdir(parents=True, exist_ok=True)  # pylint: disable=no-member
    record = {"id": asset_id, "source_url": f"https://polyhaven.com/a/{asset_id}",
              "license": "CC0-1.0", "license_url": "https://polyhaven.com/license",
              "status": "candidate-not-approved", "files": []}
    for kind, item in sorted(maps.items()):
        url = item["url"]
        approved_url(url, {"dl.polyhaven.org"})
        request = Request(url, headers={"User-Agent": "IslesOfMythosAssetHarvester/1.0"})
        with OPENER.open(request, timeout=45) as response:
            approved_url(response.url, {"dl.polyhaven.org"})
            data = response.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ValueError("File exceeds staging limit")
        name = f"{asset_id}_{kind.lower()}_1k.png"
        (OUTPUT / name).write_bytes(data)  # pylint: disable=no-member
        record["files"].append({"path": name, "url": url,
                                "sha256": hashlib.sha256(data).hexdigest(),
                                "bytes": len(data)})
    (OUTPUT / "candidate.json").write_text(  # pylint: disable=no-member
        json.dumps(record, indent=2) + "\n"
    )
    print(f"Staged {len(record['files'])} map(s) for {asset_id}; visual review required")


if __name__ == "__main__":
    try:
        main(sys.argv[1] if len(sys.argv) > 1 else "aerial_beach_01")
    except (ValueError, OSError, KeyError) as exc:
        print(f"Staging failed: {exc}", file=sys.stderr)
        sys.exit(1)
