extends SceneTree

func _init() -> void:
	call_deferred("run")


func run() -> void:
	var scene := load("res://scenes/island_preview.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var player := scene.get_node_or_null("PreviewPlayer")
	var camera := scene.get_node_or_null("IslandCamera") as Camera3D
	var ok := player != null and camera != null and camera.current
	if ok:
		scene._touch_target = Vector3(40.0, 0.0, 40.0).limit_length(scene.ISLAND_RADIUS - 1.1)
		scene._touch_active = true
		scene._physics_process(0.1)
		ok = player.position.length() <= scene.ISLAND_RADIUS - 1.09
	if not ok:
		push_error("Island preview camera, player or bounded touch movement failed")
	scene.queue_free()
	print("Island preview smoke: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
