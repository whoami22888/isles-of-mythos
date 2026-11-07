extends SceneTree
## Capture ACTUAL Godot-rendered frames of the vertical slice touch controls
## (joystick held, then after a right-half camera orbit) for exact-SHA review.
## Output directory: IOM_TOUCH_CONTROLS_OUTPUT_DIR (default user://).
const WorldScene = preload("res://gameplay/vertical_slice.tscn")

func _init() -> void:
	call_deferred("_capture")

func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)

func _drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	root.push_input(event, true)

func _frame(path: String) -> bool:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() < 640:
		push_error("Renderer did not produce an acceptable screenshot")
		return false
	if image.save_png(path) != OK:
		push_error("Could not write %s" % path)
		return false
	print("captured %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	return true

func _capture() -> void:
	var out := OS.get_environment("IOM_TOUCH_CONTROLS_OUTPUT_DIR")
	if out.is_empty():
		out = "user://"
	var world = WorldScene.instantiate()
	root.add_child(world)
	for i in range(4):
		await process_frame
	var controls = world.get_node_or_null("Interface/TouchControls")
	if controls == null:
		push_error("TouchControls not mounted")
		quit(1)
		return
	var screen: Vector2 = root.get_visible_rect().size
	var panel: Rect2 = (world.get_node("Interface/Panel") as Control).get_global_rect()
	var left := Vector2((panel.end.x + controls.joystick_split_x()) * 0.5, screen.y * 0.7)
	print("capture layout: screen %s hud %s joystick %s" % [screen, panel, left])
	var radius: float = controls.JOYSTICK_RADIUS
	_touch(0, left, true)
	await process_frame
	_drag(0, left + Vector2(radius * 0.7, -radius * 0.7))
	await process_frame
	if not controls.is_joystick_active() or controls.joystick_vector() == Vector2.ZERO:
		push_error("Joystick did not engage for capture")
		quit(1)
		return
	if not await _frame(out.path_join("touch-joystick-held.png")):
		quit(1)
		return
	var right := Vector2(screen.x * 0.78, screen.y * 0.5)
	_touch(1, right, true)
	_drag(1, right + Vector2(-90, 0))
	_drag(1, right + Vector2(-180, 0))
	_touch(1, right + Vector2(-180, 0), false)
	if is_zero_approx(world._camera_yaw):
		push_error("Camera orbit did not change yaw")
		quit(1)
		return
	if not await _frame(out.path_join("touch-camera-orbited.png")):
		quit(1)
		return
	_touch(0, left, false)
	world.queue_free()
	await process_frame
	quit(0)
