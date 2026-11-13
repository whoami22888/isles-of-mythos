extends SceneTree
## Headless-friendly capture of the washed-ashore scene from its real cameras.
## Not a CI gate.
## IOM_ASHORE_POSE=wake|intro|intro_hull|follow|hut|dusk|offshore|gather|ghost|built|pet_point|trees_a|trees_b|cook
## IOM_ASHORE_SHOT=/absolute/path.png

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var pose := OS.get_environment("IOM_ASHORE_POSE")
	if pose.is_empty():
		pose = "intro"
	var output := OS.get_environment("IOM_ASHORE_SHOT")
	if output.is_empty():
		output = "user://washed-ashore.png"
	if FileAccess.file_exists("user://washed_ashore.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://washed_ashore.cfg"))
	var scene = load("res://gameplay/ashore/washed_ashore.tscn").instantiate()
	scene.begin_authenticated_session("ws://127.0.0.1:9/ws", "capture")
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.apply_opening_outcome("hull" if pose == "intro_hull" else "mast")
	if pose == "wake":
		scene._cine_age = 1.6
		scene._wake_camera()
	else:
		scene.skip_cinematic()
	match pose:
		"follow":
			_walk(scene, Vector3(0.5, 0, 4.8), Vector3(1, 0, 0.25))
		"hut":
			scene._spot = 1
			scene._move_hut()
			scene._show_hut(3)
			_walk(scene, scene._pad_position(1) + Vector3(-2.0, 0, -5.0), Vector3(0.35, 0, 1))
		"dusk":
			scene._health = 999
			_free_pet(scene)
			_walk(scene, Vector3(-11.0, 0, 6.0), Vector3(0.3, 0, 1))
			scene._step = "shelter"
			scene._enter("dusk")
		"offshore":
			_walk(scene, Vector3(-5.0, 0, 2.6), Vector3(-0.1, 0, -1))
		"gather":
			_free_pet(scene)
			var tree: Dictionary = scene._node_by_id("tree_a")
			var at: Vector3 = (tree["root"] as Node3D).global_position
			_walk(scene, at + Vector3(-0.6, 0, -2.2), Vector3(0.25, 0, 1))
			scene._cam_yaw += 0.5
		"ghost", "built":
			_free_pet(scene)
			_walk(scene, Vector3(-9.6, 0, 4.4), Vector3(-0.6, 0, 1))
			scene._step = "fire"
			for k in ["wood", "stone", "fibre", "planks", "rope"]:
				scene._inv[k] = 9
			scene.on_build_pick("campfire")
			scene._tick_ghost()
			if not scene._ghost_ok:
				scene._ghost_pin = scene._nearest_site("campfire", scene._ghost.global_position, 4.0)
				scene._tick_ghost()
			if pose == "built":
				scene.on_build_place()
				scene.on_build_pick("lean_to")
				scene._ghost_pin = scene._nearest_site("lean_to", scene._player.global_position + Vector3(2.5, 0, 2.5), 6.0)
				scene._tick_ghost()
				scene.on_build_place()
				for i in 16:
					scene._tick_build(0.5)
				scene._cam_yaw += 0.35
		"pet_point":
			_free_pet(scene)
			_walk(scene, Vector3(-10.5, 0, 6.5), Vector3(0.1, 0, 1))
			scene._step = "gather"
			scene._start_sniff()
			var goal: Vector3 = scene._pet_goal
			scene._pet.global_position = goal
			scene._pet.position.y = scene._ground_y(goal.x, goal.z)
		"trees_a":
			_free_pet(scene)
			_walk(scene, Vector3(-9.5, 0, 7.4), Vector3(0, 0, -1))
		"trees_b":
			_free_pet(scene)
			_walk(scene, Vector3(-13.0, 0, 12.5), Vector3(-1, 0, 0.2))
	for _i in 30:
		await process_frame
		if pose == "gather" and _i == 21:
			var tree_node: Dictionary = scene._node_by_id("tree_a")
			for _h in scene._hits_for(tree_node):
				scene._gather_lock = 0.0
				scene._act_on_node(tree_node)
		if pose == "dusk" and _i < 29:
			scene._beast.global_position = scene._beast.global_position
		if pose == "wake":
			scene._cine_age = 1.6
		elif pose.begins_with("intro"):
			scene.snap_intro_camera()
		else:
			scene._follow_camera(1.0 / 30.0 if pose.begins_with("trees") else 10.0)
		await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Ashore capture produced an empty image")
		quit(1)
		return
	image.save_png(output)
	print("Ashore capture wrote %s (%dx%d)" % [output, image.get_width(), image.get_height()])
	quit(0)


func _walk(scene: Node, at: Vector3, facing: Vector3) -> void:
	var player := scene._player as Node3D
	at.y = scene._ground_y(at.x, at.z)
	player.position = at
	player.look_at(at + facing, Vector3.UP)
	scene._cam_yaw = player.rotation.y
	scene._intro_k = 0.0
	scene._step = "gather"
	scene._follow_camera(10.0)


func _free_pet(scene: Node) -> void:
	scene._pet_freed = true
	scene._pet.visible = true
	var pile: Dictionary = scene._node_by_id("pet_pile")
	if not pile.is_empty():
		pile["depleted"] = true
		(pile["root"] as Node3D).visible = false
