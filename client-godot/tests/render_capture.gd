extends SceneTree
## Capture an ACTUAL Godot-rendered frame for graphics review in a display-backed CI runner.

func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var baseline_output := OS.get_environment("IOM_SCREENSHOT_PATH")
	if baseline_output.is_empty():
		baseline_output = "user://island-preview.png"
	if not await _capture_scene("res://scenes/island_preview.tscn", "IslandCamera", baseline_output):
		quit(1)
		return

	var coastal_output := OS.get_environment("IOM_CINEMATIC_SCREENSHOT_PATH")
	if not coastal_output.is_empty():
		if not await _capture_scene("res://scenes/realistic_coastal_slice.tscn", "CinematicRevealCamera", coastal_output, true):
			quit(1)
			return
	quit(0)


func _capture_scene(scene_path: String, camera_name: String, output: String, cinematic := false) -> bool:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Could not load capture scene: %s" % scene_path)
		return false
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	if cinematic:
		scene.set_cinematic_view()
		# Frame from the imported vessel bounds before the first render fence so
		# mast and sail clipping cannot be hidden by a later camera update.
		if not scene.frame_ship_cinematic(scene.cinematic_camera, scene.cinematic_camera.global_position):
			push_error("Imported vessel bounds could not frame cinematic capture")
			scene.queue_free()
			return false
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var camera: Camera3D = scene.get_node_or_null(camera_name)
	if camera == null or not camera.current:
		push_error("No active capture camera: %s" % camera_name)
		scene.queue_free()
		return false
	var screenshot: Image = root.get_viewport().get_texture().get_image()
	if screenshot == null or screenshot.is_empty() or screenshot.get_width() < 640:
		push_error("Renderer did not produce an acceptable screenshot")
		scene.queue_free()
		return false
	var first_pixel := screenshot.get_pixel(0, 0)
	var varied_pixels := 0
	for sample in [Vector2i(320, 180), Vector2i(640, 360), Vector2i(960, 540)]:
		var pixel := screenshot.get_pixel(sample.x, sample.y)
		if abs(pixel.r - first_pixel.r) + abs(pixel.g - first_pixel.g) + abs(pixel.b - first_pixel.b) > 0.09:
			varied_pixels += 1
	if varied_pixels < 2:
		push_error("Renderer produced a uniform or blank capture")
		scene.queue_free()
		return false
	var error: Error = screenshot.save_png(output)
	if error != OK:
		push_error("Could not write rendered capture: %d" % error)
		scene.queue_free()
		return false
	print("Godot rendered capture: %s (%dx%d)" % [output, screenshot.get_width(), screenshot.get_height()])
	scene.queue_free()
	return true
