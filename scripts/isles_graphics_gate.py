#!/usr/bin/env python3
"""Fail-closed *structural* graphics checks; human Godot-video parity is separate."""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import struct
# The audit intentionally launches a user-selected, locally verified Godot binary.
import subprocess  # nosec B404
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

JsonObject = Dict[str, Any]
RuntimeReport = Dict[str, Any]

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


def _source_graph(root: Path, scene: str) -> Tuple[str, List[str], List[Finding]]:
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


def _resource_paths(text: str) -> Set[str]:
    return {p for p in RESOURCE_RE.findall(text) if p.endswith((".gltf", ".glb"))}


def _safe_resource(root: Path, rel: str) -> Path:
    path = root / rel
    if ".." in Path(rel).parts or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError("Resource escapes the client root")
    return path


def _model_payload(path: Path) -> bytes:
    """Read the bounded JSON payload from a glTF or GLB container."""
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
            return stream.read(size)
    if path.stat().st_size > MAX_JSON_BYTES:
        raise ValueError("Oversized GLTF JSON")
    return path.read_bytes()


def _model_collection(document: JsonObject, key: str) -> List[JsonObject]:
    """Return a validated object collection from a model document."""
    value = document.get(key, [])
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise ValueError("Invalid model collection: " + key)
    return value


def _model_index(document: JsonObject, value: Any, collection: str) -> None:
    """Validate an exact integer index into a model collection."""
    items = _model_collection(document, collection)
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value < len(items):
        raise ValueError("Invalid " + collection + " index")


def _validate_materials(document: JsonObject) -> None:
    for material in _model_collection(document, "materials"):
        if not isinstance(material.get("name", ""), str):
            raise ValueError("Invalid material name")
        pbr = material.get("pbrMetallicRoughness", {})
        if not isinstance(pbr, dict):
            raise ValueError("Invalid PBR object")
        color = pbr.get("baseColorTexture", {})
        if not isinstance(color, dict):
            raise ValueError("Invalid base color texture")
        if "index" in color:
            _model_index(document, color["index"], "textures")


def _validate_textures_and_images(document: JsonObject) -> None:
    for texture in _model_collection(document, "textures"):
        if "source" in texture:
            _model_index(document, texture["source"], "images")
    for image in _model_collection(document, "images"):
        if not isinstance(image.get("uri", ""), str):
            raise ValueError("Invalid image URI")


def _validate_accessors(document: JsonObject) -> None:
    for accessor in _model_collection(document, "accessors"):
        count = accessor.get("count", 0)
        if isinstance(count, bool) or not isinstance(count, int) or count < 0:
            raise ValueError("Invalid accessor count")


def _validate_primitive(document: JsonObject, primitive: JsonObject) -> None:
    if "indices" in primitive:
        _model_index(document, primitive["indices"], "accessors")
    attributes = primitive.get("attributes", {})
    if not isinstance(attributes, dict):
        raise ValueError("Invalid attributes")
    if "POSITION" in attributes:
        _model_index(document, attributes["POSITION"], "accessors")
    mode = primitive.get("mode", 4)
    if isinstance(mode, bool) or not isinstance(mode, int) or mode not in range(7):
        raise ValueError("Invalid primitive mode")


def _validate_meshes(document: JsonObject) -> None:
    for mesh in _model_collection(document, "meshes"):
        if not isinstance(mesh.get("name", ""), str):
            raise ValueError("Invalid mesh name")
        primitives = mesh.get("primitives", [])
        if not isinstance(primitives, list) or not all(
            isinstance(primitive, dict) for primitive in primitives
        ):
            raise ValueError("Invalid primitives")
        for primitive in primitives:
            _validate_primitive(document, primitive)


