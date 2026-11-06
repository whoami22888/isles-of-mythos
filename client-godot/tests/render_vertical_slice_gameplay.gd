extends SceneTree
## Capture ACTUAL Godot-rendered frames of the playable vertical slice gameplay view on the coastal bay:
## the follow camera, the player and resource markers on the terrain, the HUD and touch controls.
## The player/chunk states below are local presentation fixtures fed through the same handlers the
## server messages use; no server authority is simulated. llvmpipe numbers are not phone measurements.
## Output directory: IOM_VERTICAL_SLICE_OUTPUT_DIR (default user://).
const WorldScene = preload("res://gameplay/vertical_slice.tscn")

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
	world._on_player_state({"x": 10.0, "y": 11.0, "health": 100, "inventory": {}})
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
	world.queue_free()
	await process_frame
	quit(0)
