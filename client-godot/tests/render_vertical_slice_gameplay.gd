extends SceneTree
## Capture ACTUAL Godot-rendered frames of the playable vertical slice gameplay view on the coastal bay:
## the follow camera, the player and resource markers on the terrain, the phone HUD and touch controls.
## The session, player and chunk states below are local presentation fixtures fed through the same
## handlers the server messages use (a stub stands in for the authenticated transport so the HUD is in
## its gameplay state); no server authority is simulated. llvmpipe numbers are not phone measurements.
## Frames: collapsed gameplay HUD, the same view orbited, close views of the player avatar idle and
## mid-walk, and the objectives/crafting drawer expanded.
## Output directory: IOM_VERTICAL_SLICE_OUTPUT_DIR (default user://).
## Motion evidence: when IOM_VERTICAL_SLICE_MOTION_DIR is set, a sequential player-walk clip also drives
## the real CameraZoomController through close-up zoom, strategic top-down zoom, return zoom and orbit.
## Frames are written as walk_%03d.png at --fixed-fps 30; CI encodes the sequence to an MP4.
const WorldScene = preload("res://gameplay/vertical_slice.tscn")

## Authenticated-session stand-in: reports a live session and records nothing.
class FixtureSession extends Node:
	func configure(_u: String, _t: String) -> void: pass
	func connect_to_server() -> void: pass
	func is_authenticated() -> bool: return true
	func request_world_chunk(_x: int, _y: int) -> String: return ""
	func request_move(_dx: float, _dy: float) -> bool: return false
	func request_gather(_id: String) -> String: return ""
	func request_craft(_id: String) -> String: return ""

func _init() -> void:
	call_deferred("_capture")

func _frame(path: String) -> bool:
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() < 640:
		push_error("Renderer did not produce an acceptable screenshot")
		return false
	if image.save_png(path) != OK:
		push_error("Could not write %s" % path)
		return false
	var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("captured %s (%dx%d) draw_calls=%d primitives=%d" % [path, image.get_width(), image.get_height(), draw_calls, primitives])
	return true

func _capture() -> void:
	var out := OS.get_environment("IOM_VERTICAL_SLICE_OUTPUT_DIR")
	if out.is_empty():
		out = "user://"
	DirAccess.make_dir_recursive_absolute(out)
	var world = WorldScene.instantiate()
	root.add_child(world)
	for _i in range(4):
		await process_frame
	if world.get_node_or_null("CoastalWorld") == null:
		push_error("Coastal world not mounted")
		quit(1)
		return
	var transport: Node = world._client
	world._client = FixtureSession.new()
	world.add_child(world._client)
	transport.queue_free()
	world._on_authenticated("fixture-player")
	if not world.is_gameplay_hud() or world.is_drawer_open():
		push_error("Authenticated session did not enter the collapsed gameplay HUD")
		quit(1)
		return
	world._on_player_state({"x": 10.0, "y": 11.0, "health": 100, "inventory": {"resource.wood": 6, "resource.stone": 3}})
	world._on_world_chunk("", {"x": 0, "y": 0, "resources": [
		{"id": "wood:fixture-1", "type": "wood", "x": 7.5, "y": 9.0},
		{"id": "stone:fixture-2", "type": "stone", "x": 13.0, "y": 9.5},
		{"id": "herb:fixture-3", "type": "herb", "x": 9.0, "y": 15.0},
		{"id": "wood:fixture-4", "type": "wood", "x": 12.0, "y": 13.5},
	]})
	if not await _frame(out.path_join("vertical-slice-gameplay.png")):
		quit(1)
		return
	# Touch-controls camera orbit (presentation only) around the same player.
	world._on_camera_drag(Vector2(-140.0, 0.0))
	if not await _frame(out.path_join("vertical-slice-gameplay-orbited.png")):
		quit(1)
		return
	world._on_camera_drag(Vector2(140.0, 0.0))
	# Closer look at the player avatar: standing idle, then mid-walk after a few server steps.
	var camera := world.get_node("Camera") as Camera3D
	var feet: Vector3 = world._player - Vector3(0.0, world.PLAYER_HALF_HEIGHT, 0.0)
	camera.h_offset = 0.0
	camera.look_at_from_position(feet + Vector3(2.4, 2.2, -4.2), feet + Vector3(0.0, 0.9, 0.0))
	if not await _frame(out.path_join("vertical-slice-player-closeup-idle.png")):
		quit(1)
		return
	for i in 4:
		world._on_player_state({"x": 10.0 + 0.3 * (i + 1), "y": 11.0, "health": 100})
		await process_frame
	feet = world._player - Vector3(0.0, world.PLAYER_HALF_HEIGHT, 0.0)
	camera.h_offset = 0.0
	camera.look_at_from_position(feet + Vector3(2.4, 2.2, -4.2), feet + Vector3(0.0, 0.9, 0.0))
	if not await _frame(out.path_join("vertical-slice-player-closeup-walk.png")):
		quit(1)
		return
	world._on_player_state({"x": 10.0, "y": 11.0, "health": 100})
	var motion_dir := OS.get_environment("IOM_VERTICAL_SLICE_MOTION_DIR")
	if not motion_dir.is_empty():
		if not await _capture_walk_motion(world, camera, motion_dir):
			quit(1)
			return
	# The objectives/crafting drawer opened from the HUD toggle.
	(world.get_node("Interface/Panel/Margin/Content/DrawerToggle") as Button).pressed.emit()
	if not world.is_drawer_open():
		push_error("Drawer toggle did not open the drawer")
		quit(1)
		return
	if not await _frame(out.path_join("vertical-slice-gameplay-drawer.png")):
		quit(1)
		return
	world.queue_free()
	await process_frame
	quit(0)

