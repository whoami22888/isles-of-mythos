extends SceneTree
## Regression: the cinematic reveal camera must stay above the sea, inside the
## water plane, and be IDENTICAL between runtime playback and the capture
## harness at matching timestamps, for the full 4 s / 96 frames, with the
## vessel moving exactly as in tests/render_coastal_fx_sequence.gd.
##
## Root cause this pins (PR #216): _safe_cinematic_position() scaled the raw
## waypoint offset outward from the ship's (tall) rigging centre. A waypoint
## below that centre therefore pushed the camera further DOWN as the framing
## radius grew; once the ship drifted the camera crossed the back-face-culled
## ocean surface (y ~ -1.35 at frame 71) and exposed the seabed mesh edge.

const SCENE_PATH := "res://scenes/realistic_coastal_fx_slice.tscn"
const FRAMES := 96
const STEP := 1.0 / 24.0
const POSE_EPSILON := 0.001

var _ok := true


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		push_error("FAIL " + label)
		_ok = false


func _spawn() -> Node3D:
	# One SubViewport per instance: only one Camera3D can be `current` per
	# viewport, so shared-viewport instances would steal each other's camera.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 36)
	root.add_child(viewport)
	var scene: Node3D = (load(SCENE_PATH) as PackedScene).instantiate()
	viewport.add_child(scene)
	await process_frame
	await process_frame
	var integration := scene.get_node_or_null("CoastalShipEffects")
	if integration == null or not integration.components_ready():
		_check(false, "scene exposes the real ship + FX components")
		return null
	# Deterministic: nothing may advance from wall-clock time.
	scene.set_process(false)
	# _process() bobs the ship from the wall clock; the setup frames above let
	# each instance freeze at a different phase. Pin the base height so poses
	# are a pure function of simulated time.
	scene.ship_focal.position.y = scene._ship_base_position.y
	scene._cache_ship_visual_bounds()
	integration.set_process(false)
	integration.wake.set_process(false)
	integration.bow_spray.set_process(false)
	integration.start_visual_demo()
	return scene


## The pre-fix algorithm, kept ONLY as a negative fixture so this test proves
## it would have failed on the old code.
func _legacy_position(scene: Node3D, desired: Vector3) -> Vector3:
	var bounds: AABB = scene.ship_visual_bounds_world()
	var centre := bounds.get_center()
	var away := (desired - centre).normalized()
	var distance := maxf(0.5, desired.distance_to(centre))
	var safe_angle := deg_to_rad(scene.cinematic_camera.fov * 0.45)
	var aim_offset := centre.distance_to(centre.lerp(scene.CINEMATIC_COAST_POINT, scene.CINEMATIC_COAST_BIAS))
	var needed := (bounds.size.length() * 0.5 + aim_offset) / maxf(0.05, sin(safe_angle))
	return centre + away * maxf(distance, needed)


