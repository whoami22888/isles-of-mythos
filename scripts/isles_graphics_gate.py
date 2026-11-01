#!/usr/bin/env python3
"""Fail-closed *structural* graphics checks; human Godot-video parity is separate."""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

PROTOTYPES = {
    "island_preview.tscn", "sculpted_terrain_preview.tscn",
    "coastal_water_preview.tscn", "coastal_preview.tscn",
    "coastal_atmosphere_preview.tscn",
}
TRIANGLE_REVIEW_LIMIT = 300_000  # Review trigger, not an Android performance certification.
MAX_JSON_BYTES = 8 * 1024 * 1024
REVIEW_CODES = {"NO_ART_SOURCE", "FLAT_TERRAIN", "FLAT_FOAM", "FAKE_WATER_DEPTH",
                "STATIC_WATER", "STATIC_SHIP", "MISSING_PBR_ASSETS", "HEAVY_LOD0", "FOLIAGE_ALPHA",
                "STALE_CAPTURE", "BLANK_CAPTURE"}
RESOURCE_RE = re.compile(r"res://([^\"'\n\r]+?\.(?:tscn|gd|tres|gdshader|gltf|glb))(?=[\"'])")


@dataclass(frozen=True)
class Finding:
    code: str
    file: str
    detail: str

    @property
    def severity(self) -> str:
        return "review" if self.code in REVIEW_CODES else "error"

    def __str__(self) -> str:
        return f"{self.code}: {self.file}: {self.detail}"


def _read_source(root: Path, rel: str) -> str:
    path = _safe_resource(root, rel)
    if path.stat().st_size > MAX_JSON_BYTES:
        raise ValueError("Oversized source resource")
    return path.read_text(encoding="utf-8")


def _source_graph(root: Path, scene: str) -> tuple[str, list[str], list[Finding]]:
    pending = [scene]
    visited = set()
    texts = []
    scripts = []
    issues = []
    while pending:
        rel = pending.pop()
        if rel in visited:
            continue
        if len(visited) >= 2048:
            issues.append(Finding("RESOURCE_LIMIT", scene, "Source dependency graph exceeds audit bound"))
            break
        visited.add(rel)
        try:
            text = _read_source(root, rel)
        except (OSError, ValueError, UnicodeError) as exc:
            code = "UNSAFE_RESOURCE" if isinstance(exc, ValueError) and "escapes" in str(exc) else "INVALID_SOURCE"
            if isinstance(exc, FileNotFoundError):
                code = "MISSING_SCRIPT" if rel.endswith(".gd") else "MISSING_RESOURCE"
            issues.append(Finding(code, rel, str(exc)))
            continue
        texts.append(text)
        if rel.endswith(".gd"):
            scripts.append(text)
        for dep in RESOURCE_RE.findall(text):
            if not dep.endswith((".gltf", ".glb")):
                pending.append(dep)
    return "\n".join(texts), scripts, issues


def _resource_paths(text: str) -> set[str]:
    return {p for p in RESOURCE_RE.findall(text) if p.endswith((".gltf", ".glb"))}


def _safe_resource(root: Path, rel: str) -> Path:
    path = root / rel
    if ".." in Path(rel).parts or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError("Resource escapes the client root")
    return path


