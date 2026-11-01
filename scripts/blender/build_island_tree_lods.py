"""Export reproducible far-scatter island-tree LOD2 GLBs from admitted meshes."""
import argparse
import importlib
import sys
from pathlib import Path

bpy = importlib.import_module("bpy")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source.resolve()))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError(f"Expected one authored mesh, got {len(meshes)}")
    mesh = meshes[0]
    before = len(mesh.data.polygons)
    if before < 15000:
        raise RuntimeError("Input is already under the far-scatter budget")
    materials_before = {material.name for material in mesh.data.materials}
    modifier = mesh.modifiers.new("FarScatterLOD2", "DECIMATE")
    modifier.ratio = min(1.0, 14000.0 / before)
    bpy.context.view_layer.objects.active = mesh
    mesh.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    after = len(mesh.data.polygons)
    if not 0 < after < 15000:
        raise RuntimeError(f"LOD2 triangle budget not met: {after}")
    if {material.name for material in mesh.data.materials} != materials_before or not mesh.data.uv_layers:
        raise RuntimeError("LOD2 lost authored material regions or UVs")
    mesh.name = args.source.stem + "_LOD2"
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(args.output.resolve()), export_format="GLB",
                              use_selection=True, export_texcoords=True, export_normals=True,
                              export_materials="EXPORT")
    print(f"IOM_LOD2 {args.source.name}: {before} -> {after} triangles; {len(materials_before)} material regions")


if __name__ == "__main__":
    main()
