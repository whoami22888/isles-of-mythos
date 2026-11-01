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
						ok = _check(material.albedo_color.get_luminance() > 0.8, "contract line 52") and ok
						ok = _check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "contract line 53") and ok
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
		for child in premium_layer.get_children():
			if child.scene_file_path.ends_with("coastal_cliff_01_1k.gltf"):
				cliff_count += 1
				var cliff_mesh := child.get_child(0) as MeshInstance3D
				var cliff_triangles := 0
				if cliff_mesh != null and cliff_mesh.mesh != null:
					for surface_index in range(cliff_mesh.mesh.get_surface_count()):
						var indices: PackedInt32Array = cliff_mesh.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX]
						cliff_triangles += indices.size() / 3
				ok = _check(cliff_triangles > 0 and cliff_triangles <= 60000, "cliff runtime LOD budget") and ok
				var cliff_bounds: AABB = scene.visual_bounds_world(child)
				# Imported cliff bounds must remain a background landmark, not a
				# camera-spanning occluder or a second terrain wall.
				ok = _check(cliff_bounds.size.x < 50.0 and cliff_bounds.size.z < 35.0, "contract line 76") and ok
				ok = _check(cliff_bounds.position.z > scene.ship_focal.position.z + 8.0, "contract line 77") and ok
		ok = _check(cliff_count == 3, "contract line 78") and ok
		if premium_layer:
			for child in premium_layer.get_children():
				if child.scene_file_path.ends_with("island_tree_01_1k.gltf") or child.scene_file_path.ends_with("island_tree_02_1k.gltf"):
					var foliage_node := child.get_child(0) as MeshInstance3D
					var foliage_mesh := foliage_node.mesh as ArrayMesh
					ok = _check(foliage_mesh != null and foliage_mesh.get_surface_count() == 3, "contract line 83") and ok
					var foliage_triangles := 0
					var leaf_alpha_verified := false
					for surface_index in range(foliage_mesh.get_surface_count()):
						var indices: PackedInt32Array = foliage_mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX]
						foliage_triangles += indices.size() / 3
						var material := foliage_node.get_active_material(surface_index) as BaseMaterial3D
						if material != null and str(material.resource_name).contains("leaves") and material.albedo_texture != null:
							leaf_alpha_verified = material.albedo_texture.get_image().detect_alpha() != Image.ALPHA_NONE
					ok = _check(foliage_triangles > 0 and foliage_triangles < 15000, "distant foliage LOD budget") and ok
					ok = _check(leaf_alpha_verified, "distant foliage has real albedo alpha") and ok
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
	quit(0 if ok else 1)

func _check(condition: bool, label: String) -> bool:
	if not condition:
		printerr("FAILED: " + label)
	return condition