def _model_document(path: Path) -> dict:
    if path.suffix == ".glb":
        with path.open("rb") as stream:
            header = stream.read(20)
            if len(header) != 20:
                raise ValueError("Truncated GLB header")
            magic, version, total, size, kind = struct.unpack("<IIIII", header)
            if magic != 0x46546C67 or version != 2 or total != path.stat().st_size:
                raise ValueError("Invalid GLB header/length")
            if kind != 0x4E4F534A or size > MAX_JSON_BYTES or size % 4 or size > total - 20:
                raise ValueError("Invalid or oversized GLB JSON chunk")
            payload = stream.read(size)
    else:
        if path.stat().st_size > MAX_JSON_BYTES:
            raise ValueError("Oversized GLTF JSON")
        payload = path.read_bytes()
    doc = json.loads(payload)
    if not isinstance(doc, dict):
        raise ValueError("Model JSON must be an object")
    for key in ("materials", "textures", "images", "accessors", "meshes"):
        if key in doc and (not isinstance(doc[key], list) or not all(isinstance(x, dict) for x in doc[key])):
            raise ValueError("Invalid model collection: " + key)
    def index(value, collection):
        if type(value) is not int or value < 0 or value >= len(doc.get(collection, [])):
            raise ValueError("Invalid " + collection + " index")
    for material in doc.get("materials", []):
        if not isinstance(material.get("name", ""), str):
            raise ValueError("Invalid material name")
        pbr = material.get("pbrMetallicRoughness", {})
        if not isinstance(pbr, dict):
            raise ValueError("Invalid PBR object")
        color = pbr.get("baseColorTexture", {})
        if not isinstance(color, dict):
            raise ValueError("Invalid base color texture")
        if "index" in color:
            index(color["index"], "textures")
    for texture in doc.get("textures", []):
        if "source" in texture:
            index(texture["source"], "images")
    for image in doc.get("images", []):
        if not isinstance(image.get("uri", ""), str):
            raise ValueError("Invalid image URI")
    for accessor in doc.get("accessors", []):
        count = accessor.get("count", 0)
        if type(count) is not int or count < 0:
            raise ValueError("Invalid accessor count")
    for mesh in doc.get("meshes", []):
        if not isinstance(mesh.get("name", ""), str):
            raise ValueError("Invalid mesh name")
        primitives = mesh.get("primitives", [])
        if not isinstance(primitives, list) or not all(isinstance(p, dict) for p in primitives):
            raise ValueError("Invalid primitives")
        for primitive in primitives:
            if "indices" in primitive:
                index(primitive["indices"], "accessors")
            attributes = primitive.get("attributes", {})
            if not isinstance(attributes, dict):
                raise ValueError("Invalid attributes")
            if "POSITION" in attributes:
                index(attributes["POSITION"], "accessors")
            if type(primitive.get("mode", 4)) is not int or primitive.get("mode", 4) not in range(7):
                raise ValueError("Invalid primitive mode")
    return doc


def _inspect_gltf(root: Path, rel: str) -> list[Finding]:
    try:
        path = _safe_resource(root, rel)
    except ValueError as exc:
        return [Finding("UNSAFE_RESOURCE", rel, str(exc))]
    issues: list[Finding] = []
    if not path.is_file():
        return [Finding("MISSING_MODEL", rel, "Referenced imported GLTF does not exist")]
    try:
        doc = _model_document(path)
    except (ValueError, UnicodeError, OSError) as exc:
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
        triangles = 0
        for primitive in mesh.get("primitives", []):
            accessor = primitive.get("indices", primitive.get("attributes", {}).get("POSITION"))
            if accessor is None:
                continue
            count = accessors[accessor].get("count", 0)
            mode = primitive.get("mode", 4)
            triangles += count // 3 if mode == 4 else max(0, count - 2) if mode in (5, 6) else 0
        if triangles > TRIANGLE_REVIEW_LIMIT and not re.search(r"LOD[1-9]", mesh.get("name", ""), re.I):
            issues.append(Finding("HEAVY_LOD0", rel,
                f"{mesh.get('name', 'unnamed')}: {triangles:,} triangles/mesh; mobile LOD and profiling required"))
    return issues


def inspect_scene_nodes_runtime(scene_path: str, meshes: list[dict]) -> list[Finding]:
    """Audit mesh surfaces and materials observed in an instantiated Godot scene."""
    issues: list[Finding] = []
    seen: set[tuple[str, str]] = set()
    for mesh in meshes:
        node = mesh["node"]
        surfaces = mesh["surfaces"]
        triangles = sum(surface["triangles"] for surface in surfaces)
        if "VerifiedTropicalContentLayer" in node and "island_tree" in node.lower() and triangles >= 15000:
            key = ("HEAVY_LOD0", node.rsplit("/", 1)[-1])
            if key not in seen:
                issues.append(Finding("HEAVY_LOD0", scene_path,
                    f"{node}: {triangles:,} triangles exceed 15,000 distant-tree budget"))
                seen.add(key)
        if triangles > TRIANGLE_REVIEW_LIMIT:
            key = ("HEAVY_LOD0", node.rsplit("/", 1)[-1])
            if key not in seen:
                issues.append(Finding("HEAVY_LOD0", scene_path,
                    f"{node}: {triangles:,} instantiated triangles; mobile profiling required"))
                seen.add(key)
        for surface in surfaces:
            material = surface["material"]
            if "lea" in material.lower() and surface["transparency"] > 0 and not surface["albedo_alpha"]:
                key = ("FOLIAGE_ALPHA", material)
                if key not in seen:
                    issues.append(Finding("FOLIAGE_ALPHA", scene_path,
                        f"{node}: {material} uses transparency without actual albedo alpha ({surface['texture']})"))
                    seen.add(key)
    return issues


