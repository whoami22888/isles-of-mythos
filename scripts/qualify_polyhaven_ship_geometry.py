#!/usr/bin/env python3
"""Read-only quarantine probe for CC0 Poly Haven ship sail geometry.

Fetches ONLY exact 1K glTF and its external BIN from the publisher's API,
verifies upstream MD5 and records SHA-256. No game asset is admitted or altered.
Results are geometric candidates, never visual-quality acceptance.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
import struct
import urllib.parse
import urllib.request

ASSET_IDS = ("dutch_ship_large_01", "dutch_ship_large_02", "ship_pinnace")
API_HOST = "api.polyhaven.com"
DATA_HOST = "dl.polyhaven.org"
MAX_GTLF_BYTES = 256_000
MAX_BIN_BYTES = 20_000_000
COMPONENT_TYPES = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
ELEMENT_COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def _validate_url(url: str, host: str) -> None:
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname != host or parsed.port not in (None, 443):
        raise ValueError("Unapproved publisher origin")
    if parsed.username or parsed.password or parsed.fragment:
        raise ValueError("Unexpected publisher URL components")


class ApprovedRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        _validate_url(newurl, urllib.parse.urlsplit(req.full_url).hostname)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _read(url: str, host: str, limit: int) -> bytes:
    _validate_url(url, host)
    opener = urllib.request.build_opener(ApprovedRedirects())
    request = urllib.request.Request(url, headers={"User-Agent": "IslesMythos-SailQualify/1.0"})
    with opener.open(request, timeout=40) as resp:
        _validate_url(resp.url, host)
        payload = resp.read(limit + 1)
    if len(payload) > limit:
        raise ValueError("Publisher payload exceeds quarantine byte cap")
    return payload


def _download(item: dict, host: str, limit: int) -> tuple[bytes, dict]:
    data = _read(item["url"], host, limit)
    md5 = hashlib.md5(data, usedforsecurity=False).hexdigest()
    if md5 != item["md5"]:
        raise ValueError("Publisher MD5 mismatch for " + item["url"])
    if int(item["size"]) != len(data):
        raise ValueError("Publisher size mismatch for " + item["url"])
    return data, {"url": item["url"], "size": len(data), "md5": md5,
                  "sha256": hashlib.sha256(data).hexdigest()}


def _accessor(doc: dict, blob: bytes, index: int) -> list:
    item = doc["accessors"][index]
    if "sparse" in item or "bufferView" not in item:
        raise ValueError("Sparse or absent accessor unsupported")
    view = doc["bufferViews"][item["bufferView"]]
    if view["buffer"] != 0:
        raise ValueError("Unexpected extra binary buffer")
    fmt, component_width = COMPONENT_TYPES[item["componentType"]]
    count = ELEMENT_COMPONENTS[item["type"]]
    element_width = component_width * count
    stride = view.get("byteStride", element_width)
    if stride < element_width or stride % component_width:
        raise ValueError("Unsupported interleaved accessor")
    start = view.get("byteOffset", 0) + item.get("byteOffset", 0)
    if item["count"] == 0:
        return []
    end = start + (item["count"] - 1) * stride + element_width
    if end > len(blob) or end > view.get("byteOffset", 0) + view["byteLength"]:
        raise ValueError("Accessor outside source bufferView")
    unpack = struct.Struct("<" + fmt * count)
    values = [unpack.unpack_from(blob, start + i * stride) for i in range(item["count"])]
    return [entry[0] for entry in values] if count == 1 else values


def _components(positions: list, indices: list, uv: list) -> list[dict]:
    if len(positions) != len(uv) or len(indices) % 3:
        raise ValueError("Invalid sail array size")
    parent = list(range(len(positions)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for a, b, c in zip(indices[::3], indices[1::3], indices[2::3]):
        if min(a, b, c) < 0 or max(a, b, c) >= len(positions):
            raise ValueError("Out-of-range glTF sail indices")
        ra = root(a)
        parent[root(b)] = ra
        parent[root(c)] = ra
    groups = {}
    for a, b, c in zip(indices[::3], indices[1::3], indices[2::3]):
        key = root(a)
        groups.setdefault(key, {"triangles": 0, "indices": set(), "surface_area_m2": 0.0})
        group = groups[key]
        group["triangles"] += 1
        group["indices"].update((a, b, c))
        pa, pb, pc = positions[a], positions[b], positions[c]
        ux, uy, uz = (pb[k] - pa[k] for k in range(3))
        vx, vy, vz = (pc[k] - pa[k] for k in range(3))
        area = 0.5 * math.sqrt((uy * vz - uz * vy) ** 2 +
                               (uz * vx - ux * vz) ** 2 +
                               (ux * vy - uy * vx) ** 2)
        group["surface_area_m2"] += area
    panels = []
    for group in groups.values():
        pts = [positions[i] for i in group["indices"]]
        uvs = [uv[i] for i in group["indices"]]
        mins = [min(p[k] for p in pts) for k in range(3)]
        maxs = [max(p[k] for p in pts) for k in range(3)]
        size = [maxs[k] - mins[k] for k in range(3)]
        horizontal = max(size[0], size[2])
        height = size[1]
        # A non-trivial cloth panel must be truly tall and broad, not a
        # narrow furled streamer or an unrolled placeholder strip.
        full_candidate = (height >= 3.0 and horizontal >= 4.0 and
                          group["surface_area_m2"] >= 8.0 and
                          0.38 <= height / max(horizontal, 0.001) <= 2.7)
        panels.append({"vertices": len(group["indices"]),
                       "triangles": group["triangles"],
                       "aabb_size_m": [round(v, 4) for v in size],
                       "uv_min": [round(min(v[k] for v in uvs), 5) for k in range(2)],
                       "uv_max": [round(max(v[k] for v in uvs), 5) for k in range(2)],
                       "surface_area_m2": round(group["surface_area_m2"], 3),
                       "geometry_full_sail_candidate": full_candidate})
    return sorted(panels, key=lambda p: p["surface_area_m2"], reverse=True)


def qualify(asset: str) -> dict:
    _validate_url(f"https://api.polyhaven.com/files/{asset}", API_HOST)
    metadata = json.loads(_read(
        f"https://api.polyhaven.com/files/{asset}", API_HOST, 1_000_000))
    model = metadata["gltf"]["1k"]["gltf"]
    source, source_receipt = _download(model, DATA_HOST, MAX_GTLF_BYTES)
    doc = json.loads(source)
    if len(doc.get("buffers", [])) != 1:
        raise ValueError("Unexpected glTF buffer layout")
    target_name = doc["buffers"][0]["uri"]
    if "/" in target_name or ".." in target_name:
        raise ValueError("Unsafe upstream BIN filename")
    dependency = model["include"][target_name]
    data, bin_receipt = _download(dependency, DATA_HOST, MAX_BIN_BYTES)
    if len(data) != doc["buffers"][0]["byteLength"]:
        raise ValueError("glTF BIN byteLength mismatch")
    nodes = []
    all_panels = []
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            mat = doc["materials"][primitive["material"]]
            if "sail" not in mat.get("name", "").lower():
                continue
            if not mat.get("doubleSided") or mat.get("alphaMode") != "MASK":
                raise ValueError("Source sail missing required two-sided alpha cutout")
            positions = _accessor(doc, data, primitive["attributes"]["POSITION"])
            texcoord = _accessor(doc, data, primitive["attributes"]["TEXCOORD_0"])
            indices = _accessor(doc, data, primitive["indices"])
            panels = _components(positions, indices, texcoord)
            nodes.append({"mesh_name": mesh["name"], "material": mat["name"],
                          "source_vertices": len(positions), "source_triangles": len(indices) // 3,
                          "panels": panels})
            all_panels.extend(panels)
    if not nodes:
        raise ValueError("No PBR-alpha sail mesh in upstream glTF")
    return {"asset": asset, "publisher": "Poly Haven",
            "licence": "CC0-1.0 (publisher claim; independent approval pending)",
            "source_page": f"https://polyhaven.com/a/{asset}",
            "geometry_only_not_visual_approval": True,
            "gltf": source_receipt, "bin": bin_receipt,
            "material_count": len(doc["materials"]),
            "sail_surfaces": nodes, "sail_components": len(all_panels),
            "candidate_broad_panels": sum(p["geometry_full_sail_candidate"] for p in all_panels)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="ship-sail-geometry-report.json")
    args = parser.parse_args()
    data = {"scope": "QUARANTINE_ONLY", "admitted_to_game": False,
            "results": [], "errors": []}
    for asset in ASSET_IDS:
        try:
            entry = qualify(asset)
            data["results"].append(entry)
            print(f"{asset}: components={entry['sail_components']} "
                  f"broad_candidates={entry['candidate_broad_panels']}")
        except (OSError, ValueError, KeyError, IndexError, TypeError, json.JSONDecodeError) as error:
            data["errors"].append({"asset": asset, "error": str(error)})
            print(f"{asset}: QUARANTINE FAILURE {error}")
    pathlib.Path(args.output).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    if data["errors"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