func _run() -> void:
	var runtime_scene: Node3D = await _spawn()
	var capture_scene: Node3D = await _spawn()
	var legacy_scene: Node3D = await _spawn()
	if runtime_scene == null or capture_scene == null or legacy_scene == null:
		quit(1)
		return

	runtime_scene.play_cinematic()
	capture_scene.set_cinematic_view()
	legacy_scene.set_cinematic_view()
	_check(runtime_scene._cinematic_active and runtime_scene.cinematic_camera.current,
		"runtime reveal is active on the cinematic camera")

	var min_clearance := INF
	var min_margin := INF
	var worst_divergence := 0.0
	var maximum_turn_radians := 0.0
	var previous_forward := Vector3.ZERO
	var all_ship_bounds_inside_frame := true
	var legacy_unsealed := 0
	var legacy_min_y := INF
	var all_sealed := true
	var still_playing_before_end := true
	var wide_ship_screen_fraction := Vector2.ZERO
	var early_approach_ship_screen_fraction := Vector2.ZERO
	var late_approach_ship_screen_fraction := Vector2.ZERO
	var detail_ship_screen_fraction := Vector2.ZERO
	var shot_a_fov := 0.0
	for frame in range(FRAMES):
		var t := float(frame) / scene_fps(runtime_scene)
		for s in [runtime_scene, capture_scene, legacy_scene]:
			s.get_node("CoastalShipEffects").advance_visual_demo(STEP)
		# Runtime path: advance simulated time exactly as _process() does.
		if frame > 0:
			var playing: bool = runtime_scene.advance_cinematic(STEP)
			if frame < FRAMES - 1 and not playing:
				still_playing_before_end = false
		else:
			runtime_scene.apply_cinematic_time(runtime_scene.cinematic_camera, 0.0)
		# Capture path: explicit timestamp through the shared function.
		capture_scene.apply_cinematic_time(capture_scene.cinematic_camera, t)
		var runtime_pos: Vector3 = runtime_scene.cinematic_camera.global_position
		var capture_pos: Vector3 = capture_scene.cinematic_camera.global_position
		worst_divergence = maxf(worst_divergence, runtime_pos.distance_to(capture_pos))
		var forward_delta: float = (-runtime_scene.cinematic_camera.global_transform.basis.z).distance_to(
			-capture_scene.cinematic_camera.global_transform.basis.z)
		worst_divergence = maxf(worst_divergence, forward_delta)
		var forward: Vector3 = -capture_scene.cinematic_camera.global_transform.basis.z
		if frame > 0:
			maximum_turn_radians = maxf(maximum_turn_radians,
				acos(clampf(previous_forward.dot(forward), -1.0, 1.0)))
		previous_forward = forward
		var pose: Dictionary = capture_scene.evaluate_cinematic_pose(capture_pos)
		all_sealed = all_sealed and pose["sealed"]
		# Match the renderer capture's 36 px safe edge even when the shot's
		# occupancy solver spends its full 2% margin to grow the visible ship.
		all_ship_bounds_inside_frame = all_ship_bounds_inside_frame and _ship_aabb_inside_frame(
			capture_scene, maxf(capture_scene.cinematic_margin_at(float(frame) / FRAMES), 0.05), frame)
		min_clearance = minf(min_clearance, pose["clearance"])
		min_margin = minf(min_margin, pose["water_margin"])
		var ship_screen_fraction := _projected_ship_screen_fraction(capture_scene)
		if frame == 0:
			wide_ship_screen_fraction = ship_screen_fraction
			shot_a_fov = capture_scene.cinematic_camera.fov
		elif frame == FRAMES / 4:
			early_approach_ship_screen_fraction = ship_screen_fraction
		elif frame == FRAMES / 2:
			late_approach_ship_screen_fraction = ship_screen_fraction
		elif frame == 71:
			detail_ship_screen_fraction = ship_screen_fraction
		# Legacy fixture: same raw waypoint through the pre-fix algorithm.
		var legacy_pos := _legacy_position(legacy_scene, legacy_scene.cinematic_raw_position_at(t))
		legacy_min_y = minf(legacy_min_y, legacy_pos.y)
		if not legacy_scene.evaluate_cinematic_pose(legacy_pos)["sealed"]:
			legacy_unsealed += 1

	print("IOM_CAMERA_PATH frames=%d min_clearance=%.2f min_water_margin=%.1f max_runtime_capture_divergence=%.6f max_turn_degrees=%.3f legacy_min_y=%.2f legacy_unsealed_frames=%d" % [
		FRAMES, min_clearance, min_margin, worst_divergence, rad_to_deg(maximum_turn_radians), legacy_min_y, legacy_unsealed])
	_check(all_sealed, "every one of %d frames is sealed above the ocean" % FRAMES)
	_check(min_clearance >= runtime_scene.CINEMATIC_MIN_CLEARANCE - POSE_EPSILON,
		"camera never closer than %.1f m to the sea surface" % runtime_scene.CINEMATIC_MIN_CLEARANCE)
	_check(worst_divergence <= POSE_EPSILON,
		"runtime playback and capture poses match at every timestamp")
	_check(all_ship_bounds_inside_frame,
		"all ship AABB corners stay within the frame at every cinematic timestamp")
	_check(maximum_turn_radians < deg_to_rad(8.0),
		"camera and ocean horizon orientation remain continuous between frames")
	print("IOM_SHIP_SCREEN_FRACTION wide=%.3f/%.3f approach24=%.3f/%.3f approach48=%.3f/%.3f detail71=%.3f/%.3f" % [
		wide_ship_screen_fraction.x, wide_ship_screen_fraction.y,
		early_approach_ship_screen_fraction.x, early_approach_ship_screen_fraction.y,
		late_approach_ship_screen_fraction.x, late_approach_ship_screen_fraction.y,
		detail_ship_screen_fraction.x, detail_ship_screen_fraction.y])
	_check(wide_ship_screen_fraction.y >= 0.18,
		"wide establishing shot gives the ship readable screen height")
	_check(is_equal_approx(shot_a_fov, runtime_scene.CINEMATIC_FOV_WIDE),
		"Shot A uses the owner's 58 degree field of view")
	_check(early_approach_ship_screen_fraction.y > wide_ship_screen_fraction.y,
		"approach shot grows the ship on screen")
	_check(late_approach_ship_screen_fraction.y >= early_approach_ship_screen_fraction.y,
		"later approach continues or holds the ship's screen-space growth")
	_check(detail_ship_screen_fraction.y > late_approach_ship_screen_fraction.y,
		"close detail shot continues the ship's screen-space growth")
	_check(detail_ship_screen_fraction.y >= 0.32,
		"close detail shot reserves at least 32% of screen height for the ship")
	_check(is_equal_approx(capture_scene.cinematic_coast_bias_at(0.5), capture_scene.CINEMATIC_COAST_BIAS)
		and is_zero_approx(capture_scene.cinematic_coast_bias_at(1.0)),
		"detail beat recentres the camera on the ship after the harbour approach")
	_check(still_playing_before_end, "runtime reveal keeps playing until its 4 s duration")
	runtime_scene.advance_cinematic(STEP * 2.0)
	_check(not runtime_scene._cinematic_active and runtime_scene.gameplay_camera.current,
		"reveal hands back to the gameplay camera when it ends")
	# Negative fixture: the pre-fix algorithm MUST have been caught.
	_check(legacy_unsealed > 0 and legacy_min_y < runtime_scene.WATER_Y,
		"negative fixture: the pre-fix algorithm dips below the sea (%d unsealed frames)" % legacy_unsealed)

	# Pure-validator negatives.
	_check(not runtime_scene.evaluate_cinematic_pose(Vector3(-16.2, -1.35, -41.6))["sealed"],
		"submerged pose is rejected")
	_check(not runtime_scene.evaluate_cinematic_pose(Vector3(0.0, 6.0, 1100.0))["sealed"],
		"pose near/outside the water plane edge is rejected")
	_check(runtime_scene.evaluate_cinematic_pose(Vector3(0.0, 6.0, -30.0))["sealed"],
		"a high pose inside the water plane is accepted")

	# Clearance floor holds even when the vessel itself sits low.
	capture_scene.ship_focal.position.y = -9.0
	capture_scene._cache_ship_visual_bounds()
	var low: Vector3 = capture_scene._safe_cinematic_position(capture_scene.cinematic_camera, Vector3(-7.0, -5.0, -17.0))
	_check(low.y >= capture_scene.WATER_Y + capture_scene.CINEMATIC_MIN_CLEARANCE - POSE_EPSILON,
		"clearance floor holds for a low ship and a below-sea waypoint (y=%.2f)" % low.y)
	for s in [runtime_scene, capture_scene, legacy_scene]:
		s.get_parent().free()
	await process_frame
	await process_frame

	quit(0 if _ok else 1)