def _runtime_report(root: Path, godot_bin: str) -> dict:
    """Instantiate production scenes with the selected Godot binary; reject incomplete output."""
    executable = shutil.which(godot_bin)
    if not executable:
        raise ValueError(f"Godot binary unavailable: {godot_bin}")
    version = subprocess.run([executable, "--version"], capture_output=True, text=True,
                             timeout=10, check=False)
    if version.returncode or not re.match(r"^4\.7\.2\.stable(?:\.|$)", version.stdout.strip()):
        raise ValueError(f"Godot 4.7.2-stable required, got: {version.stdout.strip()}")
    result = subprocess.run([executable, "--headless", "--rendering-method", "mobile",
                             "--path", str(root), "--script", "res://tests/audit_runtime_graphics.gd"],
                            capture_output=True, text=True, timeout=120, check=False)
    if result.returncode:
        raise ValueError(f"Godot runtime probe failed ({result.returncode}): {(result.stdout + result.stderr)[-2000:]}")
    if re.search(r"(?m)^(?:SCRIPT ERROR:|ERROR:|RUNTIME_GRAPHICS_FAIL:)", result.stdout + result.stderr):
        raise ValueError(f"Godot runtime probe logged an error: {(result.stdout + result.stderr)[-2000:]}")
    markers = [line.removeprefix("RUNTIME_GRAPHICS_JSON=") for line in result.stdout.splitlines()
               if line.startswith("RUNTIME_GRAPHICS_JSON=")]
    if len(markers) != 1:
        raise ValueError("Godot runtime probe produced no unique report")
    report = json.loads(markers[0])
    if not isinstance(report, dict) or not report:
        raise ValueError("Godot runtime probe report is empty")
    required = {"res://scenes/realistic_coastal_slice.tscn",
                "res://scenes/realistic_coastal_fx_slice.tscn"}
    if not required.issubset(report):
        raise ValueError("Godot runtime probe omitted a production coastal scene")
    if not isinstance(report.get("__ship_motion_verified__"), bool):
        raise ValueError("Godot runtime probe omitted ship movement result")
    for scene, meshes in report.items():
        if scene == "__ship_motion_verified__":
            continue
        if not isinstance(scene, str) or not scene.startswith("res://scenes/") or not isinstance(meshes, list) or not meshes:
            raise ValueError("Invalid runtime scene report")
        for mesh in meshes:
            if not isinstance(mesh, dict) or not isinstance(mesh.get("node"), str) or not isinstance(mesh.get("surfaces"), list):
                raise ValueError("Invalid runtime mesh report")
            for surface in mesh["surfaces"]:
                if not isinstance(surface, dict) or not isinstance(surface.get("triangles"), (int, float)) or surface["triangles"] < 0 or not isinstance(surface.get("material"), str) or not isinstance(surface.get("transparency"), int) or not isinstance(surface.get("albedo_alpha"), bool) or not isinstance(surface.get("texture"), str):
                    raise ValueError("Invalid runtime surface report")
    return report


