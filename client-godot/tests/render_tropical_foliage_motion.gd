extends SceneTree
## INTERNAL ENGINE EVIDENCE: sequential 1280x720 Godot Mobile foliage frames.
## Not a cinematic-parity or physical-Android performance result.
## Captures at logical 24 FPS independent of llvmpipe frame execution time.

const FRAME_COUNT := 48
const FRAME_RATE := 24.0
const WIDTH := 1280
const HEIGHT := 720

func _init() -> void:
	call_deferred("_capture")

func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)

func _capture() -> void:
	var frame_dir := OS.get_environment("IOM_FOLIAGE_FRAMES_DIR")
	var evidence_dir := OS.get_environment("IOM_FOLIAGE_EVIDENCE_DIR")
	if frame_dir.is_empty() or evidence_dir.is_empty():
		_fail("Explicit foliage frame and evidence paths required")
		return
	if DirAccess.make_dir_recursive_absolute(frame_dir) != OK or DirAccess.make_dir_recursive_absolute(evidence_dir) != OK:
		_fail("Could not create foliage capture directories")
		return
	var packed: PackedScene = load("res://scenes/realistic_coastal_slice.tscn")
	if packed == null:
		_fail("Cannot load real integrated coastal scene")
		return
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_gameplay_view()
	scene.apply_visual_quality(2)
	# Frame actual first-party palms, stilted huts and beach; no camera pan.
	var camera: Camera3D = scene.gameplay_camera
	camera.position = Vector3(-16.0, 8.5, -8.5)
	camera.look_at(Vector3(-13.0, 2.0, 8.5), Vector3.UP)
	if not camera.current:
		_fail("Gameplay capture camera is not active")
		return
	scene.set_process(false)
	var palms := scene.get_node_or_null("TropicalBayDressing/TropicalPalmGrove") as MultiMeshInstance3D
	var grass := scene.get_node_or_null("TropicalBayDressing/TropicalGrassTufts") as MultiMeshInstance3D
	if palms == null or grass == null or palms.multimesh == null or grass.multimesh == null:
		_fail("Real batched foliage is missing")
		return
	if palms.multimesh.visible_instance_count < 24 or grass.multimesh.visible_instance_count < 30:
		_fail("Foliage is not present in the high-quality scene")
		return
	var palm_mat := palms.material_override as ShaderMaterial
	var grass_mat := grass.material_override as ShaderMaterial
	if palm_mat == null or grass_mat == null or palm_mat.shader == null or palm_mat.shader != grass_mat.shader:
		_fail("Foliage does not share the expected wind shader")
		return
	# Freeze other time-driven visuals so frame changes reflect primarily the
	# canopy. We do not create proxy foliage, substitute images or fake motion.
	var ocean := scene.get_node_or_null("ShallowToDeepWater") as MeshInstance3D
	if ocean and ocean.material_override is ShaderMaterial:
		var ocean_mat := ocean.material_override as ShaderMaterial
		ocean_mat.set_shader_parameter("deterministic_capture", true)
		ocean_mat.set_shader_parameter("capture_time_seconds", 0.0)
	var smoke := scene.get_node_or_null("TropicalBayDressing/DistantVolcano/VolcanoSmoke") as Node3D
	if smoke:
		smoke.visible = false
	var previous := PackedByteArray()
	var changed := 0
	for frame in range(FRAME_COUNT):
		var logical_time := float(frame) / FRAME_RATE
		palm_mat.set_shader_parameter("capture_time_seconds", logical_time)
		grass_mat.set_shader_parameter("capture_time_seconds", logical_time)
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels: Image = root.get_viewport().get_texture().get_image()
		if pixels == null or pixels.is_empty() or pixels.get_width() != WIDTH or pixels.get_height() != HEIGHT:
			_fail("No genuine 1280x720 engine frame %d" % frame)
			return
		if pixels.get_format() != Image.FORMAT_RGBA8:
			pixels.convert(Image.FORMAT_RGBA8)
		var bytes: PackedByteArray = pixels.get_data()
		if bytes.size() != WIDTH * HEIGHT * 4:
			_fail("Bad RGBA8 byte count at frame %d" % frame)
			return
		if frame > 0 and bytes != previous:
			changed += 1
		previous = bytes
		var frame_file := FileAccess.open(frame_dir.path_join("frame_%04d.rgba" % frame), FileAccess.WRITE)
		if frame_file == null:
			_fail("Cannot write real engine frame %d" % frame)
			return
		frame_file.store_buffer(bytes)
		frame_file.close()
		if frame == 0 or frame == 24 or frame == FRAME_COUNT - 1:
			var png_file := evidence_dir.path_join("foliage-frame-%04d.png" % frame)
			if pixels.save_png(png_file) != OK:
				_fail("Cannot save frame preview %d" % frame)
				return
		if frame % 12 == 0:
			print("FOLIAGE_CAPTURE frame=%d logical_seconds=%.4f real_rgba_bytes=%d" % [frame, logical_time, bytes.size()])
	if changed < FRAME_COUNT - 2:
		_fail("Mostly static engine render; animated foliage evidence rejected (%d changed)" % changed)
		return
	print("FOLIAGE_MOTION_ENGINE_EVIDENCE frames=%d changed=%d rate=24 source=Godot-4.7.2-Mobile" % [FRAME_COUNT, changed])
	scene.queue_free()
	quit(0)
