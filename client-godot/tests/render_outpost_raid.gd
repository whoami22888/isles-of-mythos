extends SceneTree
## Combat stills for Milestone 2 (fast-forwarded, no real-time waiting).
## IOM_SHOTS=/abs/dir (default /workspace/iom-shots/outpost_m2). Needs a renderer.

func _init() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var dir := OS.get_environment("IOM_SHOTS")
	if dir == "":
		dir = "/workspace/iom-shots/outpost_m2"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["user://washed_ashore.cfg", "user://outpost.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var scene = load("res://gameplay/outpost/outpost.tscn").instantiate()
	root.add_child(scene)
	await frames(5)
	var st = scene.state
	for r in st.inv.keys():
		st.inv[r] = 3000
	for k in 300:
		for id in ["camp", "mill", "dock", "palisade", "forge", "watchtower", "barracks"]:
			if st.block_reason(id) == "":
				st.start(id)
		st.tick(10.0)
	scene._refresh_sites(true)
	for kind in ["sailor", "crew_musketeer", "sailor", "crew_musketeer"]:
		var why: String = st.train(kind)
		print("train ", kind, " -> '", why, "' slots=", st.crew_slots())
	st.tick(200.0)
	await frames(3)
	print("crew ready=%s fielded=%d" % [st.crew_ready, scene.raid.crew_alive()])
	scene.raid.wave = 2
	scene.raid.start_warning()
	scene.raid._spawn_wave()
	# Raiders massed at the stake line (south), crew and castaway behind it.
	var line: float = scene.raid.palisade_line()
	var pal: Vector3 = scene.site_pos("palisade")
	var i := 0
	for u in scene.raid.units:
		if u["team"] == "enemy":
			var p := Vector3(pal.x - 3.0 + (i % 4) * 1.6, 0, line - 0.8 - (i / 4) * 1.6)
			p.y = scene.ground_y(p.x, p.z)
			u["node"].global_position = p
			i += 1
	scene._player.global_position = Vector3(pal.x + 0.6, scene.ground_y(pal.x + 0.6, line + 1.4), line + 1.4)
	scene._cam_yaw = deg_to_rad(20.0)
	scene.snap_camera()
	await frames(40)
	print("crew=%d enemies=%d palisade_hp=%d" % [scene.raid.crew_alive(), scene.raid.enemies_alive(), int(st.hp_of("palisade"))])
	root.get_viewport().get_texture().get_image().save_png(dir.path_join("raid_palisade.png"))
	print("shot raid_palisade")
	quit()
