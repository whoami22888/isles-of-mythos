extends SceneTree
## Run with: godot --headless --path client-godot --script res://tests/camera_zoom_controller_regression.gd

const Controller = preload("res://scripts/camera_zoom_controller.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var camera = Controller.new()
	camera.terrain_collision_mask = 1 # _ready must not query a locked physics space
	root.add_child(camera)
	await process_frame
	# Manual interpolation calls below are not physics callbacks; keep raycasts off.
	# The raised-terrain test at the end re-enables the mask on real physics ticks.
	camera.terrain_collision_mask = 0
	assert(is_equal_approx(camera.global_position.distance_to(camera.focus_point), 10.0), "Near camera distance")
	assert(is_equal_approx(rad_to_deg(camera.rotation.x), -45.0), "Near camera pitch")
	var transitions: Array[bool] = []
	camera.camera_mode_changed.connect(func(top_down: bool) -> void: transitions.append(top_down))
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for i in range(20):
		camera._unhandled_input(wheel)
	assert(transitions == [true], "Top-down transition must emit exactly once")
	for i in range(180):
		camera._physics_process(1.0 / 60.0)
	assert(absf(camera.global_position.distance_to(camera.focus_point) - 120.0) < 0.05, "Far camera distance")
	assert(absf(rad_to_deg(camera.rotation.x) + 85.0) < 0.05, "Far camera pitch")
	var far_pan_origin: Vector3 = camera.focus_point
	camera._pan(Vector2(100.0, 0.0))
	var far_pan_metres: float = camera.focus_point.distance_to(far_pan_origin)
	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	if viewport_size.x < 1.0 or viewport_size.y < 1.0:
		viewport_size = Vector2(1280.0, 720.0)
	var half_fov: float = deg_to_rad(camera.fov) * 0.5
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		half_fov = atan(tan(half_fov) * viewport_size.y / viewport_size.x)
	var expected_pan: float = 100.0 * 2.0 * camera._rendered_distance * tan(half_fov) / viewport_size.y
	assert(absf(far_pan_metres - expected_pan) < 0.01, "Pan must scale by viewport and field of view")
	var touch_a: InputEventScreenTouch = InputEventScreenTouch.new()
	touch_a.index = 0
	touch_a.pressed = true
	touch_a.position = Vector2(100, 100)
	camera._unhandled_input(touch_a)
	var touch_b: InputEventScreenTouch = InputEventScreenTouch.new()
	touch_b.index = 1
	touch_b.pressed = true
	touch_b.position = Vector2(200, 100)
	camera._unhandled_input(touch_b)
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(240, 100)
	drag.relative = Vector2(40, 0)
	camera._unhandled_input(drag)
	assert(camera._zoom_fraction < 1.0, "Pinch-in must zoom towards action view")
	touch_a.pressed = false
	touch_b.pressed = false
	camera._unhandled_input(touch_a)
	camera._unhandled_input(touch_b)
	# Fractional wheel events must sum to the same zoom as one whole wheel step.
	camera._set_zoom(0.5)
	wheel.factor = 0.1
	for i in range(10):
		camera._unhandled_input(wheel)
	assert(absf(camera._zoom_fraction - 0.56) < 0.001, "Fractional wheel amount")
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	for i in range(10):
		camera._unhandled_input(wheel)
	assert(absf(camera._zoom_fraction - 0.5) < 0.001, "Symmetric wheel amount")
	wheel.factor = 0.0
	camera._unhandled_input(wheel)
	assert(absf(camera._zoom_fraction - 0.44) < 0.001, "Legacy zero wheel factor")

	# Parallel finger movement at either clamped zoom limit must not zoom.
	camera._set_zoom(0.0)
	touch_a.pressed = true
	touch_b.pressed = true
	touch_a.position = Vector2(100, 100)
	touch_b.position = Vector2(200, 100)
	camera._unhandled_input(touch_a)
	camera._unhandled_input(touch_b)
	drag.index = 1
	drag.position = Vector2(240, 100)
	camera._unhandled_input(drag)
	drag.index = 0
	drag.position = Vector2(140, 100)
	camera._unhandled_input(drag)
	assert(absf(camera._zoom_fraction) < 0.001, "Parallel near-limit pan must not zoom")
	touch_a.pressed = false
	touch_b.pressed = false
	camera._unhandled_input(touch_a)
	camera._unhandled_input(touch_b)

	camera._set_zoom(1.0)
	touch_a.pressed = true
	touch_b.pressed = true
	touch_a.position = Vector2(100, 100)
	touch_b.position = Vector2(200, 100)
	camera._unhandled_input(touch_a)
	camera._unhandled_input(touch_b)
	drag.index = 1
	drag.position = Vector2(160, 100)
	camera._unhandled_input(drag)
	drag.index = 0
	drag.position = Vector2(60, 100)
	camera._unhandled_input(drag)
	assert(absf(camera._zoom_fraction - 1.0) < 0.001, "Parallel far-limit pan must not zoom")

	# A lost-focus gesture cannot leave ghost fingers behind.
	camera._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert(camera._touches.is_empty(), "Focus loss clears touches")
	assert(camera._pinch_start_distance == 0.0, "Focus loss clears pinch baseline")
	var zoom_before_new_touch: float = camera._zoom_fraction
	touch_a.position = Vector2(120, 100)
	camera._unhandled_input(touch_a)
	drag.index = 0
	drag.position = Vector2(145, 100)
	camera._unhandled_input(drag)
	assert(is_equal_approx(camera._zoom_fraction, zoom_before_new_touch), "One new finger does not inherit stale pinch")
	touch_a.pressed = false
	camera._unhandled_input(touch_a)

	# Raise collision terrain above the focus point. The camera must stay above it.
	var terrain: StaticBody3D = StaticBody3D.new()
	terrain.collision_layer = 1
	terrain.collision_mask = 0
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(256.0, 16.0, 256.0)
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	terrain.add_child(collider)
	root.add_child(terrain)
	camera.focus_point = Vector3.ZERO
	camera._set_zoom(0.0)
	camera._rendered_distance = Controller.NEAR_DISTANCE
	camera._rendered_pitch = Controller.NEAR_PITCH
	await physics_frame
	await physics_frame
	assert(camera.global_position.y > 8.0 + camera.collision_clearance, "Raised terrain must not clip camera")
	terrain.queue_free()
	camera.queue_free()
	await process_frame
	print("PROMPT_007 camera regression PASS")
	quit(0)