## Sequential engine frames of the avatar walking while the real camera controller performs a
## complete close-up -> strategic -> close-up transition and an orbit. The server-state fixture only
## moves the presentation avatar; the camera remains the actual Prompt 007 CameraZoomController.
const MOTION_WALK_FRAMES := 66
const MOTION_IDLE_FRAMES := 24
const MOTION_SPEED_PER_FRAME := 0.11
const CAMERA_ZOOM_IN_END := 29
const CAMERA_FAR_HOLD_END := 44
const CAMERA_ZOOM_OUT_END := 74

func _capture_walk_motion(world: Node, camera: CameraZoomController, motion_dir: String) -> bool:
	DirAccess.make_dir_recursive_absolute(motion_dir)
	var transitions: Array[bool] = []
	camera.camera_mode_changed.connect(
		func(is_top_down: bool) -> void:
			transitions.append(is_top_down)
	)
	var x := 8.0
	camera._set_zoom(0.0)
	camera.set_orbit_yaw(PI)
	camera.set_focus_point(world._camera_target() + world._camera_focus_offset)
	world._on_player_state({"x": x, "y": 11.0, "health": 100})
	await process_frame

	var first_camera_position := camera.global_position
	var previous_distance := camera.get_rendered_distance()
	var minimum_distance := previous_distance
	var maximum_distance := previous_distance
	var minimum_pitch := camera.rotation.x
	var maximum_pitch := camera.rotation.x
	var index := 0

	for frame in MOTION_WALK_FRAMES + MOTION_IDLE_FRAMES:
		if frame < MOTION_WALK_FRAMES:
			x += MOTION_SPEED_PER_FRAME
			world._on_player_state({"x": x, "y": 11.0, "health": 100})

		var zoom_fraction := 0.0
		if frame <= CAMERA_ZOOM_IN_END:
			zoom_fraction = float(frame) / float(CAMERA_ZOOM_IN_END)
		elif frame <= CAMERA_FAR_HOLD_END:
			zoom_fraction = 1.0
		elif frame <= CAMERA_ZOOM_OUT_END:
			zoom_fraction = 1.0 - float(frame - CAMERA_FAR_HOLD_END) / float(CAMERA_ZOOM_OUT_END - CAMERA_FAR_HOLD_END)
		camera._set_zoom(zoom_fraction)

		var orbit_fraction := float(frame) / float(MOTION_WALK_FRAMES + MOTION_IDLE_FRAMES - 1)
		camera.set_orbit_yaw(PI + 0.65 * orbit_fraction)
		camera.set_focus_point(world._camera_target() + world._camera_focus_offset)

		# The physics callback applies smoothed distance/pitch and terrain clearance;
		# capture only after the actual rendered frame has completed.
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			push_error("Renderer did not produce a camera-motion frame")
			return false
		if image.save_png(motion_dir.path_join("walk_%03d.png" % index)) != OK:
			push_error("Could not write camera-motion frame %d" % index)
			return false

		var rendered_distance := camera.get_rendered_distance()
		var rendered_pitch := camera.rotation.x
		minimum_distance = minf(minimum_distance, rendered_distance)
		maximum_distance = maxf(maximum_distance, rendered_distance)
		minimum_pitch = minf(minimum_pitch, rendered_pitch)
		maximum_pitch = maxf(maximum_pitch, rendered_pitch)
		previous_distance = rendered_distance
		index += 1

	var final_camera_position := camera.global_position
	if index != MOTION_WALK_FRAMES + MOTION_IDLE_FRAMES:
		push_error("Camera-motion capture produced %d frames, expected %d" % [index, MOTION_WALK_FRAMES + MOTION_IDLE_FRAMES])
		return false
	if maximum_distance < 105.0 or minimum_distance > 25.0:
		push_error("Camera-motion capture did not traverse near/far distances (min=%f max=%f)" % [minimum_distance, maximum_distance])
		return false
	if minimum_pitch > deg_to_rad(-80.0) or maximum_pitch < deg_to_rad(-50.0):
		push_error("Camera-motion capture did not traverse near/far pitches (min=%f max=%f)" % [minimum_pitch, maximum_pitch])
		return false
	if transitions != [true, false]:
		push_error("Camera-motion capture expected top-down enter/exit transitions, got %s" % [transitions])
		return false
	if first_camera_position.distance_to(final_camera_position) < 1.0:
		push_error("Camera-motion capture did not produce a visible orbit/follow transform")
		return false
	var overlay := world.get("_camera_mode_overlay") as Control
	if overlay == null or overlay.visible:
		push_error("Camera-motion capture did not return the strategic overlay to the action state")
		return false

	print(
		"PROMPT007_CAMERA_MOTION=PASS frames=%d distance=%.2f..%.2f pitch=%.2f..%.2f transitions=%s"
		% [
			index,
			minimum_distance,
			maximum_distance,
			rad_to_deg(minimum_pitch),
			rad_to_deg(maximum_pitch),
			transitions,
		]
	)
	camera._set_zoom(0.0)
	camera.set_orbit_yaw(PI)
	camera.set_focus_point(world._camera_target() + world._camera_focus_offset)
	world._on_player_state({"x": 10.0, "y": 11.0, "health": 100})
	await process_frame
	return true
