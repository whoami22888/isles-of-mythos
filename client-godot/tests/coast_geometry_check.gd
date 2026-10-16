extends SceneTree
func _init() -> void:
 var scene := Node3D.new()
 scene.set_script(load("res://scripts/island_preview.gd"))
 var mesh: ArrayMesh = scene.call("_build_coast_mesh")
 var arrays := mesh.surface_get_arrays(0)
 var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
 var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
 for i in range(0, positions.size(), 3):
  var cross_y := (positions[i+1]-positions[i]).cross(positions[i+2]-positions[i]).y
  if cross_y >= -0.000001:
   push_error("Invalid triangle at %s" % i)
   scene.free()
   quit(1)
   return
 for normal in normals:
  if normal.y <= 0.0:
   push_error("Invalid generated normal")
   scene.free()
   quit(1)
   return
 print("PASS actual Godot mesh: %d vertices, upward normals, clockwise faces" % positions.size())
 scene.free()
 quit(0)
