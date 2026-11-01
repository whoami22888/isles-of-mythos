extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var scene: Node3D = load("res://scenes/realistic_coastal_slice.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var terrain := scene.get_node_or_null("IrregularCoastalTerrain") as MeshInstance3D
	var water := scene.get_node_or_null("ShallowToDeepWater") as MeshInstance3D
	var gameplay := scene.get_node_or_null("GameplayCamera") as Camera3D
	var cinematic := scene.get_node_or_null("CinematicRevealCamera") as Camera3D
	var rock_count := 0
	var tree_count := 0
	var ship_count := 0
	for child in scene.get_children():
		if child.scene_file_path.ends_with("coast_rocks_05_1k.gltf"):
			rock_count += 1
		if child.scene_file_path.ends_with("tree_small_02_1k.gltf"):
			tree_count += 1
		if child.name == "HarbourShipFocalPoint":
			ship_count += 1
	var ok := terrain != null and terrain.mesh != null and terrain.mesh.get_surface_count() == 1
	ok = _check(water != null and gameplay != null and cinematic != null, "contract line 26") and ok
	var depth_layer := scene.get_node_or_null("CoastalPBRDepthLayer")
	ok = _check(rock_count == 4 and tree_count == 4 and ship_count == 1 and gameplay.current, "contract line 28") and ok
	var spawn_marker_count := 0
	for child in scene.get_children():
		if child.name == "PlayerSpawnMarker":
			spawn_marker_count += 1
	ok = _check(spawn_marker_count == 1 and scene.player_marker != null, "contract line 33") and ok
	# Imported sails must retain their authored RGBA atlas and mobile-safe
	# alpha-mask material; a missing/black material is a visible ship failure.
	var sail_materials := 0
	var pending_ship: Array[Node] = [scene.ship_focal]
	while not pending_ship.is_empty():
		var ship_node: Node = pending_ship.pop_back()
		if ship_node is MeshInstance3D:
			var mesh_instance := ship_node as MeshInstance3D
			if mesh_instance.mesh:
				for surface_index in range(mesh_instance.mesh.get_surface_count()):
					var material := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
					if material == null:
						continue
					var material_name := str(material.resource_name).to_lower()
					var node_name := str(mesh_instance.name).to_lower()
					if material_name.contains("sail") or node_name.contains("sail"):
						sail_materials += 1
						ok = _check(material.albedo_texture != null, "contract line 51") and ok
						if material.albedo_texture != null:
							ok = _check(material.albedo_texture.get_width() >= 1024 and material.albedo_texture.get_height() >= 1024,
								"sail weave must retain the admitted 1024px CC0 atlas") and ok
						ok = _check(material.albedo_color.get_luminance() > 1.0, "Mobile sail texture needs a bright warm lift") and ok
						ok = _check(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
							"sails stay readable under the Mobile Vulkan backlight") and ok
						# Opaque + double-sided: alpha scissor with cull disabled
						# rendered unlit black canvas on the Mobile renderer.
						ok = _check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "contract line 53") and ok
						ok = _check(material.cull_mode == BaseMaterial3D.CULL_DISABLED, "sails must be double-sided") and ok
		for child in ship_node.get_children():
			pending_ship.append(child)
	ok = _check(sail_materials > 0, "contract line 56") and ok
	# The premium content layer must contain real varied tropical geometry; a
	# shader-only or palette-only replacement cannot satisfy the coastal brief.
	var premium_layer := scene.get_node_or_null("VerifiedTropicalContentLayer")
	ok = _check(premium_layer != null and premium_layer.get_child_count() == 9, "contract line 60") and ok
	if premium_layer:
		var premium_paths := []
		for child in premium_layer.get_children():
			ok = _check(child is Node3D and child.scene_file_path != "", "contract line 64") and ok
			premium_paths.append(child.scene_file_path)
		ok = _check(premium_paths.any(func(path): return path.ends_with("coastal_cliff_01_1k.gltf")), "contract line 66") and ok
		ok = _check(premium_paths.any(func(path): return path.ends_with("island_tree_01_1k.gltf")), "contract line 67") and ok
		ok = _check(premium_paths.any(func(path): return path.ends_with("island_tree_02_1k.gltf")), "contract line 68") and ok
		var cliff_count := 0
		var total_cliff_triangles := 0
		for child in premium_layer.get_children():
			if child.scene_file_path.ends_with("coastal_cliff_01_1k.gltf"):
				cliff_count += 1
				var cliff_bounds: AABB = scene.visual_bounds_world(child)
				# Imported cliff bounds must remain a background landmark, not a
				# camera-spanning occluder or a second terrain wall.
				ok = _check(cliff_bounds.size.x < 50.0 and cliff_bounds.size.z < 35.0, "contract line 76") and ok
				ok = _check(cliff_bounds.position.z > scene.ship_focal.position.z + 8.0, "contract line 77") and ok
				# The unbounded source cliff is 461,824 triangles; every cliff
				# instance must render an admitted LOD within the 90k cap.
				var cliff_triangles := 0
				for mesh_node in child.find_children("*", "MeshInstance3D", true, false):
					cliff_triangles += scene._triangle_count((mesh_node as MeshInstance3D).mesh)
				var expected_cap := 90000 if is_equal_approx(child.position.x, 21.0) else 60000
				total_cliff_triangles += cliff_triangles
				ok = _check(cliff_triangles > 0 and cliff_triangles <= expected_cap,
					"cliff at x=%.1f uses requested %d triangle LOD cap" % [child.position.x, expected_cap]) and ok
		ok = _check(cliff_count == 3, "contract line 78") and ok
		ok = _check(total_cliff_triangles <= 210000,
			"three cliffs remain within the combined per-instance LOD budgets") and ok
		# Negative fixture: the unbounded source cliff must violate the same cap,
		# proving the per-instance check above would catch a skipped LOD.
		var unbounded_cliff: Node3D = scene.COASTAL_CLIFF_SCENE.instantiate()
		var unbounded_mesh_nodes: Array[Node] = unbounded_cliff.find_children("*", "MeshInstance3D", true, false)
		if unbounded_mesh_nodes.is_empty():
			ok = _check(false, "negative fixture loads the source cliff mesh") and ok
		else:
			var unbounded_mesh_instance := unbounded_mesh_nodes[0] as MeshInstance3D
			ok = _check(scene._triangle_count(unbounded_mesh_instance.mesh) > 90000,
				"negative fixture: unbounded cliff source exceeds the cap") and ok
			scene._apply_cliff_lod(unbounded_cliff, 1, false)
			ok = _check(not unbounded_cliff.visible,
				"negative fixture: no cliff LOD fit fails closed instead of rendering the unbounded source") and ok
		# This detached imported scene owns ObjectDB instances and RenderingServer
		# RIDs. Free it explicitly; otherwise a successful regression exits with
		# leaked GLTF nodes, materials, meshes and renderer allocations.
		unbounded_cliff.free()
		if premium_layer:
			for child in premium_layer.get_children():
				if child.scene_file_path.ends_with("island_tree_01_1k.gltf") or child.scene_file_path.ends_with("island_tree_02_1k.gltf"):
					var foliage_mesh := child.get_child(0).mesh as ArrayMesh
					ok = _check(foliage_mesh != null and foliage_mesh.get_surface_count() == 3, "contract line 83") and ok
					var foliage_triangles := 0
					for surface_index in range(foliage_mesh.get_surface_count()):
						var indices: PackedInt32Array = foliage_mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX]
						foliage_triangles += indices.size() / 3
					ok = _check(foliage_triangles <= 72000, "contract line 88") and ok
	# Every visible imported landmark keeps its authored materials while using
	# a deterministic triangle cap. This guards the capture watchdog regression
	# without allowing a bare placeholder or an unbounded source mesh back in.
	for child in scene.get_children():
		if child.scene_file_path.ends_with("tree_small_02_1k.gltf"):
			var near_tree_triangles := 0
			for mesh_node in child.find_children("*", "MeshInstance3D", true, false):
				var near_mesh := mesh_node as MeshInstance3D
				if near_mesh.mesh:
					for surface_index in range(near_mesh.mesh.get_surface_count()):
						near_tree_triangles += (near_mesh.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			ok = _check(near_tree_triangles <= 90000, "contract line 100") and ok
		elif child.scene_file_path.ends_with("coast_rocks_05_1k.gltf"):
			var rock_triangles := 0
			for mesh_node in child.find_children("*", "MeshInstance3D", true, false):
				var rock_mesh := mesh_node as MeshInstance3D
				if rock_mesh.mesh:
					for surface_index in range(rock_mesh.mesh.get_surface_count()):
						rock_triangles += (rock_mesh.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			ok = _check(rock_triangles <= 30000, "contract line 108") and ok
	# Background trees must use an explicit material-preserving geometry LOD.
	if depth_layer:
		for child in depth_layer.get_children():
			if child.scene_file_path.ends_with("tree_small_02_1k.gltf"):
				var lod_mesh := child.get_child(0).mesh as ArrayMesh
				var lod_triangles := 0
				for surface_index in range(lod_mesh.get_surface_count()):
					var lod_arrays := lod_mesh.surface_get_arrays(surface_index)
					var lod_indices: PackedInt32Array = lod_arrays[Mesh.ARRAY_INDEX]
					lod_triangles += (lod_indices.size() / 3) if not lod_indices.is_empty() else 0
					ok = _check(lod_triangles < 150000, "contract line 119") and ok
	# Guard against reintroducing the sparse 24x18 rectangular mound and
	# disconnected beach/cliff relief that failed owner visual inspection.
	var terrain_points: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	ok = _check(terrain_points.size() >= 6000, "contract line 123") and ok
	ok = _check(scene._terrain_height(0.0, 15.0) > scene._terrain_height(0.0, -12.0) + 3.0, "contract line 124") and ok
	ok = _check(absf(scene._terrain_height(-15.0, -6.0) - scene._terrain_height(15.0, -6.0)) > 0.3, "contract line 125") and ok
	ok = _check(scene.player_marker.position.y > scene._terrain_height(0.0, 5.5), "contract line 126") and ok
	# Regression: the terrain was emitted counter-clockwise, so Godot (clockwise
	# front faces) culled every upward-facing triangle and the beach rendered
	# behind the ocean. Every triangle must face up: for Godot's clockwise front
	# winding, (b - a) x (c - a) points DOWN for a surface seen from above.
	var terrain_arrays := terrain.mesh.surface_get_arrays(0)
	var terrain_vertices: PackedVector3Array = terrain_arrays[Mesh.ARRAY_VERTEX]
	var terrain_indices: PackedInt32Array = terrain_arrays[Mesh.ARRAY_INDEX]
	var upward_triangles := 0
	for t in range(0, terrain_indices.size(), 3):
		var a := terrain_vertices[terrain_indices[t]]
		var b := terrain_vertices[terrain_indices[t + 1]]
		var c := terrain_vertices[terrain_indices[t + 2]]
		if (b - a).cross(c - a).y < 0.0:
			upward_triangles += 1
	ok = _check(upward_triangles == terrain_indices.size() / 3, "terrain triangles must face up (clockwise front winding)") and ok
	# The beach must genuinely rise out of the sea with a sloped seabed in
	# front of it, not a sea-level sheet across the whole bay.
	ok = _check(scene._terrain_height(12.0, 7.0) > scene.WATER_Y + 0.2, "dry beach above sea level") and ok
	ok = _check(scene._terrain_height(12.0, -6.0) < scene.WATER_Y - 2.5, "offshore seabed has real depth") and ok
	ok = _check(scene._terrain_height(1.0, -5.8) < scene.WATER_Y - 1.5, "moored hull has clearance over the seabed") and ok
	scene.play_cinematic(true)
	ok = _check(gameplay.current and not scene._cinematic_active, "contract line 128") and ok
	scene.play_cinematic()
	ok = _check(cinematic.current and scene._cinematic_active, "contract line 130") and ok
	# The previous *exact camera coordinate* contract clipped the imported
	# ship's mast. Instead require a seaward camera with ALL geometry in view.
	ok = _check(scene._ship_bounds_ready, "contract line 133") and ok
	var bounds: AABB = scene.ship_visual_bounds_world()
	ok = _check(bounds.size.y > 0.01, "contract line 135") and ok
	for corner in range(8):
		var world_pt: Vector3 = bounds.position + Vector3(
			bounds.size.x if corner & 1 else 0.0,
			bounds.size.y if corner & 2 else 0.0,
			bounds.size.z if corner & 4 else 0.0
		)
		var projected: Vector2 = cinematic.unproject_position(world_pt)
		ok = _check(not cinematic.is_position_behind(world_pt), "contract line 143") and ok
		ok = _check(projected.x > 32.0 and projected.x < 1248.0, "contract line 144") and ok
		ok = _check(projected.y > 32.0 and projected.y < 688.0, "contract line 145") and ok
	# Both cameras must see the coast as a background BEHIND the ship.
	ok = _check(cinematic.position.z < scene.ship_focal.position.z - 5.0, "contract line 147") and ok
	ok = _check(gameplay.position.z < scene.ship_focal.position.z - 5.0, "contract line 148") and ok
	scene.skip_cinematic()
	ok = _check(gameplay.current and not scene._cinematic_active, "contract line 150") and ok
	if not ok:
		push_error("Realistic coastal slice contract failed")
	print("Realistic coastal slice test: %s" % ("PASS" if ok else "FAIL"))
	# Flush scene-owned rendering resources before quitting so leak diagnostics
	# report the test result rather than teardown noise from the fixture.
	scene.free()
	await process_frame
	await process_frame
	quit(0 if ok else 1)

func _check(condition: bool, label: String) -> bool:
	if not condition:
		printerr("FAILED: " + label)
	return condition
