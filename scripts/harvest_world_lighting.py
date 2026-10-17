#!/usr/bin/env python3
"""Stage verified creator HDRIs; an isolated download is not asset admission.

Assets never enter gameplay or client-godot/assets/external automatically.
Only verified receipt-bearing captures can be proposed for graphics review.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
from urllib.request import HTTPRedirectHandler, Request, build_opener

from world_content import ContentError, _candidate, _safe_file, load_catalog


class PolyHavenRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, *args, **kwargs):
        from urllib.parse import urlsplit
        url = args[0] if args else kwargs['newurl']
        u = urlsplit(url)
        if (u.scheme != 'https' or u.hostname != 'dl.polyhaven.org'
                or u.username or u.password or u.port not in (None, 443)):
            raise ContentError('Unapproved asset redirect')
        return super().redirect_request(req, fp, code, msg, headers, *args, **kwargs)


def stage(candidate: dict, destination: Path, opener=None) -> dict:
    """Atomic streaming exact-byte/MD5 validation and SHA-256 staging receipt."""
    _candidate(candidate)
    target = _safe_file(destination, candidate['path'])
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=target.parent, prefix='.iom-source-')
    result = None
    try:
        dig_md5 = hashlib.md5()
        dig_sha256 = hashlib.sha256()
        count = 0
        opener = opener or build_opener(PolyHavenRedirects())
        request = Request(candidate['download_url'], headers={'User-Agent': 'IslesOfMythosContentHarvest/1.0'})
        with os.fdopen(fd, 'wb') as out, opener.open(request, timeout=40) as response:
            from urllib.parse import urlsplit
            actual = urlsplit(response.geturl())
            if actual.scheme != 'https' or actual.hostname != 'dl.polyhaven.org':
                raise ContentError('Off-publisher final redirect')
            while True:
                chunk = response.read(65536)
                if not chunk:
                    break
                count += len(chunk)
                if count > candidate['bytes']:
                    raise ContentError('Asset exceeds published file length')
                dig_md5.update(chunk)
                dig_sha256.update(chunk)
                out.write(chunk)
        if count != candidate['bytes'] or dig_md5.hexdigest() != candidate['md5']:
            raise ContentError('Downloaded HDRI does not match publisher file metadata')
        os.replace(tmp_name, target)
        result = {'id': candidate['id'], 'status': 'downloaded_unadmitted',
                  'path': candidate['path'], 'bytes': count,
                  'md5': dig_md5.hexdigest(), 'sha256': dig_sha256.hexdigest(),
                  'publisher': candidate['source_url'], 'license': candidate['license']}
        return result
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def main() -> int:
    parser = argparse.ArgumentParser(description='Stage officially pinned lighting HDRIs without admitting them into gameplay')
    parser.add_argument('--catalog', type=Path, default=Path('client-godot/content/world_population.json'))
    parser.add_argument('--staging-dir', type=Path, required=True)
    parser.add_argument('--ids', nargs='+', required=True)
    args = parser.parse_args()
    catalog = load_catalog(args.catalog)
    found = {x['id']: x for x in catalog['lighting_candidates']}
    if any(value not in found for value in args.ids):
        raise ContentError('Unrecognized candidate id')
    receipts = [stage(found[k], args.staging_dir) for k in sorted(set(args.ids))]
    args.staging_dir.mkdir(parents=True, exist_ok=True)
    # Strictly staging side only: no mutation to approved asset manifest.
    receipt_path = _safe_file(args.staging_dir, 'source-receipts.json')
    if receipt_path.is_symlink():
        raise ContentError('Unsafe receipt destination')
    receipt_path.write_text(json.dumps(receipts, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print(json.dumps({'staged': len(receipts), 'receipts': str(receipt_path)}, sort_keys=True))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ContentError, OSError, ValueError) as exc:
        raise SystemExit(f'World lighting harvest blocked: {exc}') from exc
