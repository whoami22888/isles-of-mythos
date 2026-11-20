extends SceneTree
## Fast-forward outpost stills (no real-time waiting). Clears saves, enters the
## outpost, renders the empty plots, then fast-forwards the economy so every
## building stands and renders the built village.
## IOM_SHOTS=/abs/dir (default /workspace/iom-shots/outpost_m1). Needs a renderer.

var scene: Node

func _init() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func shot(dir: String, name: String) -> void:
	await frames(20)
	root.get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("shot ", name)

func run() -> void:
	var dir := OS.get_environment("IOM_SHOTS")
	if dir == "":
		dir = "/workspace/iom-shots/outpost_m1"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["user://washed_ashore.cfg", "user://outpost.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	scene = load("res://gameplay/outpost/outpost.tscn").instantiate()
	root.add_child(scene)
	await frames(5)
	scene.stand_at("mill")
	scene._player.global_position += Vector3(2.5, 0, -0.5)
	scene._player.global_position.y = scene.ground_y(scene._player.global_position.x, scene._player.global_position.z)
	scene.snap_camera()
	await shot(dir, "outpost_plots")
	var st = scene.state
	for k in 500:
		for r in st.inv.keys():
			st.inv[r] = 9999
		for id in ["camp", "mill", "dock", "palisade", "forge", "watchtower", "barracks"]:
			if st.block_reason(id) == "":
				st.start(id)
		st.tick(10.0)
	scene._refresh_sites(true)
	for r in st.inv.keys():
		st.inv[r] = 400
	print("levels camp=%d %s" % [st.camp_level, st.buildings])
	scene._player.global_position = Vector3(11.0, scene.ground_y(11.0, 8.4), 8.4)
	scene._cam_yaw = deg_to_rad(192.0)
	scene.snap_camera()
	await shot(dir, "outpost_built")
	quit()
