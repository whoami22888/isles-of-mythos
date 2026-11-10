extends SceneTree
## Budget and quality contract for the tropical bay dressing. Not a visual-parity claim.

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var scene: Node3D = load("res://scenes/realistic_coastal_slice.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var ok := true
	var dressing := scene.get_node_or_null("TropicalBayDressing")
	ok = _check(dressing != null, "dressing node") and ok
	var palms := dressing.get_node_or_null("TropicalPalmGrove") as MultiMeshInstance3D if dressing else null
	var grass := dressing.get_node_or_null("TropicalGrassTufts") as MultiMeshInstance3D if dressing else null
	ok = _check(palms != null and palms.multimesh != null, "palm multimesh") and ok
	ok = _check(grass != null and grass.multimesh != null, "grass multimesh") and ok
	if palms and palms.multimesh:
		ok = _check(palms.multimesh.visible_instance_count >= 24, "enough palms for a grove") and ok
		ok = _check(palms.multimesh.visible_instance_count <= 32, "palm instance cap") and ok
	var dressing_script = load("res://scripts/tropical_bay_dressing.gd")
	ok = _check(dressing_script.palm_triangle_count() < 15000, "palm mesh stays cheap") and ok
	ok = _check(scene.get_node_or_null("TropicalBayDressing/DistantVolcano") != null, "volcano landmark") and ok
	ok = _check(scene.get_node_or_null("TropicalBayDressing/HazyIslets") != null, "distant islets") and ok
	var premium := scene.get_node_or_null("VerifiedTropicalContentLayer")
	if premium:
		for child in premium.get_children():
			if child.scene_file_path.ends_with("coastal_cliff_01_1k.gltf"):
				var triangles := 0
				for mesh_node in child.find_children("*", "MeshInstance3D", true, false):
					var mesh_instance := mesh_node as MeshInstance3D
					if mesh_instance.mesh == null:
						continue
					for surface_index in range(mesh_instance.mesh.get_surface_count()):
						var indices: PackedInt32Array = mesh_instance.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX]
						triangles += indices.size() / 3
				ok = _check(triangles < 200, "cliff proxy triangle budget") and ok
	scene.apply_visual_quality(0)
	if palms and palms.multimesh:
		ok = _check(palms.multimesh.visible_instance_count <= 32, "low quality reduces palms") and ok
		ok = _check(grass.multimesh.visible_instance_count == 0, "low quality drops grass cards") and ok
	var sun := scene.get_node_or_null("WarmSun") as DirectionalLight3D
	ok = _check(sun != null and not sun.shadow_enabled, "low quality disables shadows") and ok
	ok = _check(scene.get_viewport().msaa_3d == Viewport.MSAA_DISABLED, "low quality disables MSAA") and ok
	scene.apply_visual_quality(2)
	ok = _check(sun.shadow_enabled, "high quality restores shadows") and ok
	ok = _check(scene.get_viewport().msaa_3d == Viewport.MSAA_2X, "high quality uses 2x MSAA") and ok
	ok = _check(_outward_faces(dressing_script, "landmass") == 0, "volcano/islet landmass faces point up") and ok
	ok = _check(_outward_faces(dressing_script, "box") == 0, "hut wall faces point outward") and ok
	ok = _check(_outward_faces(dressing_script, "roof") == 0, "hut roof faces point outward") and ok
	ok = _check(_outward_faces(dressing_script, "trunk") == 0, "palm trunk faces point outward") and ok
	ok = _check(_landmass_boundary_submerged(dressing_script), "landmass outer ring sits below sea level") and ok
	var smoke := scene.get_node_or_null("TropicalBayDressing/DistantVolcano/VolcanoSmoke") as Node3D
	var crater := scene.get_node_or_null("TropicalBayDressing/DistantVolcano/VolcanoLandmass") as MeshInstance3D
	if smoke and crater:
		var floor_y: float = (crater.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0].y
		ok = _check(smoke.position.y >= floor_y and smoke.position.y - floor_y <= 1.0, "volcano smoke emits from the crater floor") and ok
	else:
		ok = _check(false, "volcano smoke and landmass nodes") and ok
	print("Tropical bay dressing test: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

func _check(condition: bool, label: String) -> bool:
	if not condition:
		printerr("FAILED: " + label)
	return condition

# Godot front faces are clockwise: for (a, b, c) the outward normal is
# (c - a) x (b - a). Each closed primitive must face away from its own centre,
# or cull_back draws only its far inside wall. Returns the inward face count.
func _outward_faces(dressing_script, kind: String) -> int:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	match kind:
		"landmass":
			var arrays: Array = dressing_script.landmass_mesh(18.0, 14.0, 12.0, 2.0, 0.2).surface_get_arrays(0)
			vertices = arrays[Mesh.ARRAY_VERTEX]
			indices = arrays[Mesh.ARRAY_INDEX]
		"box":
			dressing_script._add_box(vertices, colors, indices, Vector3(1.0, 2.0, 3.0), Vector3(2.0, 1.5, 1.0), Color.WHITE)
		"roof":
			dressing_script._add_prism_roof(vertices, colors, indices, Vector3(1.0, 2.0, 3.0), Vector3(2.0, 1.0, 1.5), Color.WHITE)
		"trunk":
			var arrays: Array = dressing_script._palm_mesh().surface_get_arrays(0)
			vertices = arrays[Mesh.ARRAY_VERTEX]
			normals = arrays[Mesh.ARRAY_NORMAL]
			# The first 6 sides x 4 segments x 2 triangles are the closed trunk.
			indices = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).slice(0, 6 * 4 * 6)
	var used := {}
	for index in indices:
		used[index] = true
	var centre := Vector3.ZERO
	for index in used.keys():
		centre += vertices[index]
	centre /= float(maxi(used.size(), 1))
	var inward := 0
	for t in range(0, indices.size(), 3):
		var a := vertices[indices[t]]
		var b := vertices[indices[t + 1]]
		var c := vertices[indices[t + 2]]
		var outward := (c - a).cross(b - a)
		var face_centre := (a + b + c) / 3.0
		var from_centre := face_centre - centre
		if kind == "landmass":
			# A heightfield-style island: every face must face the sky.
			from_centre = Vector3.UP
		elif not normals.is_empty():
			# The leaning trunk has authored normals; winding must agree with them.
			from_centre = normals[indices[t]] + normals[indices[t + 1]] + normals[indices[t + 2]]
		if outward.dot(from_centre) <= 0.0:
			inward += 1
	if inward > 0:
		printerr("%s: %d of %d faces point inward" % [kind, inward, indices.size() / 3])
	return inward

