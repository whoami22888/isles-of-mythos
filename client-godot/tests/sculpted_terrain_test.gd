extends SceneTree
## Run: godot --headless --path client-godot --script res://tests/sculpted_terrain_test.gd

func _initialize() -> void:
    var script := load("res://scripts/sculpted_island_terrain.gd")
    if script == null:
        push_error("Terrain script unavailable")
        quit(1)
        return
    var terrain: Node3D = script.new()
    var mesh: ArrayMesh = terrain.build_mesh()
    var arrays := mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
    var expected_vertices: int = 1 + terrain.radial_segments * terrain.ring_segments
    var expected_indices: int = 3 * terrain.radial_segments * (2 * terrain.ring_segments - 1)
    if vertices.size() != expected_vertices or indices.size() != expected_indices:
        push_error("Unexpected terrain topology")
        quit(1)
        return
    for i in range(0, indices.size(), 3):
        var a := vertices[indices[i]]
        var b := vertices[indices[i + 1]]
        var c := vertices[indices[i + 2]]
        var face: Vector3 = (b - a).cross(c - a)
        if face.length_squared() < 0.00000001:
            push_error("Degenerate triangle at %d" % i)
            quit(1)
            return
        if face.y >= -0.00000001:
            push_error("Triangle has incorrect Godot front-face winding at %d" % i)
            quit(1)
            return
    for normal in normals:
        if not normal.is_finite() or normal.y <= 0.0:
            push_error("Invalid or downward-facing terrain normal")
            quit(1)
            return
    var second: ArrayMesh = terrain.build_mesh()
    if second.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != vertices:
        push_error("Terrain geometry is not deterministic")
        quit(1)
        return
    print("PASS sculpted terrain topology, winding, normals and determinism")
    quit(0)
