extends SceneTree
## Gameplay-camera still of the coastal bay, plus a software-renderer cost note.
## llvmpipe frame time is NOT a Galaxy S23 measurement.

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var output := OS.get_environment("IOM_GAMEPLAY_BAY_PATH")
	if output.is_empty():
		push_error("IOM_GAMEPLAY_BAY_PATH is required")
		quit(1)
		return
	var scene: Node3D = load("res://scenes/realistic_coastal_fx_slice.tscn").instantiate()
	root.add_child(scene)
	scene.set_gameplay_view()
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var started := Time.get_ticks_usec()
	var samples := 6
	for _frame in samples:
		await RenderingServer.frame_post_draw
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0 / float(samples)
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Gameplay bay capture was empty")
		quit(1)
		return
	var directory := output.get_base_dir()
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
	if image.save_png(output) != OK:
		push_error("Could not save gameplay bay capture")
		quit(1)
		return
	var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var mesh_instances := 0
	var authored_triangles := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		mesh_instances += 1
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var indices: PackedInt32Array = mesh_instance.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX]
			authored_triangles += indices.size() / 3
	print("GAMEPLAY_BAY_CAPTURE path=%s size=%dx%d" % [output, image.get_width(), image.get_height()])
	print("GAMEPLAY_BAY_COST renderer=llvmpipe mean_frame_ms=%.1f draw_calls=%d primitives=%d mesh_instances=%d authored_triangles=%d" % [
		elapsed_ms, draw_calls, primitives, mesh_instances, authored_triangles])
	print("GAMEPLAY_BAY_NOTE software frame time is not a phone FPS measurement")
	quit(0)
