extends SceneTree

## Touch controls: floating joystick (dead zone, unit direction, release to
## zero), camera drag on the right half, independent multi-touch fingers, HUD
## touches stay with the HUD, and the world feeds the joystick into the same
## server `move` intent the keyboard uses.
const TouchControls = preload("res://gameplay/touch_controls.gd")
const WorldScene = preload("res://gameplay/vertical_slice.tscn")

class FakeClient extends Node:
	var moves: Array = []
	func is_authenticated() -> bool:
		return true
	func request_move(dx: float, dy: float) -> bool:
		moves.append(Vector2(dx, dy))
		return true
	func request_world_chunk(_x: int, _y: int) -> String:
		return ""

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		push_error("touch controls test failed: " + label)
		failures += 1

func touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)

func drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	root.push_input(event, true)

func mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = pressed
	root.push_input(event, true)

func mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)

func near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.001

func run() -> void:
	var screen: Vector2 = root.get_visible_rect().size
	var left := Vector2(screen.x * 0.25, screen.y * 0.7)
	var right := Vector2(screen.x * 0.75, screen.y * 0.7)
	var radius: float = TouchControls.JOYSTICK_RADIUS

	# Pure mapping: dead zone and unit direction.
	check(TouchControls.direction_for_offset(Vector2(radius * 0.1, 0)) == Vector2.ZERO, "inside dead zone is zero")
	check(TouchControls.direction_for_offset(Vector2(0, radius * 0.14)) == Vector2.ZERO, "just inside dead zone is zero")
	check(near(TouchControls.direction_for_offset(Vector2(radius * 0.2, 0)), Vector2(1, 0)), "just past dead zone is a unit vector")
	check(near(TouchControls.direction_for_offset(Vector2(radius * 3, radius * 3)), Vector2(1, 1).normalized()), "far diagonal is normalized")

	var controls = TouchControls.new()
	root.add_child(controls)
	await process_frame
	check(controls.mouse_filter == Control.MOUSE_FILTER_IGNORE, "controls never block GUI hit-testing")
	var cam_deltas: Array = []
	controls.camera_drag.connect(func(d: Vector2) -> void: cam_deltas.append(d))
	var taps: Array = []
	controls.tapped.connect(func(p: Vector2) -> void: taps.append(p))

	# Joystick appears where the thumb lands.
	touch(0, left, true)
	check(controls.is_joystick_active() and controls.joystick_vector() == Vector2.ZERO, "joystick starts at rest where the thumb lands")
	drag(0, left + Vector2(radius * 0.1, radius * 0.05))
	check(controls.joystick_vector() == Vector2.ZERO, "small drag stays in the dead zone")
	drag(0, left + Vector2(0, -radius * 0.5))
	check(near(controls.joystick_vector(), Vector2(0, -1)), "drag up gives (0,-1), got %s" % controls.joystick_vector())
	drag(0, left + Vector2(radius * 2, radius * 2))
	check(near(controls.joystick_vector(), Vector2(1, 1).normalized()) and is_equal_approx(controls.joystick_vector().length(), 1.0), "diagonal past the rim is unit length")

	# Second finger on the right half drives the camera without touching the joystick.
	touch(1, right, true)
	check(controls.is_camera_active(), "second finger on the right claims the camera")
	drag(1, right + Vector2(30, 0))
	drag(0, left + Vector2(-radius, 0))
	drag(1, right + Vector2(50, 10))
	check(cam_deltas == [Vector2(30, 0), Vector2(20, 10)], "camera receives only finger 1 deltas, got %s" % [cam_deltas])
	check(near(controls.joystick_vector(), Vector2(-1, 0)), "joystick follows only finger 0, got %s" % controls.joystick_vector())
	touch(1, right + Vector2(50, 10), false)
	check(not controls.is_camera_active() and near(controls.joystick_vector(), Vector2(-1, 0)), "lifting the camera finger leaves the joystick held")
	touch(0, left + Vector2(-radius, 0), false)
	check(not controls.is_joystick_active() and controls.joystick_vector() == Vector2.ZERO, "release resets the joystick to zero")
	check(taps.is_empty(), "drags are not taps")

	# Mouse emulation drives the same joystick; touch-emulated mouse is ignored.
	mouse_button(left, true)
	mouse_motion(left + Vector2(radius, 0))
	check(near(controls.joystick_vector(), Vector2(1, 0)), "mouse drag drives the joystick")
	mouse_button(left + Vector2(radius, 0), false)
	check(controls.joystick_vector() == Vector2.ZERO, "mouse release resets")
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.position = left
	emulated.pressed = true
	root.push_input(emulated, true)
	check(not controls.is_joystick_active(), "touch-emulated mouse does not double-claim")
	# A short press without a drag is a tap.
	touch(2, right, true)
	touch(2, right + Vector2(3, 0), false)
	check(taps.size() == 1, "short press emits one tap")
	# An OS-cancelled gesture frees the finger but is never a tap.
	touch(2, right, true)
	var cancel := InputEventScreenTouch.new()
	cancel.index = 2
	cancel.position = right + Vector2(2, 0)
	cancel.pressed = false
	cancel.canceled = true
	root.push_input(cancel, true)
	check(taps.size() == 1 and not controls.is_camera_active(), "cancelled camera touch emits no tap and frees the finger")
	touch(7, left, true)
	drag(7, left + Vector2(radius, 0))
	cancel.index = 7
	cancel.position = left + Vector2(radius, 0)
	root.push_input(cancel, true)
	check(taps.size() == 1 and not controls.is_joystick_active() and controls.joystick_vector() == Vector2.ZERO, "cancelled joystick touch resets without a tap")
	controls.queue_free()
	await process_frame

	# Integration: world mounts TouchControls under the HUD.
	var world = WorldScene.instantiate()
	root.add_child(world)
	await process_frame
	var mounted = world.get_node_or_null("Interface/TouchControls")
	check(mounted != null, "world mounts TouchControls in the Interface layer")
	var panel: Control = world.get_node("Interface/Panel")
	if mounted != null:
		check(mounted.get_index() < panel.get_index(), "touch layer is drawn below the HUD panel")
	var fake := FakeClient.new()
	world.add_child(fake)
	world._client = fake

	# A touch starting on the HUD panel never moves the player.
	var hud_point: Vector2 = panel.get_global_rect().get_center()
	# World joystick touches start on the left half but outside the HUD panel.
	var hud_rect: Rect2 = panel.get_global_rect()
	var split: float = mounted.joystick_split_x() if mounted != null else screen.x * 0.5
	# The joystick zone beside a left-docked HUD is half the free area, not a sliver.
	check(is_equal_approx(split - hud_rect.end.x, screen.x - split) and split - hud_rect.end.x >= 3.0 * radius, "joystick zone beside the HUD is %.0f px wide (split %.0f, HUD end %.0f)" % [split - hud_rect.end.x, split, hud_rect.end.x])
	left = Vector2(hud_rect.end.x + 30.0, screen.y * 0.7)
	check(not hud_rect.has_point(left) and left.x < split, "world joystick point is in the joystick zone and off the HUD")
	if mounted != null:
		touch(9, left, true)
		check(mounted.is_joystick_active() and mounted._joystick_anchor.x - radius >= hud_rect.end.x - 0.01, "joystick ring is drawn clear of the HUD, ring x %.0f" % mounted._joystick_anchor.x)
		check(mounted.joystick_vector() == Vector2.ZERO, "clamping the ring never moves the player at rest")
		var cancel_hud := InputEventScreenTouch.new()
		cancel_hud.index = 9
		cancel_hud.position = left
		cancel_hud.canceled = true
		root.push_input(cancel_hud, true)
	touch(3, hud_point, true)
	drag(3, hud_point + Vector2(radius, 0))
	await process_frame
	await process_frame
	check(mounted != null and not mounted.is_joystick_active(), "HUD touch does not start the joystick")
	check(world.manual_move_intent() == Vector2.ZERO and fake.moves.is_empty(), "HUD touch sends no move, got %s" % [fake.moves])
	touch(3, hud_point + Vector2(radius, 0), false)
	# HUD buttons still receive presses with the touch layer mounted.
	var gather: Button = world.get_node("Interface/Panel/Margin/Content/Gather")
	var gather_point := gather.get_global_rect().get_center()
	mouse_button(gather_point, true)
	mouse_button(gather_point, false)
	await process_frame
	check(world._status.text == "No server-visible resource in this chunk", "HUD Gather button still receives the press, status '%s'" % world._status.text)

	# Keyboard reference intents, then the equivalent joystick vectors.
	var cases := [["move_right", Vector2(1, 0)], ["move_forward", Vector2(0, -1)], ["move_left", Vector2(-1, 0)], ["move_back", Vector2(0, 1)]]
	for case in cases:
		var action: String = case[0]
		var offset: Vector2 = case[1] * radius
		Input.action_press(action)
		var keyboard_intent: Vector2 = world.manual_move_intent()
		fake.moves.clear()
		await process_frame
		await process_frame
		var keyboard_moves: Array = fake.moves.duplicate()
		Input.action_release(action)
		await process_frame
		touch(4, left, true)
		drag(4, left + offset)
		var joystick_intent: Vector2 = world.manual_move_intent()
		fake.moves.clear()
		await process_frame
		await process_frame
		var joystick_moves: Array = fake.moves.duplicate()
		touch(4, left + offset, false)
		await process_frame
		check(keyboard_intent != Vector2.ZERO and near(keyboard_intent, joystick_intent), "%s: joystick intent %s equals keyboard %s" % [action, joystick_intent, keyboard_intent])
		check(not keyboard_moves.is_empty() and not joystick_moves.is_empty(), "%s: both inputs send server move intents" % action)
		if not keyboard_moves.is_empty() and not joystick_moves.is_empty():
			check(near(keyboard_moves[0], joystick_moves[0]), "%s: same move payload, keyboard %s joystick %s" % [action, keyboard_moves[0], joystick_moves[0]])
	fake.moves.clear()
	await process_frame
	await process_frame
	check(fake.moves.is_empty(), "no move is sent after release")
	# An approach started (tap / Gather) while the stick is held is cancelled, so
	# it cannot walk the player once manual input is released.
	touch(8, left, true)
	drag(8, left + Vector2(radius, 0))
	await process_frame
	world._approaching = true
	world._move_to_point = true
	await process_frame
	await process_frame
	check(not world._approaching, "approach started during manual movement is cancelled")
	touch(8, left + Vector2(radius, 0), false)
	await process_frame
	fake.moves.clear()
	await process_frame
	await process_frame
	check(fake.moves.is_empty() and not world._approaching, "no automatic walk after releasing the stick, got %s" % [fake.moves])

	# Camera drag orbits the camera, and movement stays camera-relative for both inputs.
	touch(5, right, true)
	drag(5, right + Vector2(-120, 0))
	touch(5, right + Vector2(-120, 0), false)
	check(not is_zero_approx(world._camera_yaw), "right-half drag orbits the camera")
	Input.action_press("move_forward")
	var kb_forward: Vector2 = world.manual_move_intent()
	Input.action_release("move_forward")
	touch(6, left, true)
	drag(6, left + Vector2(0, -radius))
	var js_forward: Vector2 = world.manual_move_intent()
	touch(6, left + Vector2(0, -radius), false)
	var camera: Camera3D = world.get_node("Camera")
	var away := Vector2(-camera.global_transform.basis.z.x, -camera.global_transform.basis.z.z).normalized()
	check(near(kb_forward, js_forward), "orbited: joystick forward equals keyboard forward")
	check(kb_forward.distance_to(away) < 0.01, "forward walks away from the orbited camera, got %s vs %s" % [kb_forward, away])
	world.queue_free()
	await process_frame

	if failures > 0:
		push_error("touch controls test: %d failure(s)" % failures)
		print("FAIL touch_controls_test")
		quit(1)
	else:
		print("PASS touch_controls_test")
		quit(0)
