extends SceneTree
## Work-in-progress Godot capture of the coastal slice with Prompt 005 cel materials.
## This is not a cinematic-quality-floor admission.

const SLICE_PATH := "res://scenes/realistic_coastal_fx_slice.tscn"
const DEFAULT_CAPTURE_PATH := "user://cel-stylized-pbr-coastal-preview.png"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(SLICE_PATH)
	if packed == null:
		push_error("Could not load coastal preview scene: %s" % SLICE_PATH)
		quit(1)
		return

	var scene := packed.instantiate() as Node3D
	if scene == null:
		push_error("Coastal preview scene root is not Node3D")
		quit(1)
		return

	root.add_child(scene)
	for _frame in range(8):
		await process_frame

	var applicator := preload("res://scripts/cel_stylized_pbr_applicator.gd")
	var use_mobile := RenderingServer.get_current_rendering_method() == "mobile"
	var converted: int = applicator.apply_to_tree(scene, use_mobile)
	if converted < 1:
		push_error("Cel applicator did not convert any opaque coastal materials")
		scene.queue_free()
		quit(1)
		return

	if scene.has_method("set_cinematic_view"):
		scene.set_cinematic_view()
	if scene.has_method("frame_ship_cinematic") and scene.get("cinematic_camera") is Camera3D:
		var camera: Camera3D = scene.cinematic_camera
		scene.frame_ship_cinematic(camera, camera.global_position)

	for _frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw

	var screenshot: Image = root.get_viewport().get_texture().get_image()
	if screenshot == null or screenshot.is_empty() or screenshot.get_width() < 640 or screenshot.get_height() < 360:
		push_error("Coastal cel preview did not produce a usable frame")
		scene.queue_free()
		quit(1)
		return

	var varied := 0
	var first := screenshot.get_pixel(16, 16)
	for sample in [Vector2i(80, 80), Vector2i(screenshot.get_width() / 2, screenshot.get_height() / 2), Vector2i(screenshot.get_width() - 80, screenshot.get_height() - 80)]:
		var pixel := screenshot.get_pixel(clampi(sample.x, 0, screenshot.get_width() - 1), clampi(sample.y, 0, screenshot.get_height() - 1))
		if Vector3(pixel.r, pixel.g, pixel.b).distance_to(Vector3(first.r, first.g, first.b)) > 0.04:
			varied += 1
	if varied == 0:
		push_error("Coastal cel preview capture is a flat frame")
		scene.queue_free()
		quit(1)
		return

	var output := OS.get_environment("IOM_SHADER_VISUAL_CAPTURE_PATH")
	if output.is_empty():
		output = DEFAULT_CAPTURE_PATH
	var err := screenshot.save_png(output)
	if err != OK:
		push_error("Failed to write coastal cel preview PNG: %s" % output)
		scene.queue_free()
		quit(1)
		return

	print("Prompt 005 coastal cel preview: converted=%s path=%s size=%sx%s" % [
		converted,
		output,
		screenshot.get_width(),
		screenshot.get_height(),
	])
	scene.queue_free()
	quit(0)
