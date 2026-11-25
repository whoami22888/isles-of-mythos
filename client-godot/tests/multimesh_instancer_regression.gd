extends RefCounted
## Structural batching checks plus a rendered draw-call assertion when a GPU renderer is available.
## Headless CI has no renderer; the physical Android draw-call measurement remains a separate gate.

const InstancerScript := preload("res://scripts/multimesh_instancer.gd")


static func run(tree: SceneTree, check: Callable) -> void:
	var scene := load("res://tests/multimesh_instancer_test.tscn").instantiate() as MultiMeshInstancerTestScene
	tree.root.add_child(scene)
	await tree.process_frame

	var instancer := scene.instancer
	check.call(instancer != null, "MultiMesh test scene must create its instancer")
	if instancer == null:
		scene.queue_free()
		await tree.process_frame
		return

	var draw_calls_before := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	check.call(scene.populate(512), "Test scene must populate 512 transforms and colours")
	await tree.process_frame
	await tree.process_frame

	var multi := instancer.multimesh
	check.call(multi != null, "Instancer must own a MultiMesh resource")
	if multi != null:
		check.call(multi.instance_count == 512, "MultiMesh must allocate 512 instances")
		check.call(multi.visible_instance_count == 512, "All 512 instances must be visible")
		check.call(multi.use_colors, "MultiMesh must enable per-instance colours")
		check.call(multi.mesh != null and multi.mesh.get_surface_count() == 1, "Batch must contain exactly one mesh surface")
		check.call(instancer.get_expected_draw_calls() == 1, "One single-surface batch must expect one draw call per render pass")

		var buffer: PackedFloat32Array = multi.buffer
		check.call(buffer.size() == 512 * InstancerScript.FLOATS_PER_INSTANCE, "MultiMesh buffer must contain 16 floats per 3D instance")
		if buffer.size() == 512 * InstancerScript.FLOATS_PER_INSTANCE:
			var first_buffer_color := Color(buffer[12], buffer[13], buffer[14], buffer[15])
			var last_offset := 511 * InstancerScript.FLOATS_PER_INSTANCE + 12
			var last_buffer_color := Color(buffer[last_offset], buffer[last_offset + 1], buffer[last_offset + 2], buffer[last_offset + 3])
			check.call(_colors_differ(first_buffer_color, last_buffer_color), "Underlying MultiMesh buffer must contain distinct per-instance colours")

		var adapter_name := RenderingServer.get_video_adapter_name()
		if adapter_name.is_empty():
			# Godot 4.7.2's Dummy RenderingServer returns Color() for get_instance_color().
			# The raw buffer assertion above remains active in headless CI.
			print("INSTANCE_COLOR_GETTER_NOT_MEASURED: dummy headless renderer returns Color()")
		else:
			var first_color := multi.get_instance_color(0)
			var last_color := multi.get_instance_color(511)
			check.call(_colors_differ(first_color, last_color), "Per-instance colours must vary without extra materials")

		var last_transform := multi.get_instance_transform(511)
		check.call(instancer.custom_aabb.has_point(last_transform.origin), "Custom AABB must include the final instance for culling")

		var draw_calls_after := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		var rendering_method := RenderingServer.get_current_rendering_method()
		print("MULTIMESH_DRAW_CALL_DIAGNOSTIC adapter=%s method=%s before=%d after=%d delta=%d" % [adapter_name, rendering_method, draw_calls_before, draw_calls_after, draw_calls_after - draw_calls_before])
		if adapter_name.is_empty():
			print("DRAW_CALL_COUNT_NOT_MEASURED: headless renderer; expected one draw call per single-surface batch")
		else:
			check.call(draw_calls_after - draw_calls_before == 1, "Rendered 512-instance single-surface batch must add exactly one draw call")

		var invalid_colors: Array[Color] = [Color.RED]
		check.call(not instancer.set_instances([], invalid_colors), "Mismatched colour count must be rejected")
		check.call(multi.instance_count == 512, "Rejected input must preserve the previous valid batch")

	var multi_surface_mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	multi_surface_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	multi_surface_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var rejected_instancer := InstancerScript.new()
	check.call(not rejected_instancer.configure(multi_surface_mesh), "Multi-surface meshes must be split into separate batches")
	rejected_instancer.free()

	scene.queue_free()
	await tree.process_frame


static func _colors_differ(left: Color, right: Color) -> bool:
	return absf(left.r - right.r) > 0.001 or absf(left.g - right.g) > 0.001 or absf(left.b - right.b) > 0.001
