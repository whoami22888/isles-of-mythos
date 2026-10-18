extends SceneTree
## Capture an ACTUAL Godot-rendered frame for graphics review in a display-backed CI runner.

func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed: PackedScene = load("res://scenes/realistic_coastal_slice.tscn")
	if packed == null:
		push_error("Island preview scene could not be loaded")
		quit(1)
		return
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	if OS.get_environment("IOM_CAMERA_MODE") == "cinematic":
		scene.set_cinematic_view()
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var camera_name := "CinematicRevealCamera" if OS.get_environment("IOM_CAMERA_MODE") == "cinematic" else "GameplayCamera"
	var camera: Camera3D = scene.get_node_or_null(camera_name)
	if camera == null or not camera.current:
		push_error("No active realistic coastal camera: %s" % camera_name)
		quit(1)
		return
	var screenshot: Image = root.get_viewport().get_texture().get_image()
	if screenshot == null or screenshot.is_empty() or screenshot.get_width() < 640:
		push_error("Renderer did not produce an acceptable screenshot")
		quit(1)
		return
	var first_pixel := screenshot.get_pixel(0, 0)
	var varied_pixels := 0
	for sample in [Vector2i(320, 180), Vector2i(640, 360), Vector2i(960, 540)]:
		var pixel := screenshot.get_pixel(sample.x, sample.y)
		if abs(pixel.r - first_pixel.r) + abs(pixel.g - first_pixel.g) + abs(pixel.b - first_pixel.b) > 0.09:
			varied_pixels += 1
	if varied_pixels < 2:
		push_error("Renderer produced a uniform or blank capture")
		quit(1)
		return
	var output: String = OS.get_environment("IOM_SCREENSHOT_PATH")
	if output.is_empty():
		output = "user://island-preview.png"
	var error: Error = screenshot.save_png(output)
	if error != OK:
		push_error("Could not write rendered PNG: %d" % error)
		quit(1)
		return
	print("Godot rendered reference capture: %s (%dx%d)" % [output, screenshot.get_width(), screenshot.get_height()])
	var cinematic_output := OS.get_environment("IOM_CINEMATIC_SCREENSHOT_PATH")
	if not cinematic_output.is_empty():
		scene.set_cinematic_view()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var cinematic_image: Image = root.get_viewport().get_texture().get_image()
		if cinematic_image == null or cinematic_image.is_empty() or cinematic_image.save_png(cinematic_output) != OK:
			push_error("Could not write cinematic capture")
			quit(1)
			return
		print("Godot rendered cinematic capture: %s (%dx%d)" % [cinematic_output, cinematic_image.get_width(), cinematic_image.get_height()])
	scene.queue_free()
	quit(0)