func scene_fps(scene: Node3D) -> float:
	return scene.CINEMATIC_FPS


func _projected_ship_screen_fraction(scene: Node3D) -> Vector2:
	var camera: Camera3D = scene.cinematic_camera
	var bounds: AABB = scene.ship_visual_bounds_world()
	var screen_min := Vector2(INF, INF)
	var screen_max := Vector2(-INF, -INF)
	for corner in range(8):
		var world_point := bounds.position + Vector3(
			bounds.size.x if corner & 1 else 0.0,
			bounds.size.y if corner & 2 else 0.0,
			bounds.size.z if corner & 4 else 0.0
		)
		var screen_point: Vector2 = camera.unproject_position(world_point)
		screen_min = screen_min.min(screen_point)
		screen_max = screen_max.max(screen_point)
	var viewport_size := camera.get_viewport().get_visible_rect().size
	return Vector2((screen_max.x - screen_min.x) / viewport_size.x,
		(screen_max.y - screen_min.y) / viewport_size.y)


func _ship_aabb_inside_frame(scene: Node3D, margin: float, frame: int) -> bool:
	var camera: Camera3D = scene.cinematic_camera
	var bounds: AABB = scene.ship_visual_bounds_world()
	var viewport_size := camera.get_viewport().get_visible_rect().size
	for corner in range(8):
		var point := bounds.position + Vector3(
			bounds.size.x if corner & 1 else 0.0,
			bounds.size.y if corner & 2 else 0.0,
			bounds.size.z if corner & 4 else 0.0
		)
		if camera.is_position_behind(point):
			return false
		var pixel: Vector2 = camera.unproject_position(point)
		if pixel.x <= viewport_size.x * margin or pixel.x >= viewport_size.x * (1.0 - margin):
			print("IOM_FRAME_EDGE frame=%d corner=%d axis=x pixel=%.3f margin=%.3f viewport=%.0f" % [frame, corner, pixel.x, margin, viewport_size.x])
			return false
		if pixel.y <= viewport_size.y * margin or pixel.y >= viewport_size.y * (1.0 - margin):
			print("IOM_FRAME_EDGE frame=%d corner=%d axis=y pixel=%.3f margin=%.3f viewport=%.0f" % [frame, corner, pixel.y, margin, viewport_size.y])
			return false
	return true
