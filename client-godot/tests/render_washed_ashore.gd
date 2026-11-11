extends SceneTree
## Headless-friendly capture of the washed-ashore scene from its real cameras.
## Not a CI gate.
## IOM_ASHORE_POSE=wake|intro|intro_hull|follow|hut|dusk|offshore
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
			scene._begin_dusk()
			_walk(scene, scene._landmark_position("camp") + Vector3(-3.5, 0, -3.5), Vector3(1, 0, 1))
		"offshore":
			_walk(scene, Vector3(-5.0, 0, 2.6), Vector3(-0.1, 0, -1))
	for _i in 30:
		await process_frame
		if pose == "wake":
			scene._cine_age = 1.6
		elif pose.begins_with("intro"):
			scene.snap_intro_camera()
		else:
			scene._follow_camera(10.0)
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
	scene._step = "clearing"
	scene._follow_camera(10.0)
