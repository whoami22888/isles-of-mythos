extends SceneTree
## Stills of the Chapter 2 systems. IOM_POSE picks one pair:
##   ui    -> sys_world_event (barrels on the tide line + context button), sys_pet_panel (+ bag)
##   fauna -> sys_boar, sys_monkey_crab (rigged CC0 models)
##   nodes -> sys_bamboo, sys_iron_seam
## IOM_SHOTS=/abs/dir (default /workspace/iom-shots/outpost_systems).

var scene: Node
var dir := ""


func _init() -> void:
	call_deferred("run")


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await frames(20)
	root.get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("shot ", name)


func look(at: Vector3, yaw_deg: float, zoom: float) -> void:
	scene._player.global_position = Vector3(at.x, scene.ground_y(at.x, at.z), at.z)
	scene._cam_yaw = deg_to_rad(yaw_deg)
	scene.cam_zoom = zoom
	scene.snap_camera()


## Ground point under a screen position (fraction of the viewport).
func ground_at(fx: float, fy: float) -> Vector3:
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var sz := root.get_viewport().get_visible_rect().size
	var o := cam.project_ray_origin(Vector2(sz.x * fx, sz.y * fy))
	var dv := cam.project_ray_normal(Vector2(sz.x * fx, sz.y * fy))
	var p := o
	for i in 400:
		p += dv * 0.1
		if p.y <= scene.ground_y(p.x, p.z):
			break
	return Vector3(p.x, 0, p.z)


func run() -> void:
	dir = OS.get_environment("IOM_SHOTS")
	if dir == "":
		dir = "/workspace/iom-shots/outpost_systems"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["user://washed_ashore.cfg", "user://outpost.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	scene = load("res://gameplay/outpost/outpost.tscn").instantiate()
	root.add_child(scene)
	await frames(5)
	scene.events.paused = true
	scene.wildlife.auto_spawn = false
	var pose := OS.get_environment("IOM_POSE")
	match pose:
		"fauna":
			look(Vector3(13.2, 0, 9.6), 192.0, 0.3)
			await frames(3)
			var b: Dictionary = scene.wildlife.spawn_kind("boar", ground_at(0.3, 0.72))
			b["state"] = "idle"
			(b["node"] as Node3D).rotation_degrees.y = 70.0
			await shot("sys_boar")
			scene.wildlife._despawn(b)
			look(Vector3(13.0, 0, 9.4), 192.0, 0.3)
			await frames(3)
			var m: Dictionary = scene.wildlife.spawn_kind("monkey", ground_at(0.28, 0.7))
			m["state"] = "idle"
			var c: Dictionary = scene.wildlife.spawn_kind("crab", ground_at(0.6, 0.62))
			c["state"] = "idle"
			(m["node"] as Node3D).rotation_degrees.y = 120.0
			(c["node"] as Node3D).rotation_degrees.y = 150.0
			await shot("sys_monkey_crab")
		"nodes":
			look(Vector3(20.8, 0, 18.6), 192.0, 0.75)
			await shot("sys_bamboo")
			look(Vector3(20.6, 0, 9.4), 12.0, 0.6)
			await shot("sys_iron_seam")
		_:
			look(Vector3(9.5, 0, 6.0), 192.0, 0.8)
			scene.events.present("sample_driftwood")
			var wp: Vector3 = scene.events.world_pos()
			look(wp + Vector3(0.6, 0, 2.6), 12.0, 0.6)
			scene._player.look_at(Vector3(wp.x, scene._player.global_position.y, wp.z), Vector3.UP)
			await shot("sys_world_event")
			scene.events.active = {}
			scene.events._clear_world()
			scene.pet_sys.add_xp(300)
			scene.state.add_item("pearl", 1)
			scene.state.add_item("hide", 3)
			scene.state.add_item("flint", 4)
			scene.pet_sys.toggle_panel()
			await shot("sys_pet_panel")
			scene.pet_sys.toggle_panel()
			scene.bag.toggle()
			await shot("sys_bag")
	quit()
