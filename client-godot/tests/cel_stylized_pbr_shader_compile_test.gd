extends SceneTree
## Infrastructure-only shader smoke test: require the actual Vulkan Mobile renderer.

const TEST_SCENE_PATH := "res://tests/cel_stylized_pbr_shader_test.tscn"
const DEFAULT_CAPTURE_PATH := "user://cel-stylized-pbr-vulkan-mobile.png"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var rendering_method := RenderingServer.get_current_rendering_method()
	var rendering_driver := RenderingServer.get_current_rendering_driver_name()
	if rendering_method != "mobile" or rendering_driver != "vulkan":
		push_error(
			"Expected Vulkan Mobile renderer, got driver=%s method=%s"
			% [rendering_driver, rendering_method]
		)
		quit(1)
		return

	var packed_scene: PackedScene = load(TEST_SCENE_PATH)
	if packed_scene == null:
		push_error("Could not load Prompt 005 shader test scene: %s" % TEST_SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate() as Node3D
	if scene == null:
		push_error("Prompt 005 shader test scene root is not Node3D")
		quit(1)
		return

	var mesh_instance := scene.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance == null:
		push_error("Prompt 005 shader test scene has no shader mesh")
		quit(1)
		return

	var shader_material := mesh_instance.material_override as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		push_error("Prompt 005 shader material is missing")
		quit(1)
		return

	root.add_child(scene)
	for frame_index in range(4):
		await process_frame
	await RenderingServer.frame_post_draw

	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() < 64 or image.get_height() < 64:
		push_error("Vulkan Mobile did not produce a usable Prompt 005 shader frame")
		scene.queue_free()
		quit(1)
		return

	var first_pixel := image.get_pixel(0, 0)
	var first_vector := Vector4(first_pixel.r, first_pixel.g, first_pixel.b, first_pixel.a)
	var sample_positions: Array[Vector2i] = [
		Vector2i(image.get_width() / 4, image.get_height() / 4),
		Vector2i(image.get_width() / 2, image.get_height() / 2),
		Vector2i(image.get_width() * 3 / 4, image.get_height() * 3 / 4),
	]
	var varied_samples := 0
	for sample_position in sample_positions:
		var sample_pixel := image.get_pixel(sample_position.x, sample_position.y)
		var sample_vector := Vector4(
			sample_pixel.r,
			sample_pixel.g,
			sample_pixel.b,
			sample_pixel.a
		)
		if sample_vector.distance_to(first_vector) > 0.03:
			varied_samples += 1

	if varied_samples < 2:
		push_error("Vulkan Mobile Prompt 005 frame is uniform or blank")
		scene.queue_free()
		quit(1)
		return

	var capture_path := OS.get_environment("IOM_SHADER_CAPTURE_PATH")
	if capture_path.is_empty():
		capture_path = DEFAULT_CAPTURE_PATH
	var save_error := image.save_png(capture_path)
	if save_error != OK:
		push_error("Could not save internal Vulkan Mobile shader frame: %d" % save_error)
		scene.queue_free()
		quit(1)
		return

	print(
		"PROMPT005_VULKAN_MOBILE_RENDER=PASS driver=%s method=%s size=%dx%d capture=%s"
		% [
			rendering_driver,
			rendering_method,
			image.get_width(),
			image.get_height(),
			capture_path,
		]
	)
	scene.queue_free()
	quit(0)
