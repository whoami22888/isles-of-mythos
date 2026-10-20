extends SceneTree
## Captures the dedicated sculpted terrain scene, never the original island prototype.
## Requires a display-backed Godot 4.7.2 renderer.

func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene_path := "res://scenes/sculpted_terrain_preview.tscn"
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Sculpted terrain preview scene could not be loaded")
		quit(1)
		return
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await process_frame
	var terrain: Node3D = scene.get_node_or_null("Terrain")
	var coast: MeshInstance3D = scene.get_node_or_null("Terrain/SculptedCoast")
	var camera: Camera3D = scene.get_node_or_null("IslandCamera")
	if terrain == null or coast == null or coast.mesh == null:
		push_error("Sculpted terrain mesh did not instantiate")
		quit(1)
		return
	if camera == null or not camera.current:
		push_error("Sculpted terrain preview camera is not active")
		quit(1)
		return
	var screenshot: Image = root.get_viewport().get_texture().get_image()
	if screenshot == null or screenshot.is_empty() or screenshot.get_width() < 640 or screenshot.get_height() < 360:
		push_error("Renderer did not produce a usable sculpted terrain screenshot")
		quit(1)
		return
	var output: String = OS.get_environment("IOM_SCULPTED_SCREENSHOT_PATH")
	if output.is_empty():
		output = "user://sculpted-terrain-preview.png"
	var error: Error = screenshot.save_png(output)
	if error != OK:
		push_error("Could not write sculpted terrain PNG: %d" % error)
		quit(1)
		return
	print("Sculpted terrain rendered from %s: %s (%dx%d)" % [scene_path, output, screenshot.get_width(), screenshot.get_height()])
	scene.queue_free()
	quit(0)
