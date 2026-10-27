class_name IslesVirtualJoystick
extends Control

## Thumb joystick for Android. Tracks one touch index so a second finger
## (camera, actions) never hijacks movement. Emits a vector of length <= 1.

signal direction_changed(direction: Vector2)

@export var radius := 110.0
@export var knob_radius := 46.0

var _touch_index := -1
var _knob := Vector2.ZERO
var direction := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(radius, radius) * 2.0

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_update(event.position)
		elif not event.pressed and event.index == _touch_index:
			_release()
		accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update(event.position)
		accept_event()

func _notification(what: int) -> void:
	# Losing focus/visibility mid-drag must never leave the player running.
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_release()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release()

func _update(local_position: Vector2) -> void:
	_knob = (local_position - size * 0.5).limit_length(radius)
	_set_direction(_knob / radius)

func _release() -> void:
	_touch_index = -1
	_knob = Vector2.ZERO
	_set_direction(Vector2.ZERO)

func _set_direction(value: Vector2) -> void:
	if value == direction:
		return
	direction = value
	queue_redraw()
	direction_changed.emit(direction)

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius, Color(0.02, 0.06, 0.1, 0.42))
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.86, 0.74, 0.48, 0.75), 3.0, true)
	draw_circle(center + _knob, knob_radius, Color(0.93, 0.84, 0.62, 0.85))
