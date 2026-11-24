extends SceneTree
## Run with: godot --headless --path client-godot --script res://tests/camera_zoom_controller_regression.gd

const Controller = preload("res://scripts/camera_zoom_controller.gd")
const RenderingEvidenceGuard = preload("res://scripts/rendering_evidence_guard.gd")
var _failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		_failures += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_cmdline_user_args().has("--force-failure"):
		check(false, "intentional failure probe")
		print("PROMPT_007 camera regression: %d failures" % _failures)
		quit(1)
		return
	check(RenderingEvidenceGuard.is_mobile_vulkan("mobile", "vulkan"), "Mobile/Vulkan renderer must be accepted")
	check(not RenderingEvidenceGuard.is_mobile_vulkan("gl_compatibility", "opengl3"), "OpenGL compatibility fallback must be rejected")
	check(not RenderingEvidenceGuard.is_mobile_vulkan("mobile", "opengl3"), "Mobile method with OpenGL driver must be rejected")
	check(not RenderingEvidenceGuard.is_mobile_vulkan("forward_plus", "vulkan"), "Forward+ must not be accepted as Mobile/Vulkan")
	var camera = Controller.new()
	camera.terrain_collision_mask = Controller.CAMERA_TERRAIN_COLLISION_LAYER # _ready must not query a locked physics space
	root.add_child(camera)
	await process_frame
	# Focus and orbit are target state: only the physics callback may replace the
	# camera transform, preserving the last terrain-resolved pose between ticks.
	var initial_transform: Transform3D = camera.global_transform
	camera.set_focus_point(Vector3(5.0, 0.0, 0.0))
	camera.set_orbit_yaw(PI * 0.5)
	check(camera.global_transform.is_equal_approx(initial_transform), "focus/orbit changes do not write an unchecked transform outside physics")
	await physics_frame
	check(not camera.global_transform.is_equal_approx(initial_transform), "camera applies focus/orbit on a physics tick")
	check(absf(camera.rotation.y - PI * 0.5) < 0.001, "orbit yaw is applied on a physics tick")
	camera.set_focus_point(Vector3.ZERO)
	camera.set_orbit_yaw(0.0)
	await physics_frame
	# Manual interpolation calls below are not physics callbacks; keep raycasts off.
	# The raised-terrain test at the end re-enables the mask on real physics ticks.
	camera.terrain_collision_mask = 0
	check(is_equal_approx(camera.global_position.distance_to(camera.focus_point), 10.0), "Near camera distance")
	check(is_equal_approx(rad_to_deg(camera.rotation.x), -45.0), "Near camera pitch")
	var transitions: Array[bool] = []
	camera.camera_mode_changed.connect(func(top_down: bool) -> void: transitions.append(top_down))
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for i in range(20):
		camera._unhandled_input(wheel)
	check(transitions == [true], "Top-down transition must emit exactly once")
	var previous_distance: float = camera.global_position.distance_to(camera.focus_point)
	var previous_pitch: float = rad_to_deg(camera.rotation.x)
	for frame in range(180):
		camera._physics_process(1.0 / 60.0)
		var current_distance: float = camera.global_position.distance_to(camera.focus_point)
		var current_pitch: float = rad_to_deg(camera.rotation.x)
		check(current_distance + 0.001 >= previous_distance, "Zoom-out distance must be monotonic")
		check(current_pitch <= previous_pitch + 0.001, "Pitch must move toward top-down monotonically")
		check(current_distance <= Controller.FAR_DISTANCE + 0.05, "Zoom-out distance must not overshoot")
		check(current_pitch >= Controller.FAR_PITCH - 0.05, "Top-down pitch must not overshoot")
		previous_distance = current_distance
		previous_pitch = current_pitch
	check(absf(camera.global_position.distance_to(camera.focus_point) - Controller.FAR_DISTANCE) < 0.05, "Far camera distance")
	check(absf(rad_to_deg(camera.rotation.x) - Controller.FAR_PITCH) < 0.05, "Far camera pitch")
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
	check(absf(far_pan_metres - expected_pan) < 0.01, "Horizontal pan must scale by viewport and field of view")
	camera._rendered_distance = Controller.NEAR_DISTANCE
	camera._rendered_pitch = Controller.NEAR_PITCH
	var near_pan_origin: Vector3 = camera.focus_point
	camera._pan(Vector2(0.0, 100.0))
	var near_vertical_pan: float = camera.focus_point.distance_to(near_pan_origin)
	var near_expected_pan: float = 100.0 * 2.0 * camera._rendered_distance * tan(half_fov) / viewport_size.y / sin(deg_to_rad(45.0))
	check(absf(near_vertical_pan - near_expected_pan) < 0.01, "Near-angle vertical pan must compensate for camera pitch")
	camera._rendered_distance = Controller.FAR_DISTANCE
	camera._rendered_pitch = Controller.FAR_PITCH
	var far_vertical_origin: Vector3 = camera.focus_point
	camera._pan(Vector2(0.0, 100.0))
	var far_vertical_pan: float = camera.focus_point.distance_to(far_vertical_origin)
	var far_expected_pan: float = 100.0 * 2.0 * camera._rendered_distance * tan(half_fov) / viewport_size.y / sin(deg_to_rad(85.0))
	check(absf(far_vertical_pan - far_expected_pan) < 0.01, "Far-angle vertical pan must compensate for camera pitch")
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
	check(camera._zoom_fraction < 1.0, "Pinch-in must zoom towards action view")
	touch_a.pressed = false
	touch_b.pressed = false
	camera._unhandled_input(touch_a)
	camera._unhandled_input(touch_b)
	# Fractional wheel events must sum to the same zoom as one whole wheel step.
	camera._set_zoom(0.5)
	wheel.factor = 0.1
	for i in range(10):
		camera._unhandled_input(wheel)
	check(absf(camera._zoom_fraction - 0.56) < 0.001, "Fractional wheel amount")
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	for i in range(10):
		camera._unhandled_input(wheel)
	check(absf(camera._zoom_fraction - 0.5) < 0.001, "Symmetric wheel amount")
	wheel.factor = 0.0
	camera._unhandled_input(wheel)
	check(absf(camera._zoom_fraction - 0.44) < 0.001, "Legacy zero wheel factor")

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
	check(absf(camera._zoom_fraction) < 0.001, "Parallel near-limit pan must not zoom")
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
	check(absf(camera._zoom_fraction - 1.0) < 0.001, "Parallel far-limit pan must not zoom")

	# A lost-focus gesture cannot leave ghost fingers behind.
	camera._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(camera._touches.is_empty(), "Focus loss clears touches")
	check(camera._pinch_start_distance == 0.0, "Focus loss clears pinch baseline")
	var zoom_before_new_touch: float = camera._zoom_fraction
	touch_a.position = Vector2(120, 100)
	camera._unhandled_input(touch_a)
	drag.index = 0
	drag.position = Vector2(145, 100)
	camera._unhandled_input(drag)
	check(is_equal_approx(camera._zoom_fraction, zoom_before_new_touch), "One new finger does not inherit stale pinch")
	touch_a.pressed = false
	camera._unhandled_input(touch_a)

	# Return to the 3D action view and check monotonic interpolation in reverse.
	var transition_count_before_return: int = transitions.size()
	camera._set_zoom(0.0)
	previous_distance = camera.global_position.distance_to(camera.focus_point)
	previous_pitch = rad_to_deg(camera.rotation.x)
	for frame in range(180):
		camera._physics_process(1.0 / 60.0)
		var return_distance: float = camera.global_position.distance_to(camera.focus_point)
		var return_pitch: float = rad_to_deg(camera.rotation.x)
		check(return_distance <= previous_distance + 0.001, "Zoom-in distance must be monotonic")
		check(return_pitch >= previous_pitch - 0.001, "Pitch must return to action view monotonically")
		check(return_distance >= Controller.NEAR_DISTANCE - 0.05, "Zoom-in distance must not undershoot")
		check(return_pitch <= Controller.NEAR_PITCH + 0.05, "Action pitch must not overshoot")
		previous_distance = return_distance
		previous_pitch = return_pitch
	check(transitions.size() == transition_count_before_return + 1, "Returning to 3D emits one mode transition")
	check(transitions[transitions.size() - 1] == false, "Return transition must report action mode")
	check(absf(camera.global_position.distance_to(camera.focus_point) - Controller.NEAR_DISTANCE) < 0.05, "Return to near distance")
	check(absf(rad_to_deg(camera.rotation.x) - Controller.NEAR_PITCH) < 0.05, "Return to near pitch")

	# Raise collision terrain above the focus point. The camera must stay above it.
	var terrain: StaticBody3D = StaticBody3D.new()
	terrain.collision_layer = Controller.CAMERA_TERRAIN_COLLISION_LAYER
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
	camera.terrain_collision_mask = Controller.CAMERA_TERRAIN_COLLISION_LAYER # Restore physics collision for the real-tick terrain regression.
	await physics_frame
	await physics_frame
	check(camera.global_position.y > 8.0 + camera.collision_clearance, "Raised terrain must not clip camera")
	terrain.queue_free()
	camera.queue_free()
	await process_frame
	print("PROMPT_007 camera regression: %d failures" % _failures)
	quit(1 if _failures else 0)
