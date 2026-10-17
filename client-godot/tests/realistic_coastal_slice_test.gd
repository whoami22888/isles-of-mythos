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
	# The water is now a subdivided, multiscale animated ocean, not a flat
	# coloured plane with three rectangular white foam strips.
	if water != null:
		var water_mesh := water.mesh as PlaneMesh
		var water_material := water.material_override as ShaderMaterial
		ok = ok and water_mesh != null and water_mesh.subdivide_width >= 96 and water_mesh.subdivide_depth >= 96
		ok = ok and water_material != null and water_material.shader != null
		if water_material != null and water_material.shader != null:
			var ocean_source := water_material.shader.code
			ok = ok and ocean_source.contains("coastal_shore_sampler.gdshaderinc") and not ocean_source.contains("coastal_floor_height")
			ok = ok and ocean_source.contains("NORMAL_MAP")
			ok = ok and ocean_source.contains("contact * foam_motion")
			ok = ok and ocean_source.contains("swell_crest")
	for child in scene.get_children():
		if child is MeshInstance3D and child.mesh is QuadMesh:
			ok = false
	ok = ok and rock_count == 4 and tree_count == 4 and ship_count == 1 and gameplay.current
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
	ok = ok and cinematic.current and scene._cinematic_active and cinematic.position.distance_to(Vector3(-11.0, 5.5, -18.0)) < 0.01
	# Both cameras must see the coast as a background BEHIND the ship.
	ok = ok and cinematic.position.z < scene.ship_focal.position.z - 5.0
	ok = ok and gameplay.position.z < scene.ship_focal.position.z - 5.0
	scene.skip_cinematic()
	ok = ok and gameplay.current and not scene._cinematic_active
	if not ok:
		push_error("Realistic coastal slice contract failed")
	print("Realistic coastal slice test: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
