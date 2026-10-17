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
	for child in scene.get_children():
		if child.scene_file_path.ends_with("coast_rocks_05_1k.gltf"):
			rock_count += 1
		if child.scene_file_path.ends_with("tree_small_02_1k.gltf"):
			tree_count += 1
	var ok := terrain != null and terrain.mesh != null and terrain.mesh.get_surface_count() == 1
	ok = ok and water != null and gameplay != null and cinematic != null
	ok = ok and rock_count == 4 and tree_count == 4 and gameplay.current
	if not ok:
		push_error("Realistic coastal slice contract failed")
	print("Realistic coastal slice test: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
