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
	st.train("sailor")
	st.train("crew_musketeer")
	st.train("sailor")
	st.tick(100.0)
	await frames(3)
	scene.raid.wave = 2
	scene.raid.start_warning()
	scene.raid._spawn_wave()
	# Pull the raiders up the beach to the palisade line.
	for u in scene.raid.units:
		if u["team"] == "enemy":
			var p: Vector3 = u["node"].global_position + Vector3(0, 0, 3.0)
			p.y = scene.ground_y(p.x, p.z)
			u["node"].global_position = p
	var pal: Vector3 = scene.site_pos("palisade")
	scene._player.global_position = Vector3(pal.x + 1.5, scene.ground_y(pal.x + 1.5, pal.z - 1.6), pal.z - 1.6)
	scene._cam_yaw = deg_to_rad(165.0)
	scene.snap_camera()
	await frames(24)
	scene.strike_enemy()
	await frames(4)
	root.get_viewport().get_texture().get_image().save_png(dir.path_join("raid_palisade.png"))
	print("shot raid_palisade")
	await frames(30)
	scene.strike_enemy()
	await frames(5)
	root.get_viewport().get_texture().get_image().save_png(dir.path_join("raid_melee.png"))
	print("shot raid_melee  enemies=%d crew=%d palisade_hp=%d" % [scene.raid.enemies_alive(), scene.raid.crew_alive(), int(st.hp_of("palisade"))])
	quit()
