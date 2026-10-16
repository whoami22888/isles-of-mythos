extends SceneTree
## Capture an ACTUAL Godot-rendered frame for graphics review in a display-backed CI runner.

func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene_path := OS.get_environment("IOM_CAPTURE_SCENE")
	if scene_path.is_empty():
		scene_path = "res://scenes/island_preview.tscn"
	if scene_path not in ["res://scenes/island_preview.tscn", "res://scenes/coastal_preview.tscn"]:
		push_error("Unsupported visual evidence scene")
		quit(1)
		return
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Preview scene could not be loaded: %s" % scene_path)
		quit(1)
		return
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var camera := root.get_viewport().get_camera_3d()
	if camera == null or not camera.current:
		push_error("No active island preview camera")
		quit(1)
		return
	if scene_path == "res://scenes/coastal_preview.tscn":
		var props := scene.get_node_or_null("CoastalProps")
		if props == null or props.get_child_count() != 9:
			push_error("Coastal capture is missing six rocks and three palms")
			quit(1)
			return
	var screenshot: Image = root.get_viewport().get_texture().get_image()
	if screenshot == null or screenshot.is_empty() or screenshot.get_width() < 640:
		push_error("Renderer did not produce an acceptable screenshot")
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
	print("Godot rendered reference capture: %s scene=%s (%dx%d)" % [output, scene_path, screenshot.get_width(), screenshot.get_height()])
	scene.queue_free()
	quit(0)