def _model_document(path: Path) -> JsonObject:
    """Load and validate the model fields consumed by the structural audit."""
    doc = json.loads(_model_payload(path))
    if not isinstance(doc, dict):
        raise ValueError("Model JSON must be an object")
    for key in ("materials", "textures", "images", "accessors", "meshes"):
        _model_collection(doc, key)
    _validate_materials(doc)
    _validate_textures_and_images(doc)
    _validate_accessors(doc)
    _validate_meshes(doc)
    return doc


def _foliage_findings(document: JsonObject, rel: str) -> List[Finding]:
    """Find alpha materials backed by formats that cannot carry alpha."""
    issues: List[Finding] = []
    materials = _model_collection(document, "materials")
    textures = _model_collection(document, "textures")
    images = _model_collection(document, "images")
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
            issues.append(
                Finding(
                    "FOLIAGE_ALPHA",
                    rel,
                    f"{name}: unresolved base-color texture",
                )
            )
            continue
        if uri.lower().endswith((".jpg", ".jpeg")) or image.get("mimeType") == "image/jpeg":
            issues.append(
                Finding(
                    "FOLIAGE_ALPHA",
                    rel,
                    f"{name}: {alpha_mode} base texture is JPEG without alpha; "
                    "provide a pinned opacity map",
                )
            )
    return issues


def _mesh_triangle_count(mesh: JsonObject, accessors: List[JsonObject]) -> int:
    """Calculate triangle count for validated indexed or non-indexed primitives."""
    triangles = 0
    for primitive in mesh.get("primitives", []):
        accessor_index = primitive.get(
            "indices", primitive.get("attributes", {}).get("POSITION")
        )
        if accessor_index is None:
            continue
        count = accessors[accessor_index].get("count", 0)
        mode = primitive.get("mode", 4)
        if mode == 4:
            triangles += count // 3
        elif mode in (5, 6):
            triangles += max(0, count - 2)
    return triangles


def _geometry_findings(document: JsonObject, rel: str) -> List[Finding]:
    """Find high-poly source meshes without an explicit nonzero LOD identity."""
    issues: List[Finding] = []
    accessors = _model_collection(document, "accessors")
    for mesh in _model_collection(document, "meshes"):
        triangles = _mesh_triangle_count(mesh, accessors)
        name = mesh.get("name", "")
        if triangles > TRIANGLE_REVIEW_LIMIT and not re.search(r"LOD[1-9]", name, re.I):
            issues.append(
                Finding(
                    "HEAVY_LOD0",
                    rel,
                    f"{name or 'unnamed'}: {triangles:,} triangles/mesh; "
                    "mobile LOD and profiling required",
                )
            )
    return issues


def _inspect_gltf(root: Path, rel: str) -> List[Finding]:
    try:
        path = _safe_resource(root, rel)
    except ValueError as exc:
        return [Finding("UNSAFE_RESOURCE", rel, str(exc))]
    if not path.is_file():
        return [Finding("MISSING_MODEL", rel, "Referenced imported GLTF does not exist")]
    try:
        doc = _model_document(path)
    except (ValueError, UnicodeError, OSError) as exc:
        return [Finding("INVALID_MODEL", rel, str(exc))]
    return _foliage_findings(doc, rel) + _geometry_findings(doc, rel)


def inspect_scene_nodes_runtime(
    scene_path: str, meshes: List[JsonObject]
) -> List[Finding]:
    """Audit mesh surfaces and materials observed in an instantiated Godot scene."""
    issues: List[Finding] = []
    seen: Set[Tuple[str, str]] = set()
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


def _run_godot(
    executable: str, arguments: List[str], timeout: int
) -> subprocess.CompletedProcess:
    """Run a verified executable with fixed argv and no command shell."""
    command = [executable] + arguments
    # No shell is involved, and the executable is resolved and checked before use.
    return subprocess.run(  # nosec B603
        command,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
        shell=False,
    )


