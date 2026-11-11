extends SceneTree
## Run with: godot --headless --path client-godot --script res://tests/camera_zoom_controller_regression.gd

const Controller = preload("res://scripts/camera_zoom_controller.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var camera = Controller.new()
	camera.terrain_collision_mask = 0
	root.add_child(camera)
	await process_frame
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
	camera.queue_free()
	await process_frame
	print("PROMPT_007 camera regression PASS")
	quit(0)
