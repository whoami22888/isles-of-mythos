import bpy,json,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[2]
out=root/'assets/external/generated/bounded_lods';out.mkdir(parents=True,exist_ok=True)
records=[]
for name,cap in [('tree_small_02',90000),('island_tree_01',72000),('island_tree_02',72000),('coast_rocks_05',30000)]:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 src=root/f'assets/external/polyhaven/{name}/{name}_1k.gltf'
 bpy.ops.import_scene.gltf(filepath=str(src))
 obj=next(o for o in bpy.context.scene.objects if o.type=='MESH')
 before=sum(len(p.vertices)-2 for p in obj.data.polygons)
 mod=obj.modifiers.new('AuthoredLOD','DECIMATE');mod.ratio=(cap-100)/before;mod.use_collapse_triangulate=True
 bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=mod.name)
 after=sum(len(p.vertices)-2 for p in obj.data.polygons)
 assert after<=cap,(name,after,cap)
 bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
 dest=out/f'{name}.glb'
 bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',use_selection=True,export_tangents=True,export_materials='EXPORT')
 records.append(dict(asset=name,before=before,after=after,source_sha256=hashlib.sha256(src.read_bytes()).hexdigest(),output_sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),blender=bpy.app.version_string))
 (out/'metadata.json').write_text(json.dumps(records,indent=2))
 print('BOUNDED',name,before,after,dest.stat().st_size,flush=True)
