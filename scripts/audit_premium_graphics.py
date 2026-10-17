#!/usr/bin/env python3
"""Fail-closed *structural* graphics checks; human Godot-video parity is separate."""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

PROTOTYPES = {
    "island_preview.tscn", "sculpted_terrain_preview.tscn",
    "coastal_water_preview.tscn", "coastal_preview.tscn",
    "coastal_atmosphere_preview.tscn",
}
TRIANGLE_REVIEW_LIMIT = 300_000  # Review trigger, not an Android performance certification.


@dataclass(frozen=True)
class Finding:
    code: str
    file: str
    detail: str

    def __str__(self) -> str:
        return f"{self.code}: {self.file}: {self.detail}"


def _script_text(root: Path, scene_text: str) -> tuple[str, list[str]]:
    matches = re.findall(r'res://(scripts/[\w./-]+\.gd)', scene_text)
    contents = []
    for rel in matches:
        path = root / rel
        if path.is_file():
            contents.append(path.read_text(encoding="utf-8"))
    return "\n".join(contents), matches


def _resource_paths(text: str) -> set[str]:
    return set(re.findall(r'res://(assets/[\w./-]+\.gltf)', text))


def _inspect_gltf(root: Path, rel: str) -> list[Finding]:
    path = root / rel
    issues: list[Finding] = []
    if not path.is_file():
        return [Finding("MISSING_MODEL", rel, "Referenced imported GLTF does not exist")]
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, UnicodeError) as exc:
        return [Finding("INVALID_MODEL", rel, str(exc))]
    materials = doc.get("materials", [])
    textures = doc.get("textures", [])
    images = doc.get("images", [])
    accessors = doc.get("accessors", [])
    meshes = doc.get("meshes", [])
    for material in materials:
        name = material.get("name", "unnamed").lower()
        alpha_mode = material.get("alphaMode", "OPAQUE")
        color = material.get("pbrMetallicRoughness", {}).get("baseColorTexture", {})
        if alpha_mode not in ("MASK", "BLEND") or "lea" not in name:
            continue
        try:
            texture = textures[color["index"]]
            image = images[texture["source"]]
            uri = image.get("uri", "")
        except (IndexError, KeyError, TypeError):
            issues.append(Finding("FOLIAGE_ALPHA", rel, f"{name}: unresolved base-color texture"))
            continue
        if uri.lower().endswith((".jpg", ".jpeg")) or image.get("mimeType") == "image/jpeg":
            issues.append(Finding("FOLIAGE_ALPHA", rel,
                f"{name}: {alpha_mode} base texture is JPEG without alpha; provide a pinned opacity map"))
    for mesh in meshes:
        for primitive in mesh.get("primitives", []):
            try:
                count = int(accessors[primitive["indices"]]["count"])
            except (KeyError, IndexError, TypeError, ValueError):
                continue
            triangles = count // 3
            if triangles > TRIANGLE_REVIEW_LIMIT and not re.search(r"LOD[1-9]", mesh.get("name", ""), re.I):
                issues.append(Finding("HEAVY_LOD0", rel,
                    f"{mesh.get('name', 'unnamed')}: {triangles:,} triangles/primitive; mobile LOD and profiling required"))
    return issues


