#!/usr/bin/env python3
"""Quarantined Poly Haven pinnace provenance and PBR source inspection.

This script NEVER admits art to player-facing scenes. Render and artistic
comparison against owner's video are separate mandatory gates.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import tempfile
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

from PIL import Image

SOURCE_ID = 'ship_pinnace'
SOURCE_URL = 'https://polyhaven.com/a/ship_pinnace'
ALLOWED_DOMAIN = 'dl.polyhaven.org'
MAX_FILE_BYTES = 32 * 1024 * 1024
SHA256_RE = re.compile(r'[0-9a-f]{64}\Z')
MD5_RE = re.compile(r'[0-9a-f]{32}\Z')
REQUIRED_PARTS = frozenset(('aft','rigging','details','hull','deck','interior','sails'))


class SourceError(ValueError):
    pass


def safe_path(raw: str) -> Path:
    if not isinstance(raw,str) or not raw or '\\' in raw or '\x00' in raw:
        raise SourceError('Noncanonical source path')
    p = PurePosixPath(raw)
    if p.is_absolute() or any(v in ('.','..') for v in raw.split('/')) or p.as_posix() != raw:
        raise SourceError('Untrusted source path')
    return Path(*p.parts)


def _expected_url(relative: str) -> str:
    path=safe_path(relative).as_posix()
    stem = f'https://{ALLOWED_DOMAIN}/file/ph-assets/Models/'
    if path == 'ship_pinnace_1k.gltf':
        return stem+'gltf/1k/ship_pinnace/ship_pinnace_1k.gltf'
    if path == 'ship_pinnace.bin':
        return stem+'gltf/4k/ship_pinnace/ship_pinnace.bin'
    if not path.startswith('textures/') or path.count('/') != 1:
        raise SourceError('Unexpected pinnace dependency name')
    filename=path.split('/')[1]
    if not filename.startswith('ship_pinnace_') or not filename.endswith(('_1k.jpg','_1k.png')):
        raise SourceError('Unrecognised publisher texture')
    fmt='png' if filename.endswith('.png') else 'jpg'
    return stem+f'{fmt}/1k/ship_pinnace/{filename}'


def validate_manifest(doc: dict) -> None:
    if (doc.get('asset_id')!=SOURCE_ID or doc.get('license')!='CC0-1.0'
            or doc.get('publisher')!=SOURCE_URL or doc.get('status')!='quarantined-for-evaluation'):
        raise SourceError('Only official CC0 quarantined pinnace sources may be staged')
    entries=doc.get('files')
    if not isinstance(entries,list) or len(entries)<3:
        raise SourceError('Missing glTF, binary or alpha source')
    seen=set()
    for item in entries:
        if not isinstance(item,dict): raise SourceError('Invalid file record')
        path=safe_path(item.get('path'))
        if path.as_posix() in seen:raise SourceError('Duplicate source path')
        seen.add(path.as_posix())
        expected=_expected_url(path.as_posix())
        if item.get('url')!=expected:raise SourceError('Source does not match pinned publisher route')
        parts=urlsplit(item['url'])
        if (parts.scheme!='https' or parts.netloc!=ALLOWED_DOMAIN or parts.username
                or parts.password or parts.query or parts.fragment):raise SourceError('Unsafe source URL')
        if type(item.get('size')) is not int or not 0 < item['size'] <= MAX_FILE_BYTES:
            raise SourceError('Missing or unsafe source byte limit')
        if not isinstance(item.get('md5'),str) or not MD5_RE.fullmatch(item['md5']):
            raise SourceError('Missing publisher source MD5 metadata')
        pin=item.get('sha256')
        if pin is not None and (not isinstance(pin,str) or not SHA256_RE.fullmatch(pin)):
            raise SourceError('Malformed source SHA-256 pin')
    if not {'ship_pinnace_1k.gltf','ship_pinnace.bin',
            'textures/ship_pinnace_sails_alpha_1k.png'} <= seen:
        raise SourceError('Core source dependencies incomplete')


def inspect_gltf(doc: dict) -> dict:
    if not isinstance(doc,dict) or doc.get('asset',{}).get('version','2.0')!='2.0':
        raise SourceError('Invalid glTF 2 asset')
    nodes={str(n.get('name','')).removeprefix('ship_pinnace_') for n in doc.get('nodes',[])}
    if not REQUIRED_PARTS <= nodes:raise SourceError('Missing original high-detail ship assembly')
    materials={str(m.get('name','')).removeprefix('ship_pinnace_'):m for m in doc.get('materials',[])}
    if not REQUIRED_PARTS <= materials.keys():raise SourceError('Missing source PBR material sections')
    for name in REQUIRED_PARTS:
        mat=materials[name];pbr=mat.get('pbrMetallicRoughness',{})
        if (not pbr.get('baseColorTexture') or not pbr.get('metallicRoughnessTexture')
                or not mat.get('normalTexture')):
            raise SourceError('Missing source normal/base/roughness: '+name)
    if materials['sails'].get('alphaMode')!='MASK':
        raise SourceError('Sail material must use masked opacity')
    accessors=doc.get('accessors',[])
    count=0
    for mesh in doc.get('meshes',[]):
        for primitive in mesh.get('primitives',[]):
            idx=primitive.get('indices')
            if type(idx) is not int or not 0<=idx<len(accessors):raise SourceError('Invalid indexed geometry')
            n=accessors[idx].get('count',0)
            if type(n) is not int or n<3:raise SourceError('Invalid GLTF accessor')
            mode=primitive.get('mode',4)
            if mode==4:
                if n%3:raise SourceError('Non-triangular indexed primitive')
                count+=n//3
            elif mode in (5,6):count+=max(n-2,0)
            else:raise SourceError('Unsupported ship surface primitive')
    if count < 50000:raise SourceError('Too few original ship triangles for audited hero source')
    animations=doc.get('animations',[])
    if any(not a.get('channels') or not a.get('samplers') for a in animations):
        raise SourceError('Invalid / fictitious animation metadata')
    return {'triangles':count,'mesh_sections':len(doc.get('meshes',[])),
            'material_sections':len(materials), 'skeletal_skins':len(doc.get('skins',[])),
            'animated':bool(animations), 'mobile_lod_approved':False,
            'premium_visual_accepted':False}


def validate_dependency_closure(doc:dict, root:Path)->None:
    for entry in [*doc.get('images',[]),*doc.get('buffers',[])]:
        path=safe_path(entry.get('uri'))
        candidate=root/path
        if not candidate.is_file() or candidate.is_symlink():
            raise SourceError('glTF dependency absent or symlinked: '+str(path))


def _fetch_source(url:str)->bytes:
    request=Request(url,headers={'User-Agent':'Isles-of-Mythos-Source-Audit/1.0'})
    with urlopen(request,timeout=40) as r:
        if r.geturl()!=url:raise SourceError('Redirects not admitted to source provenance')
        result=r.read(MAX_FILE_BYTES+1)
    return result


def verified_download(item:dict, dest:Path, *, fetch=None)->dict:
    fetch=fetch or _fetch_source
    raw=fetch(item['url'])
    if not isinstance(raw,bytes) or len(raw)!=item['size']:
        raise SourceError('Exact publisher byte length mismatch')
    if hashlib.md5(raw).hexdigest()!=item['md5']:
        raise SourceError('Publisher MD5 mismatched; source bytes changed')
    sha=hashlib.sha256(raw).hexdigest()
    if item.get('sha256') and item['sha256']!=sha:
        raise SourceError('Pinned source SHA256 mismatch')
    path=safe_path(item['path'])
    output=dest/path
    if output.exists() or output.is_symlink():raise SourceError('Refuse to overwrite existing staged source')
    output.parent.mkdir(parents=True,exist_ok=True)
    if output.parent.is_symlink():raise SourceError('Symlinked destination forbidden')
    output.write_bytes(raw)
    return {'path':path.as_posix(),'size':len(raw),'sha256':sha,
            'source_sha_pinned':bool(item.get('sha256')),'url':item['url']}


def add_sail_alpha(stage:Path)->dict:
    path=stage/'ship_pinnace_1k.gltf'
    doc=json.loads(path.read_text(encoding='utf-8'))
    sail=next((m for m in doc.get('materials',[]) if m.get('name')=='ship_pinnace_sails'),None)
    if not sail:raise SourceError('Original PBR sail material absent')
    idx=sail.get('pbrMetallicRoughness',{}).get('baseColorTexture',{}).get('index')
    if type(idx) is not int or idx>=len(doc.get('textures',[])):raise SourceError('Sail diffuse not indexed')
    sourceidx=doc['textures'][idx].get('source')
    if type(sourceidx) is not int or sourceidx>=len(doc.get('images',[])):
        raise SourceError('Sail diffuse image absent')
    diffuse_path=safe_path(doc['images'][sourceidx]['uri'])
    alpha_path=Path('textures/ship_pinnace_sails_alpha_1k.png')
    if not (stage/alpha_path).is_file():raise SourceError('Publisher sail opacity missing')
    with Image.open(stage/diffuse_path) as rgb, Image.open(stage/alpha_path) as opacity:
        if rgb.size!=opacity.size:raise SourceError('Sail map dimensions differ')
        rgba=rgb.convert('RGBA');rgba.putalpha(opacity.convert('L'))
        result=stage/'textures/ship_pinnace_sails_rgba_derived.png'
        if result.exists():raise SourceError('Derived sail map already exists')
        rgba.save(result,optimize=True)
    doc['images'][sourceidx]['uri']='textures/ship_pinnace_sails_rgba_derived.png'
    doc['images'][sourceidx].pop('mimeType',None)
    sail['alphaMode']='MASK'
    sail['alphaCutoff']=0.47
    path.write_text(json.dumps(doc,indent=2)+'\n',encoding='utf-8')
    return {'derived_path':'textures/ship_pinnace_sails_rgba_derived.png',
            'derived_sha256':hashlib.sha256(result.read_bytes()).hexdigest(),
            'modified_gltf_sha256':hashlib.sha256(path.read_bytes()).hexdigest()}


def main()->None:
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--manifest',type=Path,required=True)
    ap.add_argument('--stage',type=Path,required=True)
    ap.add_argument('--receipt',type=Path,required=True)
    args=ap.parse_args()
    data=json.loads(args.manifest.read_text(encoding='utf-8'))
    validate_manifest(data)
    if args.stage.exists() and any(args.stage.iterdir()):raise SourceError('Destination must be empty')
    args.stage.mkdir(parents=True,exist_ok=True)
    receipts=[verified_download(item,args.stage) for item in data['files']]
    source_file=args.stage/'ship_pinnace_1k.gltf'
    source_hash=hashlib.sha256(source_file.read_bytes()).hexdigest()
    model=json.loads(source_file.read_text(encoding='utf-8'))
    stats=inspect_gltf(model)
    validate_dependency_closure(model,args.stage)
    deriv=add_sail_alpha(args.stage)
    validate_dependency_closure(json.loads(source_file.read_text(encoding='utf-8')),args.stage)
    rec={'source':'Poly Haven Ship Pinnace','license':'CC0-1.0',
         'unmodified_gltf_sha256':source_hash,'files':receipts,
         'all_sources_sha256_pinned':all(row['source_sha_pinned'] for row in receipts),
         'model':stats,'derived':deriv,
         'gameplay_admitted':False,'visual_acceptance':'NOT VERIFIED',
         'reference_video_sha256':'713cd6e90c6f7d589a06eb3bd4b9b2d5ebeb9c0ff711b5de527a68460dfbcb05'}
    args.receipt.parent.mkdir(parents=True,exist_ok=True)
    args.receipt.write_text(json.dumps(rec,indent=2)+'\n',encoding='utf-8')
    print(f"Verified {len(receipts)} publisher source files, {stats['triangles']} triangles; no visual or mobile acceptance")

if __name__=='__main__':main()
