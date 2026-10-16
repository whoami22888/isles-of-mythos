extends SceneTree
## Run: godot --headless --path client-godot --script res://tests/test_sculpted_island_terrain.gd

func _initialize() -> void:
	var terrain_script := load("res://scripts/sculpted_island_terrain.gd")
	var terrain: Node3D = terrain_script.new()
	terrain.radial_segments = 32
	terrain.ring_segments = 12
	var first: ArrayMesh = terrain.build_mesh()
	var second: ArrayMesh = terrain.build_mesh()
	var a: Array = first.surface_get_arrays(0)
	var b: Array = second.surface_get_arrays(0)
	var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	assert(vertices.size() == 1 + 32 * 12, "unexpected vertex count")
	assert(indices.size() == 32 * (1 + 2 * 11) * 3, "unexpected triangle count")
	assert(vertices == b[Mesh.ARRAY_VERTEX], "terrain generation is nondeterministic")
	assert(indices == b[Mesh.ARRAY_INDEX], "index generation is nondeterministic")
	for i in range(0, indices.size(), 3):
		var va: Vector3 = vertices[indices[i]]
		var vb: Vector3 = vertices[indices[i + 1]]
		var vc: Vector3 = vertices[indices[i + 2]]
		var face: Vector3 = (vb - va).cross(vc - va)
		assert(face.length_squared() > 0.00000001, "degenerate triangle")
		assert(face.y > 0.0, "terrain triangle faces down")
	for normal in normals:
		assert(normal.length_squared() > 0.9, "invalid vertex normal")
		assert(normal.y > 0.0, "vertex normal faces down")
	print("PASS: deterministic terrain geometry, nondegenerate faces, upward normals")
	terrain.free()
	quit(0)
