# Presentation-only RTS camera for the internal authenticated vertical slice.
# The server owns the player position; the camera preserves a local pan/orbit offset.
extends Camera3D

@export var min_zoom: float = 10.0
@export var max_zoom: float = 60.0
@export var pan_speed: float = 0.05
@export var zoom_speed: float = 0.1
# Scales the angular difference of a real two-finger twist (radians).
@export var rotation_speed: float = 1.0
@export_node_path("Control") var ui_blocker_path: NodePath

const TAP_SLOP_PIXELS := 16.0

var touch_points: Dictionary = {}
var _tap_starts: Dictionary = {}
var _completed_taps: Dictionary = {}
var _last_pinch_distance := 0.0
var _last_twist_angle := 0.0
var _has_anchor := false
var _server_anchor := Vector3.ZERO
var _pan_offset := Vector3.ZERO


func _ready() -> void:
	# Detached from parent transforms, without detaching from the scene tree.
	top_level = true


# The authoritative position is expressed in world XZ. Moving the anchor
# translates the existing camera rig by exactly the same delta, without
# cancelling any player-selected pan, height or yaw.
func apply_server_anchor(new_position: Vector3, initial_offset: Vector3 = Vector3(0.0, 28.0, 24.0)) -> void:
	if not _has_anchor:
		_has_anchor = true
		_server_anchor = new_position
		global_position = new_position + initial_offset
	else:
		global_position += new_position - _server_anchor
		_server_anchor = new_position
	look_at(_focus_point(), Vector3.UP)


func _focus_point() -> Vector3:
	return _server_anchor + _pan_offset


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_handle_touch(event)
	elif event is InputEventScreenDrag:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var index := event.index
	if event.pressed:
		_completed_taps.erase(index)
		if touch_points.size() >= 2 or _is_over_ui(event.position):
			return
		touch_points[index] = event.position
		if touch_points.size() == 1:
			_tap_starts[index] = event.position
		else:
			# Two-finger gestures must never count as gather taps.
			_tap_starts.clear()
			_reset_pinch_baseline()
		return

	if not touch_points.has(index):
		return
	var started_as_tap := _tap_starts.has(index)
	var within_slop := started_as_tap and event.position.distance_to(_tap_starts[index]) <= TAP_SLOP_PIXELS
	touch_points.erase(index)
	_tap_starts.erase(index)
	if within_slop and touch_points.is_empty():
		_completed_taps[index] = true
	if touch_points.size() < 2:
		_last_pinch_distance = 0.0


func _handle_drag(event: InputEventScreenDrag) -> void:
	if not touch_points.has(event.index):
		return
	touch_points[event.index] = event.position
	if touch_points.size() == 1:
		if _tap_starts.has(event.index):
			if event.position.distance_to(_tap_starts[event.index]) <= TAP_SLOP_PIXELS:
				return
			_tap_starts.erase(event.index)
		_pan(event.relative)
	elif touch_points.size() == 2:
		var points := _ordered_touch_points()
		var difference: Vector2 = points[1] - points[0]
		var distance := difference.length()
		if _last_pinch_distance > 0.0:
			_zoom((_last_pinch_distance - distance) * zoom_speed)
			_rotate_orbit(wrapf(difference.angle() - _last_twist_angle, -PI, PI) * rotation_speed)
		_last_pinch_distance = distance
		_last_twist_angle = difference.angle()


func _ordered_touch_points() -> Array[Vector2]:
	var indices := touch_points.keys()
	indices.sort()
	var points: Array[Vector2] = []
	points.append(touch_points[indices[0]])
	points.append(touch_points[indices[1]])
	return points


func _reset_pinch_baseline() -> void:
	var points := _ordered_touch_points()
	var difference: Vector2 = points[1] - points[0]
	_last_pinch_distance = difference.length()
	_last_twist_angle = difference.angle()


func _pan(delta: Vector2) -> void:
	if not _has_anchor:
		return
	var right := global_transform.basis.x
	var forward := -global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	right = right.normalized()
	forward = forward.normalized()
	var height_scale := maxf(0.1, (global_position.y - _focus_point().y) / 28.0)
	var movement := -(right * delta.x + forward * delta.y) * pan_speed * height_scale
	global_position += movement
	_pan_offset += movement


func _zoom(height_change: float) -> void:
	if not _has_anchor:
		return
	var pivot := _focus_point()
	var height := global_position.y - pivot.y
	if height <= 0.0:
		return
	var next_height := clampf(height + height_change, minf(min_zoom, max_zoom), maxf(min_zoom, max_zoom))
	global_position = pivot + (global_position - pivot) * (next_height / height)
	look_at(pivot, Vector3.UP)


func _rotate_orbit(radians: float) -> void:
	if not _has_anchor or absf(radians) < 0.00001:
		return
	var pivot := _focus_point()
	global_position = pivot + (global_position - pivot).rotated(Vector3.UP, -radians)
	look_at(pivot, Vector3.UP)


func _is_over_ui(screen_position: Vector2) -> bool:
	if ui_blocker_path.is_empty():
		return false
	var blocker := get_node_or_null(ui_blocker_path) as Control
	return blocker != null and blocker.is_visible_in_tree() and blocker.get_global_rect().has_point(screen_position)


# Called by the parent _unhandled_input only on release; dragging, pinching,
# rotating or pressing a GUI control cannot issue a gather intent.
func consume_tap(index: int) -> bool:
	var tapped := _completed_taps.has(index)
	_completed_taps.erase(index)
	return tapped
