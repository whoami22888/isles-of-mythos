#!/usr/bin/env python3
"""Paint an original red cross onto a copy of the Poly Haven sail atlas.

The upstream CC0 texture is not modified:
  client-godot/assets/external/polyhaven/dutch_ship_medium/
  source https://polyhaven.com/a/dutch_ship_medium
  licence CC0 1.0 https://creativecommons.org/publicdomain/zero/1.0/

UV islands come from the same glTF sail primitive. Each large cloth island
gets a cross aligned to that island's own axes, then the cloth is lifted
slightly toward warm cream so the emblem reads on the grey atlas.
"""
from __future__ import annotations

import json
import struct
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SHIP = ROOT / "client-godot/assets/external/polyhaven/dutch_ship_medium"
GLTF = SHIP / "dutch_ship_medium_1k.gltf"
SOURCE = SHIP / "textures/dutch_ship_medium_sails_rgba_1k.png"
OUTPUT = ROOT / "client-godot/assets/generated/sails/order_cross_sails_rgba.png"
# Skip pennants and tiny reef points. Main courses and topsails are larger.
MIN_ISLAND_AREA = 0.008


def _load_sail_islands() -> list[list[tuple[float, float, float, float, float, float]]]:
    document = json.loads(GLTF.read_text(encoding="utf-8"))
    blob = (SHIP / document["buffers"][0]["uri"]).read_bytes()
    views = document["bufferViews"]
    uv_view = views[10]
    index_view = views[11]
    uv_count = 4020
    uvs: list[tuple[float, float]] = []
    uv_off = uv_view["byteOffset"]
    for index in range(uv_count):
        uvs.append(struct.unpack_from("<ff", blob, uv_off + index * 8))
    index_count = 22644
    indices = struct.unpack_from(f"<{index_count}H", blob, index_view["byteOffset"])
    parent = list(range(uv_count))

    def find(node: int) -> int:
        while parent[node] != node:
            parent[node] = parent[parent[node]]
            node = parent[node]
        return node

    def union(left: int, right: int) -> None:
        root_left, root_right = find(left), find(right)
        if root_left != root_right:
            parent[root_right] = root_left

    triangles: list[tuple[int, int, int]] = []
    for cursor in range(0, len(indices), 3):
        a, b, c = indices[cursor:cursor + 3]
        union(a, b)
        union(b, c)
        triangles.append((a, b, c))
    grouped: dict[int, list[tuple[int, int, int]]] = defaultdict(list)
    for triangle in triangles:
        grouped[find(triangle[0])].append(triangle)
    islands: list[list[tuple[float, float, float, float, float, float]]] = []
    for faces in grouped.values():
        area = 0.0
        packed: list[tuple[float, float, float, float, float, float]] = []
        for a, b, c in faces:
            ax, ay = uvs[a]
            bx, by = uvs[b]
            cx, cy = uvs[c]
            area += abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) * 0.5
            packed.append((ax, ay, bx, by, cx, cy))
        if area >= MIN_ISLAND_AREA:
            islands.append(packed)
    return islands


def _rasterize(draw: ImageDraw.ImageDraw, island, width: int, height: int) -> None:
    for ax, ay, bx, by, cx, cy in island:
        draw.polygon(
            [(ax * width, ay * height), (bx * width, by * height), (cx * width, cy * height)],
            fill=255,
        )


def _cross_on_island(pixels, mask, island, width: int, height: int) -> None:
    points = []
    for ax, ay, bx, by, cx, cy in island:
        points.extend(((ax, ay), (bx, by), (cx, cy)))
    count = float(len(points))
    mean_u = sum(p[0] for p in points) / count
    mean_v = sum(p[1] for p in points) / count
    cov_uu = sum((p[0] - mean_u) ** 2 for p in points) / count
    cov_vv = sum((p[1] - mean_v) ** 2 for p in points) / count
    cov_uv = sum((p[0] - mean_u) * (p[1] - mean_v) for p in points) / count
    # Principal axis of the cloth island, so the cross follows the sail.
    if abs(cov_uv) < 1e-8 and abs(cov_uu - cov_vv) < 1e-8:
        major = (0.0, 1.0)
    else:
        trace = cov_uu + cov_vv
        det = cov_uu * cov_vv - cov_uv * cov_uv
        disc = max(0.0, trace * trace * 0.25 - det)
        root = trace * 0.5 + disc ** 0.5
        if abs(cov_uv) > 1e-8:
            major = (root - cov_vv, cov_uv)
        elif cov_uu >= cov_vv:
            major = (1.0, 0.0)
        else:
            major = (0.0, 1.0)
    length = max(1e-6, (major[0] ** 2 + major[1] ** 2) ** 0.5)
    major = (major[0] / length, major[1] / length)
    minor = (-major[1], major[0])
    along = [((p[0] - mean_u) * major[0] + (p[1] - mean_v) * major[1]) for p in points]
    across = [((p[0] - mean_u) * minor[0] + (p[1] - mean_v) * minor[1]) for p in points]
    half_long = (max(along) - min(along)) * 0.34
    half_cross = (max(across) - min(across)) * 0.34
    arm = min(half_long, half_cross) * 0.22
    arm = max(arm, min(half_long, half_cross) * 0.16)

    def covers(u: float, v: float) -> bool:
        du = (u - mean_u) * major[0] + (v - mean_v) * major[1]
        dv = (u - mean_u) * minor[0] + (v - mean_v) * minor[1]
        upright = abs(du) <= half_long and abs(dv) <= arm
        bar = abs(dv) <= half_cross and abs(du) <= arm
        return upright or bar

    min_u = max(0.0, min(p[0] for p in points))
    max_u = min(1.0, max(p[0] for p in points))
    min_v = max(0.0, min(p[1] for p in points))
    max_v = min(1.0, max(p[1] for p in points))
    x0 = int(min_u * (width - 1))
    x1 = int(max_u * (width - 1))
    y0 = int(min_v * (height - 1))
    y1 = int(max_v * (height - 1))
    red = (168, 36, 40, 255)
    for y in range(y0, y1 + 1):
        v = (y + 0.5) / height
        for x in range(x0, x1 + 1):
            if mask.getpixel((x, y)) < 128:
                continue
            u = (x + 0.5) / width
            if covers(u, v):
                pixels[x, y] = red


def main() -> None:
    islands = _load_sail_islands()
    image = Image.open(SOURCE).convert("RGBA")
    width, height = image.size
    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)
    for island in islands:
        _rasterize(draw, island, width, height)
    pixels = image.load()
    for y in range(height):
        for x in range(width):
            if mask.getpixel((x, y)) < 128:
                continue
            r, g, b, a = pixels[x, y]
            # Warm the grey CC0 cloth toward cream without flattening the weave.
            pixels[x, y] = (
                min(255, int(r * 0.62 + 214 * 0.38)),
                min(255, int(g * 0.62 + 196 * 0.38)),
                min(255, int(b * 0.62 + 156 * 0.38)),
                a,
            )
    for island in islands:
        _cross_on_island(pixels, mask, island, width, height)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)
    print(f"Wrote {OUTPUT} from {len(islands)} sail islands")


if __name__ == "__main__":
    main()
