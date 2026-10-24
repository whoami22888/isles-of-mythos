extends SceneTree
## Focused Godot 4.7.2 regression for terrain/water sampling agreement.
## Runs without external art, a display, or a physical Android device.

const SHORE := preload("res://scripts/coastal_shore_heightfield.gd")

func _init() -> void:
	call_deferred("_run")


func _make_terrain() -> MeshInstance3D:
	const columns := 5
	const rows := 4
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in range(rows):
		for x in range(columns):
			var y := 0.5 + 0.7 * float(x) + 1.2 * float(z)
			vertices.append(Vector3(float(x) * 2.0 - 4.0, y, float(z) * 3.0 - 4.5))
	for z in range(rows - 1):
		for x in range(columns - 1):
			var i := z * columns + x
			indices.append_array([i, i + columns, i + 1, i + 1, i + columns, i + columns + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var terrain := MeshInstance3D.new()
	terrain.mesh = mesh
	terrain.position = Vector3(4.0, 2.0, -7.0)
	return terrain


func _run() -> void:
	var terrain := _make_terrain()
	root.add_child(terrain)
	var baked := SHORE.bake(terrain, 5, 4)
	var ok := not baked.has("error")
	if ok:
		var image: Image = baked["image"]
		var origin: Vector2 = baked["origin"]
		var extent: Vector2 = baked["extent"]
		var size: Vector2i = baked["resolution"]
		ok = size == Vector2i(5, 4)
		ok = ok and origin.distance_to(Vector2(0.0, -11.5)) < 0.001
		ok = ok and extent.distance_to(Vector2(8.0, 9.0)) < 0.001
		# Every baked texel must match the actual translated mesh vertex.
		var vertices: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for z in range(4):
			for x in range(5):
				var world: Vector3 = terrain.global_transform * vertices[z * 5 + x]
				var queried := SHORE.sample_height(baked, Vector2(world.x, world.z))
				ok = ok and absf(image.get_pixel(x, z).r - world.y) < 0.0001
				ok = ok and absf(queried - world.y) < 0.0001
		# Texel-centre UVs stop foam shifting by half a grid sample.
		var zero_uv: Vector2 = SHORE.uv_for_world(baked, origin)
		var end_uv: Vector2 = SHORE.uv_for_world(baked, origin + extent)
		ok = ok and zero_uv.distance_to(Vector2(0.1, 0.125)) < 0.0001
		ok = ok and end_uv.distance_to(Vector2(0.9, 0.875)) < 0.0001
		# On a planar heightfield, bilinear interpolation also agrees between vertices.
		var centre := origin + extent * 0.5
		var expected_centre := (image.get_pixel(0, 0).r + image.get_pixel(4, 3).r) * 0.5
		ok = ok and absf(SHORE.sample_height(baked, centre) - expected_centre) < 0.0001
		var repeat := SHORE.bake(terrain, 5, 4)
		ok = ok and not repeat.has("error") and repeat["image"].get_data() == image.get_data()

	# Invalid sample counts and rotated/non-axis-aligned geometry must fail closed.
	ok = ok and SHORE.bake(terrain, 4, 4).has("error")
	terrain.rotation_degrees.y = 20.0
	ok = ok and SHORE.bake(terrain, 5, 4).has("error")
	terrain.rotation_degrees.y = 0.0

	var material := ShaderMaterial.new()
	var wrong_shader := Shader.new()
	wrong_shader.code = "shader_type spatial; void fragment() { ALBEDO = vec3(0.0); }"
	material.shader = wrong_shader
	ok = ok and SHORE.bind_to_material(terrain, material, 5, 4).has("error")
	var shoreline_shader := Shader.new()
	shoreline_shader.code = "shader_type spatial;\n#include \"res://shaders/coastal_shore_sampler.gdshaderinc\"\nvoid fragment() { ALBEDO = vec3(shore_terrain_coverage(vec2(0.0))); }"
	material.shader = shoreline_shader
	var bound := SHORE.bind_to_material(terrain, material, 5, 4)
	ok = ok and not bound.has("error") and bound["texture"] is Texture2D
	ok = ok and material.get_shader_parameter("shore_heightmap") is Texture2D
	ok = ok and material.get_shader_parameter("shore_texture_size") == Vector2(5.0, 4.0)

	if not ok:
		push_error("Coastal shore heightfield contract FAILED")
	print("Coastal shore heightfield contract: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
