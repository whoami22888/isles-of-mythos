extends SceneTree
## Capture genuine Godot Mobile renderer evidence for a NON-ADMITTED source ship.
## The original accepted game scene and its asset manifest stay unchanged.
const WRAPPER := preload("res://scripts/sail_emblem_hd_wrapper.gd")
const COAST := preload("res://scenes/realistic_coastal_slice.tscn")
const PINNACE_PATH := "res://assets/quarantine/ship_pinnace/ship_pinnace_1k.gltf"

const WIDTH := 1280
const HEIGHT := 720
const FRAMES := 72

func _init() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _frame_image() -> Image:
	var image: Image = root.get_viewport().get_texture().get_image()
	if image != null and image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


func _write_png(path: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _frame_image()
	if image == null or image.is_empty():
		return false
	return image.save_png(path) == OK


func _run() -> void:
	var dir: String = OS.get_environment("IOM_PINNACE_OUTPUT_DIR")
	if dir.is_empty() or not dir.is_absolute_path():
		_fail("Missing absolute IOM_PINNACE_OUTPUT_DIR")
		return
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		_fail("Cannot create quarantine capture folder")
		return
	var scene: Node3D = COAST.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var old_ship: Node3D = scene.ship_focal
	if old_ship == null:
		_fail("Current coastal scene has no authoritative focal ship")
		return
	# Dynamic load prevents unrelated clean checkouts from parsing a
	# non-committed candidate as a mandatory production dependency.
	var source_scene: PackedScene = load(PINNACE_PATH) as PackedScene
	if source_scene == null:
		_fail("Quarantined Pinnace was not staged; production import remains untouched")
		return
	var replacement: Node3D = source_scene.instantiate()
	replacement.name = "HarbourShipFocalPoint"
	replacement.position = old_ship.position
	replacement.rotation_degrees = old_ship.rotation_degrees
	# Pinnace is significantly larger in authoring units. Scale it for a
	# similar cove footprint; actual capture determines framing quality.
	replacement.scale = Vector3.ONE * 0.55
	scene.add_child(replacement)
	var result: Dictionary = WRAPPER.apply(replacement, 8, 5)
	if result.has("error"):
		_fail("Pinnace HD Order Cross wrapper: " + str(result["error"]))
		return
	scene.remove_child(old_ship)
	old_ship.free()
	scene.ship_focal = replacement
	scene._ship_base_position = replacement.position
	scene._cache_ship_visual_bounds()
	if not scene._ship_bounds_ready:
		_fail("Replacement ship has no renderable bounds")
		return

	var full: Camera3D = scene.cinematic_camera
	scene.set_cinematic_view()
	if not scene.frame_ship_cinematic(full, full.global_position):
		_fail("Pinnace cinematic camera did not include imported sails")
		return
	if not await _write_png(dir.path_join("pinnace-cinematic.png")):
		_fail("Cannot capture actual Godot cinematic ship view")
		return

	var close: Camera3D = Camera3D.new()
	close.name = "PinnaceSailInspectionCamera"
	close.fov = 58.0
	scene.add_child(close)
	close.position = replacement.position + Vector3(-12.0, 13.0, -16.0)
	close.look_at(replacement.position + Vector3(0.0, 9.0, 0.0))
	close.current = true
	if not await _write_png(dir.path_join("pinnace-sail-close.png")):
		_fail("Cannot capture actual Godot sail closeup")
		return

	scene.set_gameplay_view()
	if not await _write_png(dir.path_join("pinnace-gameplay.png")):
		_fail("Cannot capture actual Godot gameplay-distance view")
		return
	close.current = false
	scene.set_cinematic_view()
	var bounds: AABB = scene.ship_visual_bounds_world()
	print("Quarantine Pinnace AABB: ", bounds)
	print("Quarantine panel layout: ", result)
	for frame in range(FRAMES):
		# Actual imported geometry moves and the real coastal shader runs on
		# every frame. This is NOT proof of a valid server sailing simulation.
		replacement.position.z = scene._ship_base_position.z - float(frame) * 0.04
		scene.frame_ship_cinematic(full, full.global_position)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = _frame_image()
		if image == null or image.get_width() != WIDTH or image.get_height() != HEIGHT:
			_fail("Unexpected renderer framebuffer size")
			return
		var file: FileAccess = FileAccess.open(dir.path_join("frame_%03d.rgba" % frame), FileAccess.WRITE)
		if file == null:
			_fail("Could not write genuine RGBA frame")
			return
		file.store_buffer(image.get_data())
		file.close()
	print("Godot Pinnace quarantine: %d actual Mobile-renderer frames" % FRAMES)
	quit(0)
