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
ASSET_FETCH_LIMIT = 80 * 1024 * 1024  # Checked against the current pinned asset fetcher.


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
        if alpha_mode not in ("MASK", "BLEND"):
            continue
        try:
            texture = textures[color["index"]]
            image = images[texture["source"]]
            uri = image.get("uri", "")
        except (IndexError, KeyError, TypeError):
            issues.append(Finding("TRANSPARENT_BASE_MISSING", rel, f"{name}: unresolved base-color texture"))
            continue
        if uri.lower().endswith((".jpg", ".jpeg")) or image.get("mimeType") == "image/jpeg":
            issues.append(Finding("FOLIAGE_ALPHA" if "lea" in name else "MASKED_ALPHA_JPEG", rel,
                f"{name}: {alpha_mode} base texture is JPEG without alpha; supply pinned alpha-capable color or an independently validated opacity path"))
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


def _inspect_asset_manifest(root: Path) -> list[Finding]:
    """Flag un-restorable publisher references and assets above importer limit.

    This is deliberately narrow: neither a plausible URL nor a content digest proves
    legal provenance, actual source bytes, art quality or Godot import.
    """
    path = root / "assets/external-assets.json"
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        assets = data["assets"]
        if not isinstance(assets, list):
            raise ValueError("assets must be an array")
    except (OSError, ValueError, KeyError) as exc:
        return [Finding("INVALID_ASSET_MANIFEST", str(path), str(exc))]
    findings: list[Finding] = []
    reported: set[tuple[str, str]] = set()
    for item in assets:
        if not isinstance(item, dict) or not isinstance(item.get("path"), str):
            findings.append(Finding("INVALID_ASSET_ENTRY", str(path), "Entry lacks a valid path"))
            continue
        rel = item["path"]
        parts = rel.split("/")
        if len(parts) < 3 or parts[0] != "polyhaven":
            continue
        package = parts[1]
        source = str(item.get("source_url", ""))
        url = str(item.get("download_url", ""))
        if f"/a/{package}" not in source:
            key = (package, "ASSET_SOURCE_MISMATCH")
            if key not in reported:
                reported.add(key)
                findings.append(Finding(key[1], str(path),
                    f"{package}: source must link to the exact creator asset, not {source!r}"))
        if "/gltf/1k/polyhaven/" in url:
            key = (package, "BAD_ASSET_DOWNLOAD_PATH")
            if key not in reported:
                reported.add(key)
                findings.append(Finding(key[1], str(path),
                    f"{package}: download URL contains wrong /1k/polyhaven/ prefix"))
        candidate = root / "assets/external" / rel
        if candidate.is_file() and candidate.stat().st_size > ASSET_FETCH_LIMIT:
            findings.append(Finding("ASSET_EXCEEDS_FETCH_LIMIT", rel,
                f"{candidate.stat().st_size:,} bytes > fetcher's {ASSET_FETCH_LIMIT:,}-byte cap; use approved smaller payload instead of bypassing verifier"))
    return findings


def audit(root: Path) -> tuple[list[Finding], int]:
    """Return source-observable blockers and candidate count; never claim parity."""
    issues: list[Finding] = _inspect_asset_manifest(root)
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
        for referenced in used:
            if not (root / referenced).is_file():
                issues.append(Finding("MISSING_SCENE_SCRIPT", path.name, f"Scene references absent {referenced}"))
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
    parser.add_argument("--require-candidate", action="store_true",
                        help="Fail closed when accepting a premium game build with no candidate scene")
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
    return 1 if issues or (args.require_candidate and not candidates) else 0


if __name__ == "__main__":
    sys.exit(main())