def _valid_runtime_surface(surface: Any) -> bool:
    """Validate the exact runtime surface schema consumed by the audit."""
    if not isinstance(surface, dict):
        return False
    triangles = surface.get("triangles")
    if not isinstance(triangles, (int, float)) or isinstance(triangles, bool):
        return False
    if triangles < 0:
        return False
    transparency = surface.get("transparency")
    if not isinstance(transparency, int) or isinstance(transparency, bool):
        return False
    expected_types = {
        "material": str,
        "albedo_alpha": bool,
        "texture": str,
    }
    return all(isinstance(surface.get(key), kind) for key, kind in expected_types.items())


def _validate_runtime_mesh(mesh: Any) -> None:
    if not isinstance(mesh, dict):
        raise ValueError("Invalid runtime mesh report")
    if not isinstance(mesh.get("node"), str):
        raise ValueError("Invalid runtime mesh report")
    surfaces = mesh.get("surfaces")
    if not isinstance(surfaces, list):
        raise ValueError("Invalid runtime mesh report")
    if not all(_valid_runtime_surface(surface) for surface in surfaces):
        raise ValueError("Invalid runtime surface report")


def _validate_runtime_report(report: Any) -> RuntimeReport:
    """Reject missing scenes and malformed runtime-probe records."""
    if not isinstance(report, dict) or not report:
        raise ValueError("Godot runtime probe report is empty")
    required = {
        "res://scenes/realistic_coastal_slice.tscn",
        "res://scenes/realistic_coastal_fx_slice.tscn",
    }
    if not required.issubset(report):
        raise ValueError("Godot runtime probe omitted a production coastal scene")
    if not isinstance(report.get("__ship_motion_verified__"), bool):
        raise ValueError("Godot runtime probe omitted ship movement result")
    for scene, meshes in report.items():
        if scene == "__ship_motion_verified__":
            continue
        if not isinstance(scene, str) or not scene.startswith("res://scenes/"):
            raise ValueError("Invalid runtime scene report")
        if not isinstance(meshes, list) or not meshes:
            raise ValueError("Invalid runtime scene report")
        for mesh in meshes:
            _validate_runtime_mesh(mesh)
    return report


def _runtime_report(root: Path, godot_bin: str) -> RuntimeReport:
    """Instantiate production scenes with Godot 4.7.2; reject incomplete output."""
    resolved = shutil.which(godot_bin)
    if not resolved:
        raise ValueError(f"Godot binary unavailable: {godot_bin}")
    executable = str(Path(resolved).resolve())
    if not Path(executable).is_file() or not os.access(executable, os.X_OK):
        raise ValueError(f"Godot executable is not a runnable file: {executable}")
    version = _run_godot(executable, ["--version"], timeout=10)
    version_text = version.stdout.strip()
    if version.returncode or not re.match(r"^4\.7\.2\.stable(?:\.|$)", version_text):
        raise ValueError(f"Godot 4.7.2-stable required, got: {version_text}")
    result = _run_godot(
        executable,
        [
            "--headless",
            "--rendering-method",
            "mobile",
            "--path",
            str(root),
            "--script",
            "res://tests/audit_runtime_graphics.gd",
        ],
        timeout=120,
    )
    if result.returncode:
        raise ValueError(f"Godot runtime probe failed ({result.returncode}): {(result.stdout + result.stderr)[-2000:]}")
    if re.search(r"(?m)^(?:SCRIPT ERROR:|ERROR:|RUNTIME_GRAPHICS_FAIL:)", result.stdout + result.stderr):
        raise ValueError(f"Godot runtime probe logged an error: {(result.stdout + result.stderr)[-2000:]}")
    markers = [line.removeprefix("RUNTIME_GRAPHICS_JSON=") for line in result.stdout.splitlines()
               if line.startswith("RUNTIME_GRAPHICS_JSON=")]
    if len(markers) != 1:
        raise ValueError("Godot runtime probe produced no unique report")
    return _validate_runtime_report(json.loads(markers[0]))


