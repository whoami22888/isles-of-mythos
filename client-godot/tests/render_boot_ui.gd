extends SceneTree
## Real Godot 4.7.2 Mobile-renderer capture of the actual startup/login UI.
## Fail closed on clipped/overlapping controls, missing focus, blank frames or secrets.

const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(800, 480)]
## Controls visible in the default (player sign-in) state, in on-screen order. Email is registration-only and checked separately.
const NAMES: Array[String] = ["Title", "Subtitle", "Status", "Endpoint", "Modes", "Identifier", "Password", "Connect", "Hint"]
const TOUCH_TARGETS: Array[String] = ["Endpoint", "Identifier", "Password", "Connect", "Modes/PlayerLogin", "Modes/RegisterPlayer", "Modes/AdminLogin"]

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/boot.tscn")
	if packed == null:
		_fail("Could not load the actual boot scene")
		return
	var directory: String = OS.get_environment("IOM_BOOT_UI_OUTPUT_DIR")
	if directory.is_empty():
		directory = "user://"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		_fail("Could not create boot UI evidence directory")
		return
	for viewport_size in SIZES:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		var scene: Control = packed.instantiate()
		root.add_child(scene)
		for frame in range(3):
			await process_frame
		if not _verify_layout(scene, viewport_size):
			scene.queue_free()
			quit(1)
			return
		if not await _capture(directory, "boot-%dx%d.png" % [viewport_size.x, viewport_size.y]):
			scene.queue_free()
			quit(1)
			return
		if viewport_size == SIZES[0]:
			var connect: Button = scene.get_node("Panel/Margin/Content/Connect")
			connect.grab_focus()
			await process_frame
			if not connect.has_focus() or connect.get_theme_stylebox("focus") == null:
				_fail("Connect button must be keyboard/gamepad focusable with a focus style")
				scene.queue_free()
				return
			if not await _capture(directory, "boot-focused-1280x720.png"):
				scene.queue_free()
				quit(1)
				return
		scene.queue_free()
		await process_frame
	print("Boot UI visual/layout verification PASS: real Godot screenshots at 1280x720, 960x540 and 800x480, plus focus state")
	quit(0)


func _verify_layout(scene: Control, expected: Vector2i) -> bool:
	if root.get_visible_rect().size != Vector2(expected):
		_fail("Godot viewport does not match requested capture dimensions: expected %s, got %s" % [expected, root.get_visible_rect().size])
		return false
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(expected))
	var panel: Control = scene.get_node("Panel")
	var panel_rect: Rect2 = panel.get_global_rect()
	if not viewport_rect.encloses(panel_rect):
		_fail("Boot panel clipped outside viewport %s: %s" % [expected, panel_rect])
		return false
	var previous_bottom := -1.0
	for name in NAMES:
		var control: Control = scene.get_node("Panel/Margin/Content/" + name)
		var bounds: Rect2 = control.get_global_rect()
		if not viewport_rect.encloses(bounds) or not panel_rect.encloses(bounds):
			_fail("Boot control clipped at %s: %s=%s" % [expected, name, bounds])
			return false
		if bounds.position.y < previous_bottom - 1.0:
			_fail("Boot controls overlap at %s: %s" % [expected, name])
			return false
		if bounds.size.x < 80.0 or bounds.size.y < 12.0:
			_fail("Boot control too small at %s: %s=%s" % [expected, name, bounds])
			return false
		previous_bottom = bounds.end.y
	for name in TOUCH_TARGETS:
		var touch: Control = scene.get_node("Panel/Margin/Content/" + name)
		if touch.get_global_rect().size.y < 44.0:
			_fail("Boot interactive target below 44 px at %s: %s" % [expected, name])
			return false
	var password: LineEdit = scene.get_node("Panel/Margin/Content/Password")
	if not password.secret or not password.text.is_empty():
		_fail("Boot capture would expose an unmasked or populated password")
		return false
	var identifier: LineEdit = scene.get_node("Panel/Margin/Content/Identifier")
	if not identifier.text.is_empty():
		_fail("Boot capture would expose a populated account identifier")
		return false
	var email: LineEdit = scene.get_node("Panel/Margin/Content/Email")
	if email.visible or not email.text.is_empty():
		_fail("Registration email field must be hidden and empty in the default sign-in state")
		return false
	var title: Label = scene.get_node("Panel/Margin/Content/Title")
	if title.text != "ISLES OF MYTHOS":
		_fail("Boot screen title is incorrect")
		return false
	return true


func _capture(directory: String, name: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	var png: Image = root.get_viewport().get_texture().get_image()
	if png == null or png.is_empty() or png.get_width() < 800 or png.get_height() < 480:
		_fail("Boot renderer returned a blank or undersized capture")
		return false
	var sample := png.get_pixel(png.get_width() / 2, png.get_height() / 2)
	var background := png.get_pixel(0, 0)
	if Vector4(sample.r, sample.g, sample.b, sample.a).distance_to(Vector4(background.r, background.g, background.b, background.a)) < 0.03:
		_fail("Boot capture centre appears to be blank background")
		return false
	var path := directory.path_join(name)
	if png.save_png(path) != OK:
		_fail("Failed to save Godot boot capture: " + path)
		return false
	print("Rendered real boot UI: %s (%dx%d)" % [path, png.get_width(), png.get_height()])
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