def audit(root: Path) -> tuple[list[Finding], int]:
    """Return source-observable blockers and candidate count; never claim parity."""
    issues: list[Finding] = []
    project = root / "project.godot"
    if not project.is_file():
        return [Finding("MISSING_PROJECT", str(project), "Godot client project absent")], 0
    project_text = project.read_text(encoding="utf-8")
    match = re.search(r'^run/main_scene="res://scenes/([^"]+)"', project_text, re.M)
    if match and match.group(1) in PROTOTYPES:
        issues.append(Finding("PROTOTYPE_LAUNCH", "project.godot",
                              f"Prototype is player-facing main_scene: {match.group(1)}"))
    scenes = root / "scenes"
    count = 0
    for path in sorted(scenes.glob("*.tscn")):
        if path.name == "boot.tscn" or path.name in PROTOTYPES:
            continue
        count += 1
        scene = path.read_text(encoding="utf-8")
        script, used = _script_text(root, scene)
        combined = scene + "\n" + script
        if not used and not re.search(r'res://assets/[\w./-]+\.(?:gltf|glb)|albedo_texture|texture_albedo', scene):
            issues.append(Finding("NO_ART_SOURCE", path.name,
                                  "Candidate has neither inspectable script nor imported/PBR art"))
        if any(f"res://scenes/{name}" in combined or f"res://scripts/{name.replace('.tscn', '.gd')}" in combined
               for name in PROTOTYPES):
            issues.append(Finding("PROTOTYPE_DEPENDENCY", path.name,
                                  "Player-facing candidate imports a known placeholder scene/script"))
        if re.search(r'func _terrain_material\b', script):
            part = re.split(r'\nfunc [\w_]+\(', script.split("func _terrain_material", 1)[1], maxsplit=1)[0]
            if not all(x in part for x in ("albedo_texture", "normal_texture", "roughness_texture")):
                issues.append(Finding("FLAT_TERRAIN", path.name,
                    "Final terrain material lacks albedo/normal/roughness texture assignments"))
        if "QuadMesh.new()" in script and "foam" in script.lower():
            issues.append(Finding("FLAT_FOAM", path.name,
                "Shoreline foam uses unanimated quad strips; not reference-quality surf"))
        if "shallow" in combined and "deep" in combined and "UV.y" in combined and not re.search(
            r'depth_texture|DEPTH_TEXTURE|depth_sample|hint_depth_texture', combined, re.I
        ):
            issues.append(Finding("FAKE_WATER_DEPTH", path.name,
                "Water-depth colour is derived only from mesh UV instead of scene depth"))
        if "ShallowToDeepWater" in combined and not re.search(r'\bTIME\b|void vertex\s*\(|wave_offset', combined):
            issues.append(Finding("STATIC_WATER", path.name,
                "Water has no observable wave animation/displacement"))
        if "SHIP_SCENE" in script and not re.search(
            r'AnimationPlayer|AnimationTree|_animate_ship|ship_motion|ship_velocity|ship\.position\s*[+\-]=', script
        ):
            issues.append(Finding("STATIC_SHIP", path.name,
                "Ship placed but no ship movement/animation implementation observed"))
        if "coastal" in path.name.lower() and "slice" in path.name.lower():
            if not _resource_paths(combined) and not re.search(r'albedo_texture\s*=', script):
                issues.append(Finding("MISSING_PBR_ASSETS", path.name,
                    "No imported GLTF or PBR texture assignments in coastal slice"))
        for asset in sorted(_resource_paths(combined)):
            issues.extend(_inspect_gltf(root, asset))
    capture = root / "tests/render_capture.gd"
    if count and capture.is_file():
        source = capture.read_text(encoding="utf-8")
        if any(path.stem in source for path in scenes.glob("*.tscn") if path.name != "boot.tscn" and path.name not in PROTOTYPES):
            if "get_image()" in source and "RenderingServer.frame_post_draw" not in source:
                issues.append(Finding("STALE_CAPTURE", "tests/render_capture.gd",
                                      "Godot viewport read lacks renderer completion fence"))
            if "get_image()" in source and not re.search(r'get_pixel\s*\(|histogram|variation|pixel_variance', source, re.I):
                issues.append(Finding("BLANK_CAPTURE", "tests/render_capture.gd",
                                      "No pixel/content assertion proves capture contains rendered scenery"))
    return issues, count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", type=Path, default=Path("client-godot"))
    args = parser.parse_args()
    issues, candidates = audit(args.client)
    print(f"Candidate scenes scanned: {candidates}")
    for item in issues:
        print(f"::error::{item}")
    if not candidates:
        print("No production graphics candidate exists: visual milestone NOT VERIFIED")
    else:
        print("Static source audit does NOT certify artistic reference parity or mobile FPS")
    print(f"Structural findings: {len(issues)}")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
