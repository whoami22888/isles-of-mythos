extends SceneTree
## Capture ACTUAL Godot-rendered frames of the playable vertical slice gameplay view on the coastal bay:
## the follow camera, the player and resource markers on the terrain, the phone HUD and touch controls.
## The session, player and chunk states below are local presentation fixtures fed through the same
## handlers the server messages use (a stub stands in for the authenticated transport so the HUD is in
## its gameplay state); no server authority is simulated. llvmpipe numbers are not phone measurements.
## Frames: collapsed gameplay HUD, the same view orbited, close views of the player avatar idle and
## mid-walk, and the objectives/crafting drawer expanded.
## Output directory: IOM_VERTICAL_SLICE_OUTPUT_DIR (default user://).
## Motion evidence: when IOM_VERTICAL_SLICE_MOTION_DIR is set, a sequential walk-then-idle clip of the
## avatar is written there as walk_%03d.png (run Godot with --fixed-fps 30 so every frame advances the
## animation by exactly 1/30 s); CI encodes it to an MP4.
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

## Sequential engine frames of the avatar walking along +X then settling to idle. Server states are
## fed every frame (a local fixture, not simulated authority) at the walk speed, and the camera follows
## the feet so the gait stays framed. Every frame is a real Godot render saved in order.
const MOTION_WALK_FRAMES := 66
const MOTION_IDLE_FRAMES := 24
const MOTION_SPEED_PER_FRAME := 0.11

func _capture_walk_motion(world: Node, camera: Camera3D, motion_dir: String) -> bool:
	DirAccess.make_dir_recursive_absolute(motion_dir)
	var x := 8.0
	world._on_player_state({"x": x, "y": 11.0, "health": 100})
	await process_frame
	var index := 0
	for frame in MOTION_WALK_FRAMES + MOTION_IDLE_FRAMES:
		if frame < MOTION_WALK_FRAMES:
			x += MOTION_SPEED_PER_FRAME
			world._on_player_state({"x": x, "y": 11.0, "health": 100})
		var feet: Vector3 = world._player - Vector3(0.0, world.PLAYER_HALF_HEIGHT, 0.0)
		camera.h_offset = 0.0
		camera.look_at_from_position(feet + Vector3(1.2, 1.9, -4.6), feet + Vector3(0.0, 0.9, 0.0))
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			push_error("Renderer did not produce a motion frame")
			return false
		if image.save_png(motion_dir.path_join("walk_%03d.png" % index)) != OK:
			push_error("Could not write motion frame %d" % index)
			return false
		index += 1
	print("captured %d sequential motion frames in %s" % [index, motion_dir])
	world._on_player_state({"x": 10.0, "y": 11.0, "health": 100})
	await process_frame
	return true
