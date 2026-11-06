extends Control

## Phone controls for the vertical slice: a floating virtual joystick on the
## left half of the free play area (beside a left-docked HUD) and camera
## drag/orbit on the right half.
##
## Presentation/input only. The joystick produces a normalized direction that
## the world feeds into the same `move` intent path the keyboard uses; the
## server still computes every position. Touches that start on the HUD panel
## (or any rect in `blocked_controls`) are never claimed, so HUD buttons and the
## HUD ScrollContainer keep working. The node itself uses MOUSE_FILTER_IGNORE
## so it never blocks GUI hit-testing.

signal joystick_changed(direction: Vector2)
signal camera_drag(delta: Vector2)
## A short press without a drag: the world treats it as tap-to-move/gather.
signal tapped(screen_position: Vector2)

const DEAD_ZONE := 0.15
const JOYSTICK_RADIUS := 96.0
const TAP_MAX_TRAVEL := 14.0
## Finger index used for real (non-touch-emulated) mouse input so desktop and
## headless tests can drive the controls without colliding with touch indices.
const MOUSE_FINGER := 1000

## Controls whose global rects must keep receiving touches (the HUD panel).
var blocked_controls: Array[Control] = []

var _joystick_finger := -1
var _joystick_origin := Vector2.ZERO
var _joystick_point := Vector2.ZERO
## Where the ring is drawn: the landing point clamped clear of the HUD/edges.
var _joystick_anchor := Vector2.ZERO
var _direction := Vector2.ZERO
var _camera_finger := -1
var _camera_last := Vector2.ZERO
## finger index -> [start position, max travel]
var _travel: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func joystick_vector() -> Vector2:
	return _direction

func is_joystick_active() -> bool:
	return _joystick_finger != -1

func is_camera_active() -> bool:
	return _camera_finger != -1

## Clears every finger (e.g. when the app loses focus) so no stale direction
## keeps sending move intents.
func reset() -> void:
	_joystick_finger = -1
	_camera_finger = -1
	_travel.clear()
	_set_direction(Vector2.ZERO)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		reset()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		# An OS-cancelled gesture releases the finger but is never a tap.
		_on_press(event.index, event.position, event.pressed, event.canceled)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Touch-emulated mouse events (device -1) duplicate a ScreenTouch.
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_on_press(MOUSE_FINGER, event.position, event.pressed)
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_on_drag(MOUSE_FINGER, event.position)

func _on_press(finger: int, position: Vector2, pressed: bool, canceled := false) -> void:
	if pressed:
		if _is_blocked(position) or finger == _joystick_finger or finger == _camera_finger:
			return
		var free_left := free_area_left()
		var left_half := position.x < joystick_split_x()
		if left_half and _joystick_finger == -1:
			_joystick_finger = finger
			# Direction is always measured from where the thumb landed; only the
			# drawn ring is clamped so it stays fully visible beside a docked HUD.
			var screen := _screen_size()
			_joystick_origin = position
			_joystick_anchor = Vector2(
				clampf(position.x, free_left + JOYSTICK_RADIUS, maxf(free_left + JOYSTICK_RADIUS, screen.x - JOYSTICK_RADIUS)),
				clampf(position.y, JOYSTICK_RADIUS, maxf(JOYSTICK_RADIUS, screen.y - JOYSTICK_RADIUS)))
			_joystick_point = position
			_set_direction(Vector2.ZERO)
		elif not left_half and _camera_finger == -1:
			_camera_finger = finger
			_camera_last = position
		else:
			return
		_travel[finger] = [position, 0.0]
		_claim()
		queue_redraw()
		return
	if finger != _joystick_finger and finger != _camera_finger:
		return
	var was_tap: bool = not canceled and _travel.has(finger) and float(_travel[finger][1]) <= TAP_MAX_TRAVEL
	_travel.erase(finger)
	if finger == _joystick_finger:
		_joystick_finger = -1
		_set_direction(Vector2.ZERO)
	else:
		_camera_finger = -1
	_claim()
	queue_redraw()
	if was_tap:
		tapped.emit(position)

func _on_drag(finger: int, position: Vector2) -> void:
	if finger != _joystick_finger and finger != _camera_finger:
		return
	if _travel.has(finger):
		var start: Vector2 = _travel[finger][0]
		_travel[finger][1] = maxf(float(_travel[finger][1]), start.distance_to(position))
	if finger == _joystick_finger:
		_joystick_point = position
		_set_direction(direction_for_offset(position - _joystick_origin))
	else:
		var delta := position - _camera_last
		_camera_last = position
		if delta != Vector2.ZERO:
			camera_drag.emit(delta)
	_claim()
	queue_redraw()

## Joystick offset (pixels from where the thumb landed) to a unit direction;
## zero inside the dead zone.
static func direction_for_offset(offset: Vector2) -> Vector2:
	if offset.length() / JOYSTICK_RADIUS < DEAD_ZONE:
		return Vector2.ZERO
	return offset.normalized()

func _set_direction(direction: Vector2) -> void:
	if direction == _direction:
		return
	_direction = direction
	joystick_changed.emit(_direction)

func _is_blocked(position: Vector2) -> bool:
	for control in blocked_controls:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(position):
			return true
	return false

## Right edge of any visible blocked control docked on the left side of the
## screen (the HUD panel); 0 when nothing is docked there.
func free_area_left() -> float:
	var screen := _screen_size()
	var edge := 0.0
	for control in blocked_controls:
		if is_instance_valid(control) and control.is_visible_in_tree():
			var rect := control.get_global_rect()
			if rect.position.x < screen.x * 0.25 and rect.end.x < screen.x * 0.75:
				edge = maxf(edge, rect.end.x)
	return edge

## Touches left of this x drive the joystick, right of it the camera: the
## midpoint of the area not covered by a left-docked HUD, so the joystick zone
## is always as wide as the camera zone instead of a sliver beside the HUD.
func joystick_split_x() -> float:
	var free_left := free_area_left()
	return free_left + (_screen_size().x - free_left) * 0.5

func _claim() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()

func _screen_size() -> Vector2:
	var viewport := get_viewport()
	return viewport.get_visible_rect().size if viewport != null else size

func _draw() -> void:
	if _joystick_finger == -1:
		return
	var base := _joystick_anchor - get_global_rect().position
	draw_circle(base, JOYSTICK_RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(base, JOYSTICK_RADIUS, 0.0, TAU, 48, Color(1, 0.95, 0.82, 0.45), 2.0)
	var knob := base + (_joystick_point - _joystick_origin).limit_length(JOYSTICK_RADIUS)
	draw_circle(knob, JOYSTICK_RADIUS * 0.38, Color(1, 0.95, 0.82, 0.55))
