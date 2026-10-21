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
	ok = ok and water != null and gameplay != null and cinematic != null
	var depth_layer := scene.get_node_or_null("CoastalPBRDepthLayer")
	ok = ok and rock_count == 4 and tree_count == 4 and ship_count == 1 and gameplay.current
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
						ok = ok and material.albedo_texture != null
						ok = ok and material.albedo_color.get_luminance() > 0.8
						ok = ok and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		for child in ship_node.get_children():
			pending_ship.append(child)
	ok = ok and sail_materials > 0
	# The premium content layer must contain real varied tropical geometry; a
	# shader-only or palette-only replacement cannot satisfy the coastal brief.
	var premium_layer := scene.get_node_or_null("VerifiedTropicalContentLayer")
	ok = ok and premium_layer != null and premium_layer.get_child_count() == 7
	if premium_layer:
		var premium_paths := []
		for child in premium_layer.get_children():
			ok = ok and child is Node3D and child.scene_file_path != ""
			premium_paths.append(child.scene_file_path)
		ok = ok and premium_paths.any(func(path): return path.ends_with("coastal_cliff_01_1k.gltf"))
		ok = ok and premium_paths.any(func(path): return path.ends_with("island_tree_01_1k.gltf"))
		ok = ok and premium_paths.any(func(path): return path.ends_with("island_tree_02_1k.gltf"))
		var cliff_count := 0
		for child in premium_layer.get_children():
			if child.scene_file_path.ends_with("coastal_cliff_01_1k.gltf"):
				cliff_count += 1
				var cliff_bounds: AABB = scene.visual_bounds_world(child)
				# Imported cliff bounds must remain a background landmark, not a
				# camera-spanning occluder or a second terrain wall.
				ok = ok and cliff_bounds.size.x < 50.0 and cliff_bounds.size.z < 35.0
				ok = ok and cliff_bounds.position.z > scene.ship_focal.position.z + 8.0
		ok = ok and cliff_count == 1
		if premium_layer:
			for child in premium_layer.get_children():
				if child.scene_file_path.ends_with("island_tree_01_1k.gltf") or child.scene_file_path.ends_with("island_tree_02_1k.gltf"):
					var foliage_mesh := child.get_child(0).mesh as ArrayMesh
					ok = ok and foliage_mesh != null and foliage_mesh.get_surface_count() == 3
					var foliage_triangles := 0
					for surface_index in range(foliage_mesh.get_surface_count()):
						var indices: PackedInt32Array = foliage_mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX]
						foliage_triangles += indices.size() / 3
					ok = ok and foliage_triangles <= 72000
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
					ok = ok and lod_triangles < 150000
	# Guard against reintroducing the sparse 24x18 rectangular mound and
	# disconnected beach/cliff relief that failed owner visual inspection.
	var terrain_points: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	ok = ok and terrain_points.size() >= 6000
	ok = ok and scene._terrain_height(0.0, 15.0) > scene._terrain_height(0.0, -12.0) + 3.0
	ok = ok and absf(scene._terrain_height(-15.0, -6.0) - scene._terrain_height(15.0, -6.0)) > 0.3
	ok = ok and scene.player_marker.position.y > scene._terrain_height(0.0, 5.5)
	scene.play_cinematic(true)
	ok = ok and gameplay.current and not scene._cinematic_active
	scene.play_cinematic()
	ok = ok and cinematic.current and scene._cinematic_active
	# The previous *exact camera coordinate* contract clipped the imported
	# ship's mast. Instead require a seaward camera with ALL geometry in view.
	ok = ok and scene._ship_bounds_ready
	var bounds: AABB = scene.ship_visual_bounds_world()
	ok = ok and bounds.size.y > 0.01
	for corner in range(8):
		var world_pt: Vector3 = bounds.position + Vector3(
			bounds.size.x if corner & 1 else 0.0,
			bounds.size.y if corner & 2 else 0.0,
			bounds.size.z if corner & 4 else 0.0
		)
		var projected: Vector2 = cinematic.unproject_position(world_pt)
		ok = ok and not cinematic.is_position_behind(world_pt)
		ok = ok and projected.x > 32.0 and projected.x < 1248.0
		ok = ok and projected.y > 32.0 and projected.y < 688.0
	# Both cameras must see the coast as a background BEHIND the ship.
	ok = ok and cinematic.position.z < scene.ship_focal.position.z - 5.0
	ok = ok and gameplay.position.z < scene.ship_focal.position.z - 5.0
	scene.skip_cinematic()
	ok = ok and gameplay.current and not scene._cinematic_active
	if not ok:
		push_error("Realistic coastal slice contract failed")
	print("Realistic coastal slice test: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
