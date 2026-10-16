extends SceneTree
## Capture actual shoreline frame and verify triangulated geometry.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/island_preview.tscn")
	if packed == null:
		push_error("Unable to load island preview")
		quit(1)
		return
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await process_frame
	var coastline: MeshInstance3D = scene.get_node_or_null("CoastalShoreline")
	if coastline == null or not coastline.mesh is ArrayMesh:
		push_error("Triangulated coastline mesh not found")
		quit(1)
		return
	var vertices: int = coastline.mesh.surface_get_array_len(0)
	if vertices < 500:
		push_error("Insufficient coastline vertices: %d" % vertices)
		quit(1)
		return
	# Godot uses clockwise front faces; reject hidden/inverted or zero-area faces.
	var arrays: Array = coastline.mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for offset in range(0, positions.size(), 3):
		var edge_a := positions[offset + 1] - positions[offset]
		var edge_b := positions[offset + 2] - positions[offset]
		if edge_a.cross(edge_b).y >= -0.000001:
			push_error("Coastline contains degenerate or downward-facing triangles")
			quit(1)
			return
	for normal in normals:
		if normal.y <= 0.0:
			push_error("Coastline normals must point above the water")
			quit(1)
			return
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_viewport().get_texture().get_image()
	if frame == null or frame.is_empty() or frame.get_width() < 640:
		push_error("No actual renderer frame")
		quit(1)
		return
	var output: String = OS.get_environment("IOM_SCREENSHOT_PATH")
	if output.is_empty():
		output = "user://coastline.png"
	if frame.save_png(output) != OK:
		push_error("Could not save coastline screenshot")
		quit(1)
		return
	print("Captured actual coastline PNG: %s (%d mesh vertices)" % [output, vertices])
	scene.queue_free()
	quit(0)

