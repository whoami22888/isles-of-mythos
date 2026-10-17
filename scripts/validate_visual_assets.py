#!/usr/bin/env python3
"""Fail-closed admission checks for textured Godot/GLTF production assets."""

from __future__ import annotations

import base64
import binascii
import json
import struct
import sys
import zlib
from pathlib import Path
from typing import List, Optional, Set, Tuple


class VisualAssetError(ValueError):
    """Raised when an asset cannot pass the visual admission gate."""


def _png_pixels(data: bytes) -> Tuple[int, int, List[Tuple[int, int, int]]]:  # pylint: disable=too-many-locals,too-many-branches
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise VisualAssetError("texture is not a PNG")
    pos = 8
    width = height = bit_depth = color_type = None
    compressed = bytearray()
    while pos < len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        kind = data[pos + 4 : pos + 8]
        payload = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, bit_depth, color_type, compression, filt, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
            if bit_depth != 8 or color_type not in (2, 6) or compression or filt or interlace:
                raise VisualAssetError("only non-interlaced 8-bit RGB/RGBA PNGs are supported")
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break
    if width is None or height is None:
        raise VisualAssetError("PNG is missing IHDR")
    channels = 3 if color_type == 2 else 4
    stride = width * channels
    raw = zlib.decompress(bytes(compressed))
    if len(raw) != (stride + 1) * height:
        raise VisualAssetError("PNG scanline length mismatch")
    rows: list[bytes] = []
    cursor = 0
    for _ in range(height):
        filter_type = raw[cursor]
        cursor += 1
        current = bytearray(raw[cursor : cursor + stride])
        cursor += stride
        previous = rows[-1] if rows else bytes(stride)
        for i in range(stride):
            left = current[i - channels] if i >= channels else 0
            up = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filter_type == 1:
                current[i] = (current[i] + left) & 255
            elif filter_type == 2:
                current[i] = (current[i] + up) & 255
            elif filter_type == 3:
                current[i] = (current[i] + ((left + up) // 2)) & 255
            elif filter_type == 4:
                p = left + up - upper_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upper_left)
                predictor = left if pa <= pb and pa <= pc else up if pb <= pc else upper_left
                current[i] = (current[i] + predictor) & 255
            elif filter_type != 0:
                raise VisualAssetError(f"unsupported PNG filter {filter_type}")
        rows.append(bytes(current))
    pixels: List[Tuple[int, int, int]] = []
    for row in rows:
        for i in range(0, len(row), channels):
            pixels.append(tuple(row[i : i + 3]))
    return width, height, pixels


def _decode_data_uri(uri: str) -> bytes:
    try:
        return base64.b64decode(uri.split(",", 1)[1], validate=True)
    except (IndexError, binascii.Error) as exc:
        raise VisualAssetError("invalid embedded image data") from exc


def _image_bytes(document: dict, image: dict, asset_path: Path) -> bytes:
    uri = image.get("uri", "")
    if uri.startswith("data:"):
        return _decode_data_uri(uri)
    view_index = image.get("bufferView")
    if view_index is None:
        raise VisualAssetError("image has no embedded data or bufferView")
    view = document["bufferViews"][view_index]
    buffer = document["buffers"][view["buffer"]]
    buffer_uri = buffer.get("uri", "")
    if not buffer_uri.startswith("data:"):
        raise VisualAssetError(f"external buffer dependency: {asset_path.name}")
    raw = _decode_data_uri(buffer_uri)
    start = view.get("byteOffset", 0)
    return raw[start : start + view["byteLength"]]


def _texture_index(material: dict, channel: str) -> Optional[int]:
    if channel == "baseColorTexture":
        return (material.get("pbrMetallicRoughness", {}).get(channel) or {}).get("index")
    return (material.get(channel) or {}).get("index")


def _check_texture_quality(data: bytes, label: str) -> None:
    width, height, pixels = _png_pixels(data)
    unique = len(set(pixels))
    if unique < 64:
        raise VisualAssetError(f"{label}: palette/swatch-only texture ({unique} unique colours)")
    mean = tuple(sum(pixel[channel] for pixel in pixels) / len(pixels) for channel in range(3))
    variance = sum(sum((pixel[channel] - mean[channel]) ** 2 for channel in range(3)) for pixel in pixels) / (len(pixels) * 3)
    if variance < 80.0:
        raise VisualAssetError(f"{label}: texture lacks spatial/material variation")
    if width < 128 or height < 128:
        raise VisualAssetError(f"{label}: texture resolution below 128x128")


def validate_gltf(path: Path) -> None:
    document = json.loads(path.read_text(encoding="utf-8"))
    if not document.get("meshes") or not document.get("materials"):
        raise VisualAssetError(f"{path.name}: missing mesh or material")
    textures = document.get("textures", [])
    images = document.get("images", [])
    if not textures or not images:
        raise VisualAssetError(f"{path.name}: no bound material textures")
    checked_images: Set[int] = set()
    for mesh in document["meshes"]:
        for primitive in mesh.get("primitives", []):
            if "TEXCOORD_0" not in primitive.get("attributes", {}):
                raise VisualAssetError(f"{path.name}: mesh primitive has no UV coordinates")
            material_index = primitive.get("material")
            if material_index is None:
                raise VisualAssetError(f"{path.name}: mesh primitive has no material binding")
            material = document["materials"][material_index]
            for channel in ("baseColorTexture", "normalTexture", "metallicRoughnessTexture"):
                texture_index = _texture_index(material, channel)
                if texture_index is None:
                    raise VisualAssetError(f"{path.name}: material has no {channel}")
                image_index = textures[texture_index]["source"]
                if image_index not in checked_images:
                    _check_texture_quality(_image_bytes(document, images[image_index], path), f"{path.name} image {image_index}")
                    checked_images.add(image_index)
    if not checked_images:
        raise VisualAssetError(f"{path.name}: no material texture was inspected")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: validate_visual_assets.py ASSET.gltf ...")
    try:
        for value in sys.argv[1:]:
            path = Path(value)
            validate_gltf(path)
            print(f"PASS textured PBR asset: {path}")
    except (OSError, KeyError, TypeError, json.JSONDecodeError, VisualAssetError) as exc:
        print(f"REJECT: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
