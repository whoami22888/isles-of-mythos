extends SceneTree
## M3 stills: the raft mid-strait and a close side-on stockade fight.
## IOM_SHOTS=/abs/dir (default /workspace/iom-shots/outpost_m3). Needs a renderer.

func _init() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func snap(dir: String, name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("shot ", name)

func run() -> void:
	var dir := OS.get_environment("IOM_SHOTS")
	if dir == "":
		dir = "/workspace/iom-shots/outpost_m3"
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
	var rs = scene.rescue
	st.waves_done = 2
	await frames(2)
	rs.read_bottle()
	rs.build_raft()
	st.raft_left = 0.01
	await frames(2)
	rs.set_sail()
	# Two-thirds of the way across, heading for the isle.
	var from: Vector3 = rs.dock_water()
	var mid: Vector3 = from.lerp(rs.moor, 0.72)
	rs.raft.global_position = mid
	scene._cam_yaw = rs._heading + PI
	await frames(30)
	scene.snap_camera()
	await frames(4)
	await snap(dir, "voyage")
	rs.arrive()
	await frames(3)
	# Pull the first wave down to the castaway and frame it side-on, close.
	var p: Vector3 = rs.landing + Vector3(0, 0, -3.0)
	scene.place_player(p)
	var i := 0
	for u in scene.raid.units:
		if u["team"] == "enemy":
			var q := p + Vector3(-1.6 + i * 1.5, 0, -1.8 - (i % 2) * 0.8)
			q.y = scene.ground_y(q.x, q.z)
			u["node"].global_position = q
			i += 1
	scene._cam_yaw = deg_to_rad(90.0)
	scene.cam_zoom = 0.6
	scene.snap_camera()
	await frames(26)
	scene.strike_enemy()
	await frames(3)
	await snap(dir, "rescue_fight")
	quit()
