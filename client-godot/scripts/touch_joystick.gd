class_name IslesTouchJoystick
extends Control

# Virtual joystick. Emits a normalised world vector (dx, dy) with |v| <= 1.
# Sizes and colours follow the design-system tokens (--joystick-radius-*, --touch-margin-*,
# --alpha-stick, --alpha-ring, --alpha-knob, --signal, --foam, --abyss).

const DEAD_ZONE := 0.15
const RADIUS_MIN := 48.0
const RADIUS_COMPACT := 68.0
const RADIUS_MAX := 82.0
const MARGIN_MIN := 18.0
const MARGIN_MAX := 44.0
const MOUSE_INDEX := -2

const COLOR_BASE := Color(0.0275, 0.0745, 0.1216, 0.72)
const COLOR_RING := Color(1.0, 1.0, 1.0, 0.7)
const COLOR_KNOB := Color(0.1843, 0.5020, 0.9294, 0.82)

signal vector_changed(vector: Vector2)

var _active_index := -1
var _offset := Vector2.ZERO

static func radius_for_viewport(viewport: Vector2) -> float:
	var short_side := minf(viewport.x, viewport.y)
	var radius := clampf(short_side * 0.12, RADIUS_MIN, RADIUS_MAX)
	if viewport.x < 720.0 or viewport.y < 500.0:
		radius = minf(radius, RADIUS_COMPACT)
	return radius

static func margin_for_viewport(viewport: Vector2) -> float:
	return clampf(minf(viewport.x, viewport.y) * 0.045, MARGIN_MIN, MARGIN_MAX)

static func stick_vector(offset: Vector2, radius_px: float, dead_zone: float = DEAD_ZONE) -> Vector2:
	if radius_px <= 0.0:
		return Vector2.ZERO
	var normalised := offset / radius_px
	var length := normalised.length()
	if length < dead_zone:
		return Vector2.ZERO
	# Rescale so motion starts smoothly at the edge of the dead zone and reaches 1.0 at the rim.
	var magnitude := minf((length - dead_zone) / (1.0 - dead_zone), 1.0)
	return normalised.normalized() * magnitude

func current_vector() -> Vector2:
	return stick_vector(_offset, radius_for_viewport(size))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _active_index == -1:
			_begin(event.index, event.position)
		elif not event.pressed and event.index == _active_index:
			_end()
		accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _active_index:
			_track(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _active_index == -1:
			_begin(MOUSE_INDEX, event.position)
		elif not event.pressed and _active_index == MOUSE_INDEX:
			_end()
		accept_event()
	elif event is InputEventMouseMotion and _active_index == MOUSE_INDEX:
		_track(event.position)
		accept_event()

func _begin(index: int, local_position: Vector2) -> void:
	_active_index = index
	_track(local_position)

func _track(local_position: Vector2) -> void:
	_offset = local_position - size * 0.5
	queue_redraw()
	vector_changed.emit(current_vector())

func _end() -> void:
	_active_index = -1
	_offset = Vector2.ZERO
	queue_redraw()
	vector_changed.emit(Vector2.ZERO)

func _draw() -> void:
	var radius := radius_for_viewport(size)
	var centre := size * 0.5
	draw_circle(centre, radius, COLOR_BASE)
	draw_arc(centre, radius, 0.0, TAU, 64, COLOR_RING, 2.0, true)
	var knob_offset := _offset
	if knob_offset.length() > radius:
		knob_offset = knob_offset.normalized() * radius
	draw_circle(centre + knob_offset, radius * 0.45, COLOR_KNOB)
