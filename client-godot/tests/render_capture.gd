extends SceneTree
## Engine-rendered beach material evidence; never a synthetic screenshot.

func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed: PackedScene = load("res://scenes/island_preview.tscn")
	if packed == null:
		push_error("Island scene failed to load")
		quit(1)
		return
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await process_frame
	var beach: MeshInstance3D = null
	for child in scene.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh:
			if child.mesh.top_radius > 8.5:
				beach = child
				break
	if beach == null or beach.material_override == null:
		push_error("Beach material was not applied")
		quit(1)
		return
	var material: StandardMaterial3D = beach.material_override as StandardMaterial3D
	if material == null or material.albedo_texture == null:
		push_error("Verified beach texture was not imported into material")
		quit(1)
		return
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() < 640:
		push_error("No renderable image")
		quit(1)
		return
	var output: String = OS.get_environment("IOM_SCREENSHOT_PATH")
	if output.is_empty():
		output = "user://beach-material.png"
	var error: Error = image.save_png(output)
	if error != OK:
		push_error("PNG output failed: %d" % error)
		quit(1)
		return
	print("Rendered verified beach texture: %s" % output)
	scene.queue_free()
	quit(0)
