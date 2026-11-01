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
		# A bound ShaderMaterial alone previously passed while the actual red
		# heraldic marks were unreadable/off the cloth. Count real red pixels
		# only inside the independently rendered sail silhouette, not terrain
		# or water. This is a visibility smoke guard, not visual-quality parity.
		var emblem_pixels := 0
		for y in range(screenshot.get_height()):
			for x in range(screenshot.get_width()):
				var sail_pixel: Color = sail_mask.get_pixel(x, y)
				if sail_pixel.r < 0.75 or sail_pixel.g > 0.25 or sail_pixel.b < 0.75:
					continue
				var cloth_pixel: Color = screenshot.get_pixel(x, y)
				if cloth_pixel.r > 0.25 and cloth_pixel.r > cloth_pixel.g * 1.45 and cloth_pixel.r > cloth_pixel.b * 1.3:
					emblem_pixels += 1
		print("Godot Order Cross sail pixels: %d (sail mask: %d)" % [emblem_pixels, sail_stats["mask_pixels"]])
		if emblem_pixels < 100:
			push_error("Red Order Cross not visibly rendered on the imported sails")
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
