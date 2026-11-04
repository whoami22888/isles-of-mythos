extends SceneTree
## Render-only motion evidence: writes consecutive Godot-rendered PNG frames of
## the integrated coastal FX scene while the ocean shader time advances
## deterministically (frame_index / 24.0). Each PNG is read back from the
## active viewport after a real render pass. Nothing is synthesised.
##
## Environment:
##   IOM_MOTION_DIR  output directory for frame_NNNN.png (default user://motion)
##
## Exits 0 only when every frame was rendered, non-blank and saved.

const FRAME_COUNT := 48
const FPS := 24.0
const EXPECTED_WIDTH := 1280
const EXPECTED_HEIGHT := 720
const SCENE_PATH := "res://scenes/realistic_coastal_fx_slice.tscn"
const CAMERA_NAME := "CinematicRevealCamera"
const OCEAN_NODE := "ShallowToDeepWater"


func _init() -> void:
	call_deferred("_run")


func _fail(reason: String) -> void:
	push_error("render_motion_sequence: %s" % reason)
	quit(1)


func _run() -> void:
	var directory := OS.get_environment("IOM_MOTION_DIR")
	if directory.is_empty():
		directory = "user://motion"
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		_fail("could not create output directory: %s" % directory)
		return

	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		_fail("could not load scene: %s" % SCENE_PATH)
		return
	var scene: Node3D = packed.instantiate()
	if scene == null:
		_fail("could not instantiate scene: %s" % SCENE_PATH)
		return
	root.add_child(scene)
	if not scene.has_method("set_cinematic_view") or not scene.has_method("frame_ship_cinematic"):
		_fail("scene does not expose the cinematic camera API")
		return
	scene.set_cinematic_view()
	if not scene.frame_ship_cinematic(scene.cinematic_camera, scene.cinematic_camera.global_position):
		_fail("imported vessel bounds could not frame the cinematic camera")
		return

	var ocean := scene.get_node_or_null(OCEAN_NODE) as MeshInstance3D
	if ocean == null or not (ocean.material_override is ShaderMaterial):
		_fail("ocean node %s with a ShaderMaterial is required" % OCEAN_NODE)
		return
	var ocean_material := ocean.material_override as ShaderMaterial
	ocean_material.set_shader_parameter("deterministic_capture", true)

	var camera := scene.get_node_or_null(CAMERA_NAME) as Camera3D
	if camera == null or not camera.current:
		_fail("active capture camera %s is required" % CAMERA_NAME)
		return

	# Let the scene finish its first layout and material binding passes.
	for _warmup in range(3):
		await process_frame
	await RenderingServer.frame_post_draw

	for frame_index in range(FRAME_COUNT):
		var ocean_time := float(frame_index) / FPS
		ocean_material.set_shader_parameter("capture_time_seconds", ocean_time)
		await process_frame
		await RenderingServer.frame_post_draw

		var viewport_texture := root.get_viewport().get_texture()
		if viewport_texture == null:
			_fail("viewport texture unavailable at frame %d" % frame_index)
			return
		var pixels: Image = viewport_texture.get_image()
		if pixels == null or pixels.is_empty():
			_fail("empty render result at frame %d" % frame_index)
			return
		if pixels.get_width() != EXPECTED_WIDTH or pixels.get_height() != EXPECTED_HEIGHT:
			_fail("frame %d is %dx%d, expected %dx%d" % [
				frame_index, pixels.get_width(), pixels.get_height(), EXPECTED_WIDTH, EXPECTED_HEIGHT
			])
			return
		var basis := pixels.get_pixel(0, 0)
		var varied_samples := 0
		for sample in [Vector2i(320, 180), Vector2i(640, 360), Vector2i(960, 540), Vector2i(640, 600)]:
			var c := pixels.get_pixel(sample.x, sample.y)
			if absf(c.r - basis.r) + absf(c.g - basis.g) + absf(c.b - basis.b) > 0.03:
				varied_samples += 1
		if varied_samples < 2:
			_fail("frame %d is uniform or blank" % frame_index)
			return

		var output := "%s/frame_%04d.png" % [directory, frame_index]
		var save_error := pixels.save_png(output)
		if save_error != OK:
			_fail("could not save %s (error %d)" % [output, save_error])
			return
		print("IOM_MOTION_FRAME %04d t=%.4f %s" % [frame_index, ocean_time, output])

	print("IOM_MOTION_DONE frames=%d fps=%.1f size=%dx%d dir=%s" % [
		FRAME_COUNT, FPS, EXPECTED_WIDTH, EXPECTED_HEIGHT, directory
	])
	scene.queue_free()
	quit(0)
