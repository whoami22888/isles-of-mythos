"""Deterministically author a mobile-ready coastal cliff LOD package in Blender.

This script consumes only the already admitted CC0 Poly Haven cliff source. It
keeps the source PBR material slots and exports two reduced, textured GLBs for
Godot 4.7.2 Mobile validation. It does not claim visual or device acceptance.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import bpy


SEED = 18601
BLENDER_VERSION = bpy.app.version_string
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/external/polyhaven/coastal_cliff_01/coastal_cliff_01_1k.gltf"
OUT = ROOT / "assets/external/generated/coastal_cliff_blender"
BLEND_OUT = ROOT.parent / "graphics/blender"
RATIOS = {"lod1": 0.28, "lod2": 0.10}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.cameras, bpy.data.lights, bpy.data.curves):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def export_object(obj: bpy.types.Object, destination: Path) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(destination),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    BLEND_OUT.mkdir(parents=True, exist_ok=True)
    if not SOURCE.is_file():
        raise SystemExit(f"missing admitted source: {SOURCE}")

    source_digest = sha256(SOURCE)
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    imported = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(imported) != 1:
        raise SystemExit(f"expected one source mesh, found {len(imported)}")
    source = imported[0]
    source.name = "CoastalCliff_LOD0_Source"
    source["asset_role"] = "coastal_cliff"
    source["license"] = "CC0-1.0"
    source["source_url"] = "https://polyhaven.com/a/coastal_cliff_01"
    source["source_sha256"] = source_digest
    source["authoring_seed"] = SEED
    source["blender_version"] = BLENDER_VERSION

    generated = {"lod0_source_triangles": len(source.data.polygons)}
    for name, ratio in RATIOS.items():
        obj = source.copy()
        obj.data = source.data.copy()
        obj.name = f"CoastalCliff_{name.upper()}"
        bpy.context.collection.objects.link(obj)
        modifier = obj.modifiers.new(name="DeterministicMobileDecimate", type="DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = ratio
        modifier.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj["asset_role"] = "coastal_cliff"
        obj["license"] = "CC0-1.0"
        obj["source_url"] = "https://polyhaven.com/a/coastal_cliff_01"
        obj["source_sha256"] = source_digest
        obj["authoring_seed"] = SEED
        obj["lod_ratio"] = ratio
        generated[f"{name}_triangles"] = len(obj.data.polygons)
        export_object(obj, OUT / f"coastal_cliff_{name}.glb")
        obj.hide_render = True
        obj.hide_viewport = True

    blend_path = BLEND_OUT / "coastal_cliff_authoring.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    # Blender creates a rotating .blend1 backup when overwriting. It is not an
    # authored deliverable and would make the package non-reproducible.
    backup = blend_path.with_suffix(".blend1")
    if backup.exists():
        backup.unlink()
    metadata = {
        "schema_version": 1,
        "asset": "coastal_cliff",
        "license": "CC0-1.0",
        "source_url": "https://polyhaven.com/a/coastal_cliff_01",
        "source_sha256": source_digest,
        "blender_version": BLENDER_VERSION,
        "authoring_seed": SEED,
        "ratios": RATIOS,
        "geometry": generated,
        "outputs": {
            "blend": sha256(blend_path),
            "lod1_glb": sha256(OUT / "coastal_cliff_lod1.glb"),
            "lod2_glb": sha256(OUT / "coastal_cliff_lod2.glb"),
        },
        "godot_validation": "PENDING_GODOT_4.7.2_MOBILE",
    }
    (OUT / "BLENDER_BUILD_METADATA.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