# Every boundary vertex must sit under the ocean (y = -0.35) so the island
# meets the water instead of ending in an open edge. Uses the shipped seeds.
func _landmass_boundary_submerged(dressing_script) -> bool:
	var cases := [
		[19.0, 16.0, 19.0, 3.1, 0.22, 10, 30],
		[17.0, 12.0, 7.5, 1.3, 0.0, 10, 30],
		[13.0, 10.0, 5.0, 2.7, 0.0, 10, 30],
		[21.0, 14.0, 6.0, 4.4, 0.0, 10, 30],
		[15.0, 11.0, 4.2, 5.9, 0.0, 10, 30],
		[6.5, 2.75, 5.8, -14.0 * 0.37, 0.0, 5, 16],
		[6.5, 2.75, 5.8, 2.5 * 0.37, 0.0, 5, 16],
		[6.5, 2.75, 5.8, 16.5 * 0.37, 0.0, 5, 16],
	]
	for c in cases:
		var mesh: ArrayMesh = dressing_script.landmass_mesh(c[0], c[1], c[2], c[3], c[4], c[5], c[6])
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var sectors: int = c[6]
		for i in range(vertices.size() - sectors, vertices.size()):
			if vertices[i].y >= -0.35:
				printerr("landmass seed %.2f boundary vertex %d at y=%.3f" % [c[3], i, vertices[i].y])
				return false
	return true
