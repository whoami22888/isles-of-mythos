extends SceneTree

func _init() -> void:
	call_deferred("run")


func run() -> void:
	var scene = load("res://scenes/island_preview.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var player = scene.get_node_or_null("PreviewPlayer")
	var camera := scene.get_node_or_null("IslandCamera") as Camera3D
	var ok := player != null and camera != null and camera.current
	if ok:
		var starting_position: Vector3 = player.position
		var viewport_center: Vector2 = root.get_visible_rect().size * 0.5
		# Exercise actual camera ray projection and the touch-target setter.
		scene._set_touch_target(viewport_center + Vector2(150.0, 0.0))
		ok = scene._touch_active and scene._touch_target.distance_to(starting_position) > 0.2
		if ok:
			var target: Vector3 = scene._touch_target
			scene._physics_process(0.1)
			ok = player.position.distance_to(starting_position) > 0.01
			ok = ok and player.position.distance_to(target) < starting_position.distance_to(target)
			ok = ok and player.position.length() <= scene.ISLAND_RADIUS - 1.09
		if ok:
			# Verify a far-away navigation target cannot move past island bounds.
			scene._touch_target = Vector3(40.0, 0.0, 40.0).limit_length(scene.ISLAND_RADIUS - 1.1)
			scene._touch_active = true
			for index in range(80):
				scene._physics_process(0.1)
			ok = player.position.length() <= scene.ISLAND_RADIUS - 1.09
	if not ok:
		push_error("Island preview ray projection, movement or boundary check failed")
	scene.queue_free()
	# Exercise the sculpted preview in the existing pinned Godot 4.7.2 smoke job.
	var sculpted: Node3D = load("res://scenes/sculpted_terrain_preview.tscn").instantiate()
	root.add_child(sculpted)
	var coast: MeshInstance3D = sculpted.get_node_or_null("Terrain/SculptedCoast") as MeshInstance3D
	var sculpted_camera: Camera3D = sculpted.get_node_or_null("IslandCamera") as Camera3D
	var terrain_ok := coast != null and coast.mesh != null and sculpted_camera != null
	if terrain_ok:
		var forward: Vector3 = -sculpted_camera.global_transform.basis.z
		var toward_origin: Vector3 = (Vector3.ZERO - sculpted_camera.global_position).normalized()
		terrain_ok = forward.dot(toward_origin) > 0.99
		var arrays: Array = coast.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		terrain_ok = terrain_ok and vertices.size() == 2305 and indices.size() == 13536
	if not terrain_ok:
		push_error("Sculpted terrain scene, mesh topology or camera aim failed")
	ok = terrain_ok and ok
	sculpted.queue_free()
	print("Island preview smoke: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
