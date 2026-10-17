extends SceneTree
## Captures the dedicated coastal water preview scene with Godot's renderer.

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var packed: PackedScene = load("res://scenes/coastal_water_preview.tscn")
	if packed == null:
		push_error("Coastal water preview scene could not be loaded")
		quit(1)
		return
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var water := scene.get_node_or_null("CoastalWater") as MeshInstance3D
	var foam := scene.get_node_or_null("ShorelineFoam") as MeshInstance3D
	if water == null or foam == null or water.mesh == null or foam.mesh == null:
		push_error("Coastal water scene did not instantiate its 3D surfaces")
		quit(1)
		return
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() < 640 or image.get_height() < 360:
		push_error("Coastal water renderer did not produce a usable capture")
		quit(1)
		return
	var output := OS.get_environment("IOM_COASTAL_WATER_SCREENSHOT_PATH")
	if output.is_empty():
		output = "user://coastal-water-preview.png"
	if image.save_png(output) != OK:
		push_error("Could not write coastal water capture")
		quit(1)
		return
	print("Coastal water rendered capture: %s (%dx%d)" % [output, image.get_width(), image.get_height()])
	quit(0)