def _basic_scene_findings(
    path: Path, combined: str, scripts: List[str]
) -> List[Finding]:
    """Check source identity, prototype dependencies, terrain, and foam."""
    issues: List[Finding] = []
    script = "\n".join(scripts)
    has_art = re.search(
        r"res://assets/[\w./-]+\.(?:gltf|glb)|albedo_texture|texture_albedo",
        combined,
    )
    if not scripts and not has_art:
        issues.append(
            Finding(
                "NO_ART_SOURCE",
                path.name,
                "Candidate has neither inspectable script nor imported/PBR art",
            )
        )
    prototype_used = any(
        f"res://scenes/{name}" in combined
        or f"res://scripts/{name.replace('.tscn', '.gd')}" in combined
        for name in PROTOTYPES
    )
    if prototype_used:
        issues.append(
            Finding(
                "PROTOTYPE_DEPENDENCY",
                path.name,
                "Player-facing candidate imports a known placeholder scene/script",
            )
        )
    terrain_match = re.search(r"func _terrain_material\b", script)
    if terrain_match:
        terrain_body = script.split("func _terrain_material", 1)[1]
        terrain_body = re.split(r"\nfunc [\w_]+\(", terrain_body, maxsplit=1)[0]
        maps = ("albedo_texture", "normal_texture", "roughness_texture")
        if not all(texture in terrain_body for texture in maps):
            issues.append(
                Finding(
                    "FLAT_TERRAIN",
                    path.name,
                    "Final terrain material lacks albedo/normal/roughness texture assignments",
                )
            )
    if re.search(r"foam[^\n]*QuadMesh\.new\(\)|QuadMesh\.new\(\)[^\n]*foam", script, re.I):
        issues.append(
            Finding(
                "FLAT_FOAM",
                path.name,
                "Shoreline foam uses unanimated quad strips; not reference-quality surf",
            )
        )
    return issues


def _water_findings(path: Path, combined: str) -> List[Finding]:
    """Check observable water depth and motion implementation."""
    issues: List[Finding] = []
    depth_sources = re.search(
        r"depth_texture|DEPTH_TEXTURE|depth_sample|hint_depth_texture|shore_terrain_height",
        combined,
        re.I,
    )
    uv_depth_only = all(token in combined for token in ("shallow", "deep", "UV.y"))
    if uv_depth_only and not depth_sources:
        issues.append(
            Finding(
                "FAKE_WATER_DEPTH",
                path.name,
                "Water-depth colour is derived only from mesh UV instead of scene depth",
            )
        )
    animated = re.search(r"\bTIME\b|void vertex\s*\(|wave_offset", combined)
    if "ShallowToDeepWater" in combined and not animated:
        issues.append(
            Finding(
                "STATIC_WATER",
                path.name,
                "Water has no observable wave animation/displacement",
            )
        )
    return issues


def _ship_and_asset_findings(
    path: Path,
    combined: str,
    script: str,
    runtime_report: Optional[RuntimeReport],
) -> List[Finding]:
    """Check ship movement evidence and coastal imported/PBR resources."""
    issues: List[Finding] = []
    motion = re.search(
        r"AnimationPlayer|AnimationTree|_animate_ship|ship_motion|ship_velocity|"
        r"ship\.position\s*[+\-]=|advance_visual_demo",
        script,
    )
    runtime_motion = (
        path.name == "realistic_coastal_slice.tscn"
        and runtime_report is not None
        and runtime_report.get("__ship_motion_verified__") is True
    )
    if "SHIP_SCENE" in script and not motion and not runtime_motion:
        issues.append(
            Finding(
                "STATIC_SHIP",
                path.name,
                "Ship placed but no ship movement/animation implementation observed",
            )
        )
    is_coastal_slice = "coastal" in path.name.lower() and "slice" in path.name.lower()
    has_pbr = _resource_paths(combined) or re.search(r"albedo_texture\s*=", script)
    if is_coastal_slice and not has_pbr:
        issues.append(
            Finding(
                "MISSING_PBR_ASSETS",
                path.name,
                "No imported GLTF or PBR texture assignments in coastal slice",
            )
        )
    return issues


