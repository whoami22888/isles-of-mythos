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
		"ghost", "built", "storm_fire", "storm_flash", "storm_threat", "dawn":
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
			if pose != "ghost":
				scene.on_build_place()
				scene._fish_cooked = 2
				scene._enter("shelter")
				scene.on_build_pick("lean_to")
				scene._ghost_pin = scene._nearest_site("lean_to", scene._player.global_position + Vector3(2.5, 0, 2.5), 6.0)
				scene._tick_ghost()
				scene.on_build_place()
				for i in 16:
					scene._tick_build(0.5)
				scene._cam_yaw += 0.35
			if pose.begins_with("storm") or pose == "dawn":
				scene._health = 5
				# Stand at the lean-to beside the fire, looking past the fire.
				var pit: Vector3 = scene._pit_position()
				# Lean-to finished, pitched 3.7 m behind the fire.
				# Flattest spot on a 3.7 m ring round the fire (the camp backs
				# onto a steep slope that reads as a bare wedge).
				var hut_at: Vector3 = pit + Vector3(3.0, 0, 2.2)
				var best_dy := 1e9
				for ai in 16:
					var ang := float(ai) / 16.0 * TAU
					var c: Vector3 = pit + Vector3(cos(ang), 0, sin(ang)) * 3.7
					var cy: float = scene._ground_y(c.x, c.z)
					var dy := absf(cy - pit.y)
					for ri in 4:
						var r := Vector3(cos(ang + ri * 1.57), 0, sin(ang + ri * 1.57)) * 1.4
						dy += absf(float(scene._ground_y(c.x + r.x, c.z + r.z)) - cy)
					if cy > float(scene._water_y) + 0.3 and dy < best_dy:
						best_dy = dy
						hut_at = Vector3(c.x, cy, c.z)
				scene._hut.global_position = hut_at
				scene._hut.look_at(Vector3(pit.x, hut_at.y, pit.z), Vector3.UP)
				scene._hut_stage = 3
				scene._building = false
				scene._show_hut(3)
				var hut: Vector3 = scene._hut.global_position
				var to_pit := Vector3(pit.x - hut.x, 0, pit.z - hut.z).normalized()
				var side := Vector3(-to_pit.z, 0, to_pit.x)
				# Castaway between shelter and fire, facing the flames; the
				# camera sits on the dark side of the fire, three-quarter on,
				# so the firelight is on the face and the lean-to is behind.
				_walk(scene, pit - to_pit * 1.1, to_pit)
				print("storm pose hut %s pit %s" % [hut, pit])
				scene._enter("storm")
				scene._cam_yaw = (scene._player as Node3D).rotation.y + PI + 0.25
				scene._storm_night.age = 12.0
				scene._storm_night._next_flash = 99.0
				if pose == "storm_threat":
					scene._storm_night.threat_sent = true
					scene._enter("dusk")
					# Beast between the castaway and the lean-to, lit by the fire behind
					# the castaway; over-the-shoulder camera (side-on put the beast on the lens).
					var pl: Vector3 = scene._player.global_position
					var bp: Vector3 = pl.lerp(hut, 0.85) + side * 0.5
					bp.y = scene._ground_y(bp.x, bp.z)
					scene._beast.global_position = bp
					(scene._player as Node3D).look_at(Vector3(bp.x, pl.y, bp.z), Vector3.UP)
					scene._cam_yaw = (scene._player as Node3D).rotation.y + 0.55
				if pose == "dawn":
					scene._step = "night"
					scene._storm_night.age = 200.0
					scene._storm_night._begin_dawn()
					scene._storm_night._dawn_k = 0.3
		"pet_point":
			_free_pet(scene)
			_walk(scene, Vector3(-10.5, 0, 6.5), Vector3(0.1, 0, 1))
			scene._step = "gather"
			scene._start_sniff()
			var goal: Vector3 = scene._pet_goal
			# Face the spot Tide-Puck is pointing at so the pet is in frame.
			var here: Vector3 = (scene._player as Node3D).global_position
			var to_goal := Vector3(goal.x - here.x, 0, goal.z - here.z)
			if to_goal.length() > 0.5:
				_walk(scene, here + to_goal * 0.3, to_goal.normalized())
			scene._pet.global_position = goal
			scene._pet.position.y = scene._ground_y(goal.x, goal.z)
		"climb", "overlook":
			_free_pet(scene)
			var pts: Array = scene._overlook._pts
			var i0 := 30 if pose == "climb" else pts.size() - 1
			var here3: Vector3 = pts[i0]
			var nxt: Vector3 = pts[mini(i0 + 2, pts.size() - 1)]
			var fwd := Vector3(nxt.x - here3.x, 0, nxt.z - here3.z)
			if fwd.length() < 0.1:
				fwd = Vector3(0, 0, -1)
			_walk(scene, here3, fwd.normalized())
			scene._step = "climb"
			scene._overlook.progress = i0
			scene._overlook.point()
			if pose == "overlook":
				scene._cinematic = "reveal"
				scene._overlook.begin_reveal()
				scene._cine_age = 7.2
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
		if pose == "storm_threat" and _i < 29:
			var bpos: Vector3 = scene._player.global_position
			var bk: Vector3 = scene._beast.global_position
			scene._beast.look_at(Vector3(bpos.x, bk.y, bpos.z), Vector3.UP)
		if pose == "storm_flash" and _i == 24:
			scene._storm_night.hold_flash = true
		if pose == "dusk" and _i < 29:
			scene._beast.global_position = scene._beast.global_position
		if pose == "overlook":
			scene._cine_age = 7.2
			scene._overlook.reveal_camera(7.2)
		elif pose == "wake":
			scene._cine_age = 1.6
		elif pose.begins_with("intro"):
			scene.snap_intro_camera()
		else:
			scene._follow_camera(1.0 / 30.0 if pose.begins_with("trees") else 10.0)
		if pose == "storm_threat":
			# Pulled back past the fire so the beast stands 3-4 m off the lens,
			# between the castaway and the lean-to, lit by the fire.
			var cam_t: Camera3D = scene._camera
			var plt: Vector3 = scene._player.global_position
			var bkt: Vector3 = scene._beast.global_position
			var dir_t := Vector3(bkt.x - plt.x, 0, bkt.z - plt.z).normalized()
			var side_t := dir_t.cross(Vector3.UP)
			cam_t.global_position = plt - dir_t * 2.0 + side_t * 0.9 + Vector3.UP * 1.9
			cam_t.look_at(bkt.lerp(plt, 0.35) + Vector3.UP * 0.8, Vector3.UP)
			cam_t.fov = 58.0
		await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Ashore capture produced an empty image")
		quit(1)
		return
	image.save_png(output)
	var cam_dbg: Camera3D = scene._camera
	var pl_dbg: Vector3 = (scene._player as Node3D).global_position
	print("Ashore camera: dist %.2f m, up %.2f m, ots %.2f, pull %.2f" % [Vector2(cam_dbg.global_position.x - pl_dbg.x, cam_dbg.global_position.z - pl_dbg.z).length(), cam_dbg.global_position.y - pl_dbg.y, float(scene._cam_ots), float(scene._cam_pull)])
	if OS.get_environment("IOM_ASHORE_PROBE") != "":
		var hd: Vector3 = pl_dbg + Vector3.UP * 1.5
		print("yaw %.2f ground at player %.2f" % [float(scene._cam_yaw), float(scene._ground_y(pl_dbg.x, pl_dbg.z))])
		for off in [0.0, 0.7, -0.7, 1.4, -1.4, 2.1, -2.1, 3.14]:
			var oe: Vector3 = scene._ots_eye(float(scene._cam_yaw) + off)
			print("  off %.2f terrain %.2f crowd %s ground_rel %.2f foliage %.2f inside %s" % [off, float(scene._terrain_block(hd, oe)), scene._slope_crowds(hd, oe), float(scene._ground_y(oe.x, oe.z)) - oe.y, float(scene._foliage_hit(hd, oe)), scene._foliage_inside(oe)])
		for gi in scene.find_children("*", "GeometryInstance3D", true, false):
			if not (gi as GeometryInstance3D).is_visible_in_tree():
				continue
			var box: AABB = (gi as GeometryInstance3D).global_transform * (gi as GeometryInstance3D).get_aabb()
			if gi is MultiMeshInstance3D:
				continue
			if box.grow(0.6).has_point(cam_dbg.global_position) and box.size.length() < 60.0:
				print("NEAR LENS: ", scene.get_path_to(gi), " ", box.size)
	if OS.get_environment("IOM_ASHORE_PROBE") != "":
		# Exact lens raycast: triangle hits from the camera through a grid of
		# screen points, against every visible mesh (multimesh instances too).
		var cpos: Vector3 = cam_dbg.global_position
		var vp := root.get_viewport().get_visible_rect().size
		var tally := {}
		for gx in 9:
			for gy in 5:
				var sp := Vector2(vp.x * (gx + 0.5) / 9.0, vp.y * (gy + 0.5) / 5.0)
				var dir := cam_dbg.project_ray_normal(sp)
				var best_t := 1e9
				var best_name := "sky"
				for gi in scene.find_children("*", "GeometryInstance3D", true, false):
					if not (gi as GeometryInstance3D).is_visible_in_tree():
						continue
					var mesh: Mesh = null
					var xforms: Array = []
					if gi is MeshInstance3D:
						mesh = (gi as MeshInstance3D).mesh
						xforms = [(gi as Node3D).global_transform]
					elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
						var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
						mesh = mm.mesh
						for ii in mm.instance_count:
							xforms.append((gi as Node3D).global_transform * mm.get_instance_transform(ii))
					if mesh == null:
						continue
					var g := gi as GeometryInstance3D
					var vr_ok := true
					for xi in xforms.size():
						var xf: Transform3D = xforms[xi]
						var dcam := cpos.distance_to(xf.origin)
						if g.visibility_range_end > 0.0 and dcam > g.visibility_range_end + g.visibility_range_end_margin:
							continue
						if g.visibility_range_begin > 0.0 and dcam < g.visibility_range_begin - g.visibility_range_begin_margin:
							continue
						var lo := xf.affine_inverse()
						var o := lo * cpos
						var e := lo * (cpos + dir * 40.0)
						if not mesh.get_aabb().grow(0.05).intersects_segment(o, e):
							continue
						var tm := mesh.generate_triangle_mesh()
						if tm == null:
							continue
						var hit: Dictionary = tm.intersect_segment(o, e)
						if hit.is_empty():
							continue
						var t := cpos.distance_to(xf * (hit["position"] as Vector3))
						if t < best_t:
							best_t = t
							best_name = "%s#%d [%s] vr=%.0f..%.0f" % [scene.get_path_to(gi), xi, mesh.resource_path.get_file(), g.visibility_range_begin, g.visibility_range_end]
				var key := best_name
				if not tally.has(key):
					tally[key] = [0, 1e9]
				tally[key][0] += 1
				tally[key][1] = minf(tally[key][1], best_t)
		print("cam ", cpos, " player ", pl_dbg)
		for k in tally:
			print("LENS RAY: %2d/45 cells, nearest %.2f m  %s" % [tally[k][0], tally[k][1], k])
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
