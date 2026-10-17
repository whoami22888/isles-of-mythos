extends SceneTree
## Actual display-backed capture for the dedicated coastal scene.

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var packed := load("res://scenes/coastal_vertical_slice.tscn") as PackedScene
	if packed == null:
		_fail("coastal scene could not be loaded")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await process_frame
	var terrain := scene.get_node_or_null("Terrain/SculptedCoast") as MeshInstance3D
	var water := scene.get_node_or_null("Water") as MeshInstance3D
	var camera := scene.get_node_or_null("IslandCamera") as Camera3D
	if terrain == null or terrain.mesh == null or water == null or water.mesh == null:
		_fail("coastal capture scene is incomplete")
		return
	if camera == null or not camera.current:
		_fail("coastal capture camera is not active")
		return
	var image := root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() < 640 or image.get_height() < 360:
		_fail("display-backed renderer did not produce a usable coastal capture")
		return
	var output := OS.get_environment("IOM_COASTAL_SCREENSHOT_PATH")
	if output.is_empty():
		output = "user://coastal-vertical-slice.png"
	if image.save_png(output) != OK:
		_fail("could not save coastal capture")
		return
	print("Coastal vertical slice rendered from dedicated scene: %s (%dx%d)" % [output, image.get_width(), image.get_height()])
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
