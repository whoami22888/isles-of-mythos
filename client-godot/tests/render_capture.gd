extends SceneTree
## Capture an ACTUAL Godot-rendered frame for graphics review in a display-backed CI runner.

func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if not _verify_renderer():
		quit(1)
		return
	var baseline_output := OS.get_environment("IOM_SCREENSHOT_PATH")
	if baseline_output.is_empty():
		baseline_output = "user://island-preview.png"
	if not await _capture_scene("res://scenes/island_preview.tscn", "IslandCamera", baseline_output):
		quit(1)
		return

	var coastal_output := OS.get_environment("IOM_CINEMATIC_SCREENSHOT_PATH")
	if not coastal_output.is_empty():
		# The player-facing coastal evidence must exercise the integrated FX
		# scene. Capturing the base scene here silently dropped wake, bow spray
		# and the moving-vessel adapter while still producing a valid PNG.
		if not await _capture_scene("res://scenes/realistic_coastal_fx_slice.tscn", "CinematicRevealCamera", coastal_output, true):
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
	var first_rgba := Vector4(first_pixel.r, first_pixel.g, first_pixel.b, first_pixel.a)
	var varied_pixels := 0
	for sample in [Vector2i(320, 180), Vector2i(640, 360), Vector2i(960, 540)]:
		var pixel := screenshot.get_pixel(sample.x, sample.y)
		var sample_rgba := Vector4(pixel.r, pixel.g, pixel.b, pixel.a)
		if sample_rgba.distance_to(first_rgba) > 0.03:
			varied_pixels += 1
	if varied_pixels < 2:
		push_error("Renderer produced a uniform or blank capture")
		scene.queue_free()
		return false
	if cinematic and scene.has_method("rendered_sail_pixel_stats"):
		var mask_state: Array = scene.prepare_sail_pixel_mask()
		await process_frame
		await RenderingServer.frame_post_draw
		var sail_mask: Image = root.get_viewport().get_texture().get_image()
		scene.restore_sail_pixel_mask(mask_state)
		await process_frame
		await RenderingServer.frame_post_draw
		screenshot = root.get_viewport().get_texture().get_image()
		var sail_stats: Dictionary = scene.rendered_sail_pixel_stats(screenshot, sail_mask)
		if sail_stats["mask_pixels"] < 200 or sail_stats["lit_fraction"] < 0.45:
			push_error("Rendered sail pixel contract failed: %s" % sail_stats)
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

func _verify_renderer() -> bool:
	var method := RenderingServer.get_current_rendering_method()
	var driver := RenderingServer.get_current_rendering_driver_name()
	var adapter := RenderingServer.get_video_adapter_name()
	var vendor := RenderingServer.get_video_adapter_vendor()
	var api_version := RenderingServer.get_video_adapter_api_version()
	if method != "mobile" or driver != "vulkan":
		push_error("Visual capture requires Vulkan Mobile; got %s/%s" % [method, driver])
		return false
	var metadata_path := OS.get_environment("IOM_RENDERER_INFO_PATH")
	if metadata_path.is_empty():
		push_error("IOM_RENDERER_INFO_PATH is required for capture provenance")
		return false
	var metadata_file := FileAccess.open(metadata_path, FileAccess.WRITE)
	if metadata_file == null:
		push_error("Unable to write renderer metadata: %s" % metadata_path)
		return false
	var metadata := {
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"rendering_method": method,
		"rendering_driver": driver,
		"adapter_name": adapter,
		"adapter_vendor": vendor,
		"adapter_api_version": api_version,
	}
	metadata_file.store_string(JSON.stringify(metadata, "\t") + "\n")
	metadata_file.close()
	print("IOM_RENDERER_METADATA: %s" % JSON.stringify(metadata))
	return true
