#!/usr/bin/env python3
"""Quarantined, provenance-verified Godot premium-ship audition.

No downloaded file is registered as approved game art; engine footage and
human comparison against the owner's baseline are separate mandatory gates.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

from PIL import Image, ImageChops, ImageStat

_ALLOWED_HOST = 'dl.polyhaven.org'
_BASE_ROUTE = '/file/ph-assets/Models/'
_MAX_BYTES = 25 * 1024 * 1024
_HASH_MD5 = re.compile(r'^[0-9a-f]{32}$')
_HASH_SHA = re.compile(r'^[0-9a-f]{64}$')


class AssetFailure(ValueError):
    """Fail closed on missing, invalid, or non-reproducible game art."""


def _relative(path: str) -> Path:
    if not isinstance(path, str) or '\\' in path or '\0' in path or not path.strip():
        raise AssetFailure('Invalid relative asset path')
    rel = PurePosixPath(path)
    if rel.is_absolute() or '..' in rel.parts or '.' in rel.parts or not rel.parts:
        raise AssetFailure('Unsafe relative asset path')
    return Path(*rel.parts)


def _source(url: str) -> None:
    parsed = urlsplit(url)
    if (parsed.scheme != 'https' or parsed.netloc != _ALLOWED_HOST or
            not parsed.path.startswith(_BASE_ROUTE) or
            parsed.query or parsed.fragment or not parsed.path.split('/')[-1]):
        raise AssetFailure(f'Unexpected download origin/path: {url!r}')


def validate_manifest(data: dict) -> None:
    if (data.get('asset_id') != 'dutch_ship_medium' or
            data.get('publisher') != 'https://polyhaven.com/a/dutch_ship_medium' or
            data.get('license') != 'CC0-1.0'):
        raise AssetFailure('Unknown model, publisher or license')
    files = data.get('files')
    if not isinstance(files, list) or not files:
        raise AssetFailure('Manifest lacks source bytes')
    observed = set()
    for entry in files:
        if not isinstance(entry, dict):
            raise AssetFailure('Invalid file record')
        name = str(_relative(entry.get('path')))
        if name in observed:
            raise AssetFailure('Duplicate source file record')
        observed.add(name)
        _source(entry.get('url', ''))
        if not isinstance(entry.get('size'), int) or not 0 < entry['size'] <= _MAX_BYTES:
            raise AssetFailure('Invalid file size or importer limit')
        if not _HASH_MD5.fullmatch(str(entry.get('md5', ''))):
            raise AssetFailure('No official publisher MD5 evidence')
        if not _HASH_SHA.fullmatch(str(entry.get('sha256', ''))):
            raise AssetFailure('Missing or invalid pinned SHA256')
    for required in ('dutch_ship_medium_1k.gltf',
                     'textures/dutch_ship_medium_sails_diff_1k.jpg',
                     'textures/dutch_ship_medium_sails_alpha_1k.png'):
        if required not in observed:
            raise AssetFailure('Missing material/geometry closure: ' + required)


class _RestrictedRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        _source(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _download(entry: dict, stage: Path) -> dict:
    rel = _relative(entry['path'])
    target = stage.joinpath(rel)
    current = stage
    for part in rel.parts:
        current = current / part
        if current.is_symlink():
            raise AssetFailure('Symlinked destination')
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        raise AssetFailure('Audition source already exists; use fresh staging')
    _source(entry['url'])
    opener = build_opener(_RestrictedRedirect())
    sha = hashlib.sha256()
    # Publisher metadata is MD5 only. This legacy checksum is *not* a security
    # decision: HTTPS origin, exact source length, and independent SHA-256 pins
    # (when available) are validated separately; record all source SHA256s.
    upstream = hashlib.md5(usedforsecurity=False)  # nosec B324
    total = 0
    try:
        with opener.open(Request(entry['url'], headers={'User-Agent':'IslesAssetAudition/1.0'}), timeout=45) as r:
            _source(r.geturl())
            with target.open('xb') as f:
                while True:
                    data = r.read(65536)
                    if not data:
                        break
                    total += len(data)
                    if total > _MAX_BYTES or total > entry['size']:
                        raise AssetFailure('Truncated or oversized source')
                    f.write(data)
                    sha.update(data)
                    upstream.update(data)
        if total != entry['size'] or upstream.hexdigest() != entry['md5']:
            raise AssetFailure('Upstream byte length / metadata checksum mismatch')
        if sha.hexdigest() != entry['sha256']:
            raise AssetFailure('Pinned source SHA256 mismatch')
        return {'path':entry['path'], 'size':total, 'source_sha256':sha.hexdigest(),
                'source_url':entry['url'], 'publisher':'Poly Haven',
                'sha256_is_pinned':bool(entry.get('sha256'))}
    except BaseException:
        target.unlink(missing_ok=True)
        raise


def patch_sail_opacity(stage: Path) -> dict:
    """Deterministically convert the original sail RGB+mask to alpha RGBA."""
    model = stage / 'dutch_ship_medium_1k.gltf'
    raw = json.loads(model.read_text(encoding='utf-8'))
    materials = raw.get('materials', [])
    textures = raw.get('textures', [])
    images = raw.get('images', [])
    sail_matches = [m for m in materials if 'sails' in m.get('name', '').lower()]
    if len(sail_matches) != 1:
        raise AssetFailure('Missing/ambiguous sail material; never fake sail opacity')
    sail = sail_matches[0]
    texid = sail.get('pbrMetallicRoughness', {}).get('baseColorTexture', {}).get('index')
    if not isinstance(texid, int) or not 0 <= texid < len(textures):
        raise AssetFailure('Sail diffuse image not referenced')
    imgid = textures[texid].get('source')
    if not isinstance(imgid, int) or not 0 <= imgid < len(images):
        raise AssetFailure('Missing sail texture image')
    uri = images[imgid].get('uri', '')
    if uri != 'textures/dutch_ship_medium_sails_diff_1k.jpg':
        raise AssetFailure('Unexpected sail albedo source')
    rgb_src = stage / uri
    mask_src = stage / 'textures/dutch_ship_medium_sails_alpha_1k.png'
    with Image.open(rgb_src) as file:
        rgb = file.convert('RGB')
    with Image.open(mask_src) as file:
        mask = file.convert('L')
    if rgb.size != mask.size or not (min(mask.getextrema()) < max(mask.getextrema())):
        raise AssetFailure('Mask size or opacity range invalid')
    rgba = rgb.copy()
    rgba.putalpha(mask)
    newname = 'textures/dutch_ship_medium_sails_rgba_1k.png'
    rgba.save(stage / newname, format='PNG', optimize=False, compress_level=9)
    images[imgid]['uri'] = newname
    images[imgid].pop('mimeType', None)
    sail['alphaMode'] = 'MASK'
    sail['alphaCutoff'] = 0.43
    sail['doubleSided'] = True
    model.write_text(json.dumps(raw, sort_keys=True, separators=(',', ':')) + '\n', encoding='utf-8')
    result = {'model_file':model.name,
              'model_sha256':hashlib.sha256(model.read_bytes()).hexdigest(),
              'rgba_path':newname,
              'sha256':hashlib.sha256((stage / newname).read_bytes()).hexdigest(),
              'details':'Generated from verified CC0 1K source diffuse + separate alpha; not approved.'}
    return result


def validate_engine_frames(directory: Path, min_frames: int = 24, min_width: int = 640) -> bool:
    frames = sorted(directory.glob('frame_*.png'))
    if len(frames) < min_frames:
        raise AssetFailure(f'Only {len(frames)} engine frames; need {min_frames}')
    first, last = None, None
    for i, path in enumerate(frames):
        with Image.open(path) as im:
            if im.width < min_width or im.height < 64:
                raise AssetFailure('Invalid engine render resolution')
            image = im.convert('RGB')
            variance = ImageStat.Stat(image).var
            if max(variance) < 16:
                raise AssetFailure(f'Blank/near-flat render: {path.name}')
            if i == 0:
                first = image.copy()
            if i == len(frames)-1:
                last = image.copy()
    diff = ImageStat.Stat(ImageChops.difference(first, last)).mean
    if max(diff) < 2.0:
        raise AssetFailure('No meaningful temporal change in in-engine capture')
    return True


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifest', type=Path)
    ap.add_argument('--staging', type=Path)
    ap.add_argument('--receipt', type=Path)
    ap.add_argument('--verify-frames', type=Path)
    ap.add_argument('--min-frames', type=int, default=24)
    args = ap.parse_args()
    if args.verify_frames:
        validate_engine_frames(args.verify_frames, args.min_frames)
        print('Godot RGB content and temporal motion validation PASS')
        return
    if args.manifest is None or args.staging is None or args.receipt is None:
        ap.error('Manifest, staging and receipt paths required to stage an audition')
    doc = json.loads(args.manifest.read_text(encoding='utf-8'))
    validate_manifest(doc)
    if args.staging.exists() and any(args.staging.iterdir()):
        raise AssetFailure('Use an empty staging directory')
    args.staging.mkdir(parents=True, exist_ok=True)
    records = [_download(item, args.staging) for item in doc['files']]
    modified = patch_sail_opacity(args.staging)
    # All glTF relative referenced closure checked (URI is relative and exists)
    model = json.loads((args.staging/'dutch_ship_medium_1k.gltf').read_text())
    for img in model.get('images', []):
        rel = _relative(img.get('uri'))
        if not (args.staging/rel).is_file():
            raise AssetFailure('Missing glTF image dependency')
    for buff in model.get('buffers', []):
        rel = _relative(buff.get('uri'))
        if not (args.staging/rel).is_file():
            raise AssetFailure('Missing glTF geometry dependency')
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(json.dumps({'source_assets':records,'transformation':modified,
        'visual_approval':'NOT_VERIFIED', 'runtime_admission':'DENIED',
        'description':'CC0 candidate only. Must show Godot PNG/MP4 at owner video baseline.'},indent=2)+'\n')
    print(f'Staged {len(records)} source files, 1 derived RGBA; NOT admitted')

if __name__ == '__main__':
    main()