def _scene_findings(
    root: Path, path: Path, runtime_report: Optional[RuntimeReport]
) -> List[Finding]:
    """Audit one production scene and its reachable dependencies."""
    combined, scripts, issues = _source_graph(root, str(path.relative_to(root)))
    script = "\n".join(scripts)
    issues.extend(_basic_scene_findings(path, combined, scripts))
    issues.extend(_water_findings(path, combined))
    issues.extend(_ship_and_asset_findings(path, combined, script, runtime_report))
    scene_key = "res://" + path.relative_to(root).as_posix()
    if runtime_report is not None and scene_key in runtime_report:
        meshes = runtime_report[scene_key]
        if not isinstance(meshes, list):
            issues.append(Finding("INVALID_RUNTIME", scene_key, "Runtime meshes are not a list"))
        else:
            issues.extend(inspect_scene_nodes_runtime(scene_key, meshes))
    else:
        for asset in sorted(_resource_paths(combined)):
            issues.extend(_inspect_gltf(root, asset))
    return issues


def _capture_findings(root: Path, scenes: Path, candidate_count: int) -> List[Finding]:
    """Check the legacy capture script for render fencing and content assertions."""
    capture = root / "tests/render_capture.gd"
    if not candidate_count or not capture.is_file():
        return []
    try:
        source = _read_source(root, "tests/render_capture.gd")
    except (OSError, ValueError, UnicodeError) as exc:
        return [Finding("UNSAFE_RESOURCE", "tests/render_capture.gd", str(exc))]
    candidates = (
        path
        for path in scenes.rglob("*.tscn")
        if path.name != "boot.tscn" and path.name not in PROTOTYPES
    )
    if not any(path.stem in source for path in candidates):
        return []
    issues: List[Finding] = []
    if "get_image()" in source and "RenderingServer.frame_post_draw" not in source:
        issues.append(
            Finding(
                "STALE_CAPTURE",
                "tests/render_capture.gd",
                "Godot viewport read lacks renderer completion fence",
            )
        )
    content_check = re.search(
        r"get_pixel\s*\(|histogram|variation|pixel_variance", source, re.I
    )
    if "get_image()" in source and not content_check:
        issues.append(
            Finding(
                "BLANK_CAPTURE",
                "tests/render_capture.gd",
                "No pixel/content assertion proves capture contains rendered scenery",
            )
        )
    return issues


def audit(
    root: Path, runtime_report: Optional[RuntimeReport] = None
) -> Tuple[List[Finding], int]:
    """Return source-observable blockers and candidate count; never claim parity."""
    project = root / "project.godot"
    if not project.is_file():
        return [Finding("MISSING_PROJECT", str(project), "Godot client project absent")], 0
    try:
        project_text = _read_source(root, "project.godot")
    except (OSError, ValueError, UnicodeError) as exc:
        return [Finding("UNSAFE_RESOURCE", "project.godot", str(exc))], 0
    issues: List[Finding] = []
    match = re.search(r'^run/main_scene="res://scenes/([^"]+)"', project_text, re.M)
    if match and match.group(1) in PROTOTYPES:
        issues.append(
            Finding(
                "PROTOTYPE_LAUNCH",
                "project.godot",
                f"Prototype is player-facing main_scene: {match.group(1)}",
            )
        )
    scenes = root / "scenes"
    candidates = [
        path
        for path in sorted(scenes.rglob("*.tscn"))
        if path.name != "boot.tscn" and path.name not in PROTOTYPES
    ]
    for path in candidates:
        issues.extend(_scene_findings(root, path, runtime_report))
    issues.extend(_capture_findings(root, scenes, len(candidates)))
    if not candidates:
        issues.append(Finding("NO_CANDIDATE", "scenes", "No production graphics candidate exists"))
    return issues, len(candidates)


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
