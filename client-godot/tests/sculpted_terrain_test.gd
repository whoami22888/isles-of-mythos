extends SceneTree
## Run: godot --headless --path client-godot --script res://tests/sculpted_terrain_test.gd

func _initialize() -> void:
    var script := load("res://scripts/sculpted_island_terrain.gd")
    if script == null:
        push_error("Terrain script unavailable")
        quit(1)
        return
    # The terrain is an unparented Node3D (an Object, not RefCounted): it must be freed explicitly on every
    # path, otherwise Godot reports leaked ObjectDB instances and resources at exit.
    var terrain: Node3D = script.new()
    var ok := _check(terrain)
    terrain.free()
    quit(0 if ok else 1)

func _check(terrain: Node3D) -> bool:
    var mesh: ArrayMesh = terrain.build_mesh()
    var arrays := mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
    var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
    var expected_vertices: int = 1 + terrain.radial_segments * terrain.ring_segments
    var expected_indices: int = 3 * terrain.radial_segments * (2 * terrain.ring_segments - 1)
    if vertices.size() != expected_vertices or indices.size() != expected_indices or colors.size() != expected_vertices:
        push_error("Unexpected terrain topology")
        return false
    for i in range(0, indices.size(), 3):
        var a := vertices[indices[i]]
        var b := vertices[indices[i + 1]]
        var c := vertices[indices[i + 2]]
        var face: Vector3 = (b - a).cross(c - a)
        if face.length_squared() < 0.00000001:
            push_error("Degenerate triangle at %d" % i)
            return false
        if face.y >= -0.00000001:
            push_error("Triangle has incorrect Godot front-face winding at %d" % i)
            return false
    if absf(terrain.terrain_height(0.0, 0.0) - terrain.terrain_height(0.0, PI)) > 0.0001:
        push_error("Central terrain height depends on angle")
        return false
    if terrain.terrain_height(0.55, 0.0) <= terrain.terrain_height(0.8, 0.0) + 1.0:
        push_error("Cliff rise is missing")
        return false
    for normal in normals:
        if not normal.is_finite() or normal.y <= 0.0:
            push_error("Invalid or downward-facing terrain normal")
            return false
    var second: ArrayMesh = terrain.build_mesh()
    if second.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != vertices:
        push_error("Terrain geometry is not deterministic")
        return false
    print("PASS sculpted terrain topology, winding, normals and determinism")
    return true