def audit(root: Path, runtime_report: dict | None = None) -> tuple[list[Finding], int]:
    """Return source-observable blockers and candidate count; never claim parity."""
    issues: list[Finding] = []
    project = root / "project.godot"
    if not project.is_file():
        return [Finding("MISSING_PROJECT", str(project), "Godot client project absent")], 0
    try:
        project_text = _read_source(root, "project.godot")
    except (OSError, ValueError, UnicodeError) as exc:
        return [Finding("UNSAFE_RESOURCE", "project.godot", str(exc))], 0
    match = re.search(r'^run/main_scene="res://scenes/([^"]+)"', project_text, re.M)
    if match and match.group(1) in PROTOTYPES:
        issues.append(Finding("PROTOTYPE_LAUNCH", "project.godot",
                              f"Prototype is player-facing main_scene: {match.group(1)}"))
    scenes = root / "scenes"
    count = 0
    for path in sorted(scenes.rglob("*.tscn")):
        if path.name == "boot.tscn" or path.name in PROTOTYPES:
            continue
        count += 1
        combined, scripts, graph_issues = _source_graph(root, str(path.relative_to(root)))
        issues.extend(graph_issues)
        script = "\n".join(scripts)
        used = scripts
        scene = combined
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
        if re.search(r'foam[^\n]*QuadMesh\.new\(\)|QuadMesh\.new\(\)[^\n]*foam', script, re.I):
            issues.append(Finding("FLAT_FOAM", path.name,
                "Shoreline foam uses unanimated quad strips; not reference-quality surf"))
        if "shallow" in combined and "deep" in combined and "UV.y" in combined and not re.search(
            r'depth_texture|DEPTH_TEXTURE|depth_sample|hint_depth_texture|shore_terrain_height', combined, re.I
        ):
            issues.append(Finding("FAKE_WATER_DEPTH", path.name,
                "Water-depth colour is derived only from mesh UV instead of scene depth"))
        if "ShallowToDeepWater" in combined and not re.search(r'\bTIME\b|void vertex\s*\(|wave_offset', combined):
            issues.append(Finding("STATIC_WATER", path.name,
                "Water has no observable wave animation/displacement"))
        if "SHIP_SCENE" in script and not re.search(
            r'AnimationPlayer|AnimationTree|_animate_ship|ship_motion|ship_velocity|ship\.position\s*[+\-]=|advance_visual_demo', script
        ) and not (path.name == "realistic_coastal_slice.tscn" and runtime_report is not None
                   and runtime_report.get("__ship_motion_verified__")):
            issues.append(Finding("STATIC_SHIP", path.name,
                "Ship placed but no ship movement/animation implementation observed"))
        if "coastal" in path.name.lower() and "slice" in path.name.lower():
            if not _resource_paths(combined) and not re.search(r'albedo_texture\s*=', script):
                issues.append(Finding("MISSING_PBR_ASSETS", path.name,
                    "No imported GLTF or PBR texture assignments in coastal slice"))
        scene_key = "res://" + path.relative_to(root).as_posix()
        if runtime_report is not None and scene_key in runtime_report:
            issues.extend(inspect_scene_nodes_runtime(scene_key, runtime_report[scene_key]))
        else:
            for asset in sorted(_resource_paths(combined)):
                issues.extend(_inspect_gltf(root, asset))
    capture = root / "tests/render_capture.gd"
    if count and capture.is_file():
        try:
            source = _read_source(root, "tests/render_capture.gd")
        except (OSError, ValueError, UnicodeError) as exc:
            issues.append(Finding("UNSAFE_RESOURCE", "tests/render_capture.gd", str(exc)))
            source = ""
        if any(path.stem in source for path in scenes.rglob("*.tscn") if path.name != "boot.tscn" and path.name not in PROTOTYPES):
            if "get_image()" in source and "RenderingServer.frame_post_draw" not in source:
                issues.append(Finding("STALE_CAPTURE", "tests/render_capture.gd",
                                      "Godot viewport read lacks renderer completion fence"))
            if "get_image()" in source and not re.search(r'get_pixel\s*\(|histogram|variation|pixel_variance', source, re.I):
                issues.append(Finding("BLANK_CAPTURE", "tests/render_capture.gd",
                                      "No pixel/content assertion proves capture contains rendered scenery"))
    if not count:
        issues.append(Finding("NO_CANDIDATE", "scenes", "No production graphics candidate exists"))
    return issues, count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", type=Path, default=Path("client-godot"))
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    args = parser.parse_args()
    runtime = None
    if (args.client / "tests/audit_runtime_graphics.gd").is_file():
        try:
            runtime = _runtime_report(args.client, args.godot_bin)
        except (ValueError, OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
            print(f"::error::RUNTIME_PROBE: {exc}")
            return 1
    issues, candidates = audit(args.client, runtime)
    print(f"Candidate scenes scanned: {candidates}")
    for item in issues:
        print(f"::{'warning' if item.severity == 'review' else 'error'}::{item}")
    if not candidates:
        print("No production graphics candidate exists: visual milestone NOT VERIFIED")
    else:
        print("Structural/runtime audit does NOT certify artistic reference parity or mobile FPS")
    print(f"Structural findings: {len(issues)}")
    return int(any(item.severity == "error" for item in issues))


if __name__ == "__main__":
    sys.exit(main())
