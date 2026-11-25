extends CanvasLayer

## Capture-only visual fixture for Prompt 004. The cyan capsule and magenta box
## are intentionally diagnostic primitives, never production art.
const Factory = preload("res://scripts/render_fallback_factory.gd")

const PANEL_WIDTH := 320.0
const PANEL_HEIGHT := 376.0
const VIEWPORT_SIZE := Vector2i(640, 640)
const MIN_DIAGNOSTIC_PIXELS := 100

var _diagnostic_viewport: SubViewport

static func resolve_source_sha(event_path: String, fallback_sha: String) -> String:
	if not event_path.is_empty() and FileAccess.file_exists(event_path):
		var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(event_path))
		if payload is Dictionary:
			var pull_request: Variant = payload.get("pull_request", {})
			if pull_request is Dictionary:
				var head: Variant = pull_request.get("head", {})
				if head is Dictionary:
					var head_sha := str(head.get("sha", ""))
					if not head_sha.is_empty():
						return head_sha
	return fallback_sha

func _ready() -> void:
	layer = 100
	var panel := PanelContainer.new()
	panel.name = "DiagnosticPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -PANEL_WIDTH - 16.0
	panel.offset_top = 16.0
	panel.offset_right = -16.0
	panel.offset_bottom = PANEL_HEIGHT
	add_child(panel)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(content)

	var label := Label.new()
	label.name = "DiagnosticLabel"
	var engine_version: Dictionary = Engine.get_version_info()
	var version_text := str(engine_version.get("string", "unknown"))
	var adapter := RenderingServer.get_video_adapter_name()
	var api_version := RenderingServer.get_video_adapter_api_version()
	var renderer_method := RenderingServer.get_current_rendering_method()
	var renderer_driver := RenderingServer.get_current_rendering_driver_name()
	var requested_method := "mobile" if not OS.get_environment("IOM_VERTICAL_SLICE_OUTPUT_DIR").is_empty() else "project"
	var source_sha := resolve_source_sha(OS.get_environment("GITHUB_EVENT_PATH"), OS.get_environment("GITHUB_SHA"))
	var short_sha := source_sha.left(12) if not source_sha.is_empty() else "unavailable"
	var renderer_text := "%s/%s" % [renderer_method, renderer_driver]
	if not api_version.is_empty():
		renderer_text += " API " + api_version
	if not adapter.is_empty():
		renderer_text += " · " + adapter
	label.text = "PROMPT 004 FALLBACKS — DIAGNOSTIC ONLY / NOT PRODUCTION ART\nGodot %s · requested %s · actual %s · SHA %s" % [
		version_text,
		requested_method,
		renderer_text,
		short_sha
	]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 11)
	content.add_child(label)

	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "ViewportContainer"
	viewport_container.custom_minimum_size = Vector2(PANEL_WIDTH - 24.0, 320.0)
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(viewport_container)

	var viewport := SubViewport.new()
	viewport.name = "DiagnosticViewport"
	viewport.size = VIEWPORT_SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport_container.add_child(viewport)
	_diagnostic_viewport = viewport

	var world := Node3D.new()
	world.name = "DiagnosticWorld"
	viewport.add_child(world)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.055, 0.09, 1.0)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)

	var camera := Camera3D.new()
	camera.name = "DiagnosticCamera"
	camera.position = Vector3(0.0, 1.25, 6.0)
	camera.fov = 40.0
	camera.current = true
	world.add_child(camera)
	# look_at() requires the camera to be inside the active viewport tree.
	camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)

	var character := Factory.get_fallback_mesh(
		"res://__prompt004_missing_character_fixture.glb",
		"character"
	)
	character.name = "MissingCharacter"
	var capsule := character.mesh as CapsuleMesh
	if capsule != null:
		capsule.height = 2.0
		capsule.radius = 0.4
	character.position = Vector3(-1.05, 0.0, 0.0)
	world.add_child(character)

	var prop := Factory.get_fallback_mesh(
		"res://__prompt004_missing_prop_fixture.glb",
		"prop"
	)
	prop.name = "MissingProp"
	var box := prop.mesh as BoxMesh
	if box != null:
		box.size = Vector3.ONE
	prop.position = Vector3(1.05, 0.5, 0.0)
	world.add_child(prop)

	var light := DirectionalLight3D.new()
	light.name = "DiagnosticLight"
	light.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	world.add_child(light)

	# Pixel readback is only meaningful in the real capture renderer. The IOM-00
	# headless dummy backend has no ViewportTexture storage; its smoke test checks
	# node/material contracts while this capture-only check validates actual pixels.
	if not OS.get_environment("IOM_VERTICAL_SLICE_OUTPUT_DIR").is_empty():
		call_deferred("_verify_rendered_fallback_pixels")


func _verify_rendered_fallback_pixels() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not is_instance_valid(_diagnostic_viewport):
		push_error("Prompt 004 fallback pixel check: diagnostic SubViewport was freed")
		get_tree().quit(1)
		return
	var viewport_texture := _diagnostic_viewport.get_texture()
	if viewport_texture == null:
		push_error("Prompt 004 fallback pixel check: SubViewport texture is unavailable")
		get_tree().quit(1)
		return
	var diagnostic_image: Image = viewport_texture.get_image()
	if diagnostic_image == null or diagnostic_image.is_empty():
		push_error("Prompt 004 fallback pixel check: SubViewport produced no rendered image")
		get_tree().quit(1)
		return
	var cyan_pixels := 0
	var magenta_pixels := 0
	for pixel_y in range(diagnostic_image.get_height()):
		for pixel_x in range(diagnostic_image.get_width()):
			var pixel := diagnostic_image.get_pixel(pixel_x, pixel_y)
			if pixel.r < 0.12 and pixel.g > 0.45 and pixel.b > 0.65:
				cyan_pixels += 1
			if pixel.r > 0.65 and pixel.g < 0.12 and pixel.b > 0.65:
				magenta_pixels += 1
	if cyan_pixels < MIN_DIAGNOSTIC_PIXELS or magenta_pixels < MIN_DIAGNOSTIC_PIXELS:
		push_error("Prompt 004 fallback pixel check failed: cyan=%d magenta=%d" % [cyan_pixels, magenta_pixels])
		get_tree().quit(1)
		return
	print("PROMPT004_RENDERED_FALLBACK_PIXELS cyan=%d magenta=%d" % [cyan_pixels, magenta_pixels])
