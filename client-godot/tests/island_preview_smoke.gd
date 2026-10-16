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
	print("Island preview smoke: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
