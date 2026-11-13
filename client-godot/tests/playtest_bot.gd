extends SceneTree
## Scripted play-test bot for the washed-ashore island. Not a CI gate.
## Drives the scene through the real input path (HUD joystick touches, taps on
## world objects, HUD button presses) and logs what a player would experience.
## Run headless with --fixed-fps 30 for logic, or under xvfb for screenshots.
## IOM_BOT_LOG=/abs/log.txt  IOM_BOT_SHOTS=/abs/dir (optional, needs a renderer)
## IOM_BOT_MINUTES=10

var scene: Node
var log_lines: PackedStringArray = []
var shots_dir := ""
var t := 0.0
var touching := false
var joy_origin := Vector2(190, 560)
var foliage: Array[AABB] = []
var cam_blocked_frames := 0
var cam_inside_frames := 0
var cam_frames := 0
var steps_seen: Dictionary = {}
var shot_i := 0

func _init() -> void:
	call_deferred("run")

func say(text: String) -> void:
	var line := "[%6.1fs] %s" % [t, text]
	print(line)
	log_lines.append(line)

func g(name: String, fallback = null):
	var v = scene.get(name)
	return fallback if v == null else v

func inv() -> Dictionary:
	return (g("_inv", {}) as Dictionary).duplicate()

func wipe() -> void:
	for f in ["user://washed_ashore.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func frame() -> void:
	await process_frame
	t += 1.0 / 30.0
	_watch_camera()

func frames(n: int) -> void:
	for i in n:
		await frame()

func _watch_camera() -> void:
	var cam: Camera3D = g("_camera")
	var player: Node3D = g("_player")
	if cam == null or player == null or str(g("_cinematic", "")) != "":
		return
	cam_frames += 1
	var eye := cam.global_position
	var head := player.global_position + Vector3.UP * 1.4
	var inside := false
	var blocked := false
	for box in foliage:
		if box.has_point(eye):
			inside = true
		if box.intersects_segment(eye, head):
			blocked = true
	if inside:
		cam_inside_frames += 1
	if blocked:
		cam_blocked_frames += 1

func collect_foliage() -> void:
	var slice: Node = g("_slice")
	if slice == null:
		return
	for mmi in slice.find_children("*", "MultiMeshInstance3D", true, false):
		var n := str(mmi.name)
		if not ("Palm" in n or "Canopy" in n or "Shrub" in n or "Cover" in n or "Understory" in n or "Calathea" in n):
			continue
		var mm: MultiMesh = mmi.multimesh
		if mm == null or mm.mesh == null:
			continue
		var local := mm.mesh.get_aabb()
		for i in mm.instance_count:
			var xf: Transform3D = mmi.global_transform * mm.get_instance_transform(i)
			var box := xf * local
			if box.size.y > 0.9:
				foliage.append(box)
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var n := str(scene.get_path_to(mi)).to_lower()
		if ("tree" in n or "palm" in n or "jungle" in n or "bush" in n or "canopy" in n) and (mi as Node3D).is_visible_in_tree():
			var box: AABB = mi.global_transform * mi.get_aabb()
			if box.size.y > 0.9:
				foliage.append(box)
	say("foliage volumes tracked: %d" % foliage.size())

# --- input helpers -------------------------------------------------------
func touch(pos: Vector2, pressed: bool, index: int = 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	root.push_input(e, true)

func drag(pos: Vector2, index: int = 0) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = Vector2.ZERO
	root.push_input(e, true)

func stick(v: Vector2) -> void:
	if v.length() < 0.05:
		if touching:
			touch(joy_origin + Vector2.ZERO, false)
			touching = false
		return
	if not touching:
		touch(joy_origin, true)
		touching = true
	drag(joy_origin + v.limit_length(1.0) * 74.0)

func tap(screen: Vector2) -> void:
	touch(screen, true, 3)
	touch(screen, false, 3)

func press(button: Control) -> bool:
	if button == null or not button.is_visible_in_tree():
		return false
	if button is BaseButton:
		(button as BaseButton).emit_signal("pressed")
		return true
	return false

func hud_button(name: String) -> Control:
	var hud = g("_hud")
	if hud == null:
		return null
	var b = hud.get(name)
	return b as Control

func steer_toward(target: Vector3) -> float:
	var player: Node3D = g("_player")
	var to := target - player.global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.3:
		stick(Vector2.ZERO)
		return dist
	var dir := to.normalized()
	var yaw := float(g("_cam_yaw", 0.0))
	var local := dir.rotated(Vector3.UP, -yaw)
	stick(Vector2(local.x, local.z))
	return dist

func walk_to(target: Vector3, stop: float, max_s: float) -> bool:
	var start := t
	while t - start < max_s:
		var d := steer_toward(target)
		if d <= stop:
			stick(Vector2.ZERO)
			return true
		await frame()
	stick(Vector2.ZERO)
	return false

func screen_of(world: Vector3) -> Vector2:
	var cam: Camera3D = g("_camera")
	return cam.unproject_position(world)

func shot(tag: String) -> void:
	if shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		shot_i += 1
		var path := "%s/bot_%02d_%s.png" % [shots_dir, shot_i, tag]
		img.save_png(path)
		say("screenshot " + path)

# --- scenario ------------------------------------------------------------
func run() -> void:
	wipe()
	shots_dir = OS.get_environment("IOM_BOT_SHOTS")
	var minutes := float(OS.get_environment("IOM_BOT_MINUTES")) if OS.get_environment("IOM_BOT_MINUTES") != "" else 10.0
	scene = load("res://gameplay/ashore/washed_ashore.tscn").instantiate()
	scene.begin_authenticated_session("ws://127.0.0.1:9/ws", "bot")
	root.add_child(scene)
	await frames(3)
	var vp := root.get_viewport().get_visible_rect().size
	joy_origin = Vector2(190, vp.y - 170)
	collect_foliage()
	say("step=%s line=%s" % [g("_step"), g("_line")])
	var skipped := press(hud_button("_skip"))
	await frames(2)
	say("skip pressed=%s cinematic now='%s' line='%s'" % [skipped, g("_cinematic"), g("_line")])
	await shot("start")
	await test_tap_gather()
	await test_follow_quest(minutes * 60.0 * 0.7)
	await test_pet()
	await test_cliff()
	say("CAMERA: %d play frames, camera inside foliage %d (%.1f%%), foliage between camera and player %d (%.1f%%)" % [
		cam_frames, cam_inside_frames, 100.0 * cam_inside_frames / maxf(cam_frames, 1),
		cam_blocked_frames, 100.0 * cam_blocked_frames / maxf(cam_frames, 1)])
	say("final step=%s inventory=%s" % [g("_step"), inv()])
	var path := OS.get_environment("IOM_BOT_LOG")
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string("\n".join(log_lines) + "\n")
		f.close()
	stick(Vector2.ZERO)
	scene.queue_free()
	await process_frame
	wipe()
	quit(0)

func test_tap_gather() -> void:
	say("--- TAP-TO-GATHER on visible models")
	var nodes: Array = g("_nodes", [])
	var player: Node3D = g("_player")
	var tried := 0
	for node in nodes:
		var root3 := node.get("root") as Node3D
		if root3 == null or not root3.visible:
			continue
		var kind := str(node.get("kind", ""))
		if kind == "pile":
			continue
		var box: AABB = scene._merged_aabb(root3)
		var centre := box.position + box.size * 0.5
		var cam: Camera3D = g("_camera")
		if cam.is_position_behind(centre):
			continue
		var before := inv()
		tap(screen_of(centre))
		await frames(70)
		var after := inv()
		var delta := {}
		for k in after.keys():
			if int(after[k]) != int(before.get(k, 0)):
				delta[k] = int(after[k]) - int(before.get(k, 0))
		say("tap %s (%s), model centre %.1fm away -> inv delta %s, hint '%s'" % [
			node.get("id"), kind, scene._flat(player.global_position, root3.global_position), delta, g("_hint")])
		tried += 1
		if tried >= 6:
			break

func test_follow_quest(budget: float) -> void:
	say("--- FOLLOW THE QUEST (budget %.0fs)" % budget)
	var start := t
	var last_step := ""
	var stuck_since := t
	var acts := 0
	while t - start < budget:
		var step := str(g("_step"))
		if step != last_step:
			say("STEP -> %s  line='%s'  inv=%s" % [step, g("_line"), inv()])
			steps_seen[step] = snappedf(t, 0.1)
			last_step = step
			stuck_since = t
			await shot("step_" + step)
		if step == "epilogue":
			break
		if bool(g("_naming", false)):
			scene.on_name("Tide-Puck")
			await frames(2)
			continue
		if bool(g("_fork", false)):
			press(hud_button("_fork_tame"))
			await frames(2)
			continue
		if bool(g("_qte", false)):
			var period := 2.0
			var m := fposmod(float(g("_tame_phase", 0.0)), period) / period
			if m > 0.7 and m < 0.82:
				press(hud_button("_qte"))
			await frame()
			continue
		if str(g("_cinematic", "")) != "":
			press(hud_button("_skip"))
			await frames(2)
			continue
		if scene.has_method("bot_goal"):
			var goal: Dictionary = scene.bot_goal()
			if goal.has("press"):
				press(hud_button(str(goal["press"])))
				await frames(4)
				continue
		var target: Vector3 = scene._point_position()
		var d := steer_toward(target)
		if d < 2.6:
			stick(Vector2.ZERO)
			press(hud_button("_action"))
			acts += 1
			await frames(20)
		else:
			await frame()
		if t - stuck_since > 120.0:
			say("STUCK on step '%s' for 120s. line='%s' hint='%s' pointer=%s inv=%s tools=%s" % [step, g("_line"), g("_hint"), g("_pointer_id"), inv(), g("_tools")])
			break
	stick(Vector2.ZERO)
	say("quest run: %d action presses, steps reached %s" % [acts, steps_seen])

func test_pet() -> void:
	say("--- PET")
	var pet: Node3D = g("_pet")
	if pet == null or not bool(g("_pet_freed", false)):
		say("pet not freed; freed=%s" % g("_pet_freed"))
		return
	var player: Node3D = g("_player")
	var before := inv()
	var found_before := int(g("_pet_finds", 0))
	var dist_sum := 0.0
	var n := 0
	var start := t
	var points := [Vector3(-8, 0, 8), Vector3(4, 0, 6), Vector3(12, 0, 6), Vector3(-2, 0, 4)]
	var i := 0
	while t - start < 60.0:
		var target: Vector3 = points[i % points.size()]
		if steer_toward(target) < 1.5:
			i += 1
		await frame()
		if scene.has_method("bot_pet_tick"):
			scene.bot_pet_tick()
		dist_sum += scene._flat(pet.global_position, player.global_position)
		n += 1
	stick(Vector2.ZERO)
	var after := inv()
	say("pet: mean distance to player %.1fm over 60s; finds=%d; inv before %s after %s; stats=%s" % [
		dist_sum / maxf(n, 1), int(g("_pet_finds", 0)) - found_before, before, after, g("_pet_stats")])

func test_cliff() -> void:
	say("--- CLIFF CLIMB (walk straight at the summit for 40s)")
	var player: Node3D = g("_player")
	var summit := Vector3(-4, 0, 16)
	var best_y := -99.0
	var y0 := player.global_position.y
	var max_slope := 0.0
	var prev := player.global_position
	var start := t
	while t - start < 40.0:
		steer_toward(summit)
		await frame()
		var p := player.global_position
		var run := Vector2(p.x - prev.x, p.z - prev.z).length()
		if run > 0.01:
			max_slope = maxf(max_slope, rad_to_deg(atan2(p.y - prev.y, run)))
		prev = p
		best_y = maxf(best_y, p.y)
	stick(Vector2.ZERO)
	await shot("cliff")
	say("cliff: start y %.1f, highest y %.1f (summit ground %.1f), steepest step climbed %.0f deg, ended at %s" % [
		y0, best_y, scene._ground_y(summit.x, summit.z), max_slope, player.global_position])
