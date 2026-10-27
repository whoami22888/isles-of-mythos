class_name IslesPlayerSession
extends Node

## Client-side view of the authenticated player. The server is authoritative:
## this node only forwards bounded movement intent at the approved 20 Hz cadence
## and smooths the server-confirmed position for rendering. It never moves the
## player, grants items or edits stats locally.

signal state_updated(state: Dictionary)
signal server_error(code: String)

const INPUT_HZ := 20.0
const INPUT_INTERVAL := 1.0 / INPUT_HZ
const DEADZONE := 0.12
## Display catches up with authority within ~100 ms without teleport jitter.
const SMOOTHING_RATE := 18.0
## Larger corrections (respawn, knockback, server rejection) snap immediately.
const SNAP_DISTANCE := 6.0

var _sender: Callable
var _intent := Vector2.ZERO
var _last_sent := Vector2.ZERO
var _sequence := 0
var _accumulator := 0.0
var _has_state := false
var _state: Dictionary = {}
var _authoritative := Vector2.ZERO
var _display := Vector2.ZERO

func bind_sender(sender: Callable) -> void:
	_sender = sender

func has_state() -> bool:
	return _has_state

func state() -> Dictionary:
	return _state

func authoritative_position() -> Vector2:
	return _authoritative

func display_position() -> Vector2:
	return _display

func sequence() -> int:
	return _sequence

## Movement intent from keyboard or the touch joystick; clamped to the server's
## |dx|,|dy| <= 1 contract and length <= 1 so diagonals are not faster.
func set_move_intent(direction: Vector2) -> void:
	if not direction.is_finite() or direction.length() < DEADZONE:
		_intent = Vector2.ZERO
		return
	_intent = direction.limit_length(1.0)

func apply_message(message: Dictionary) -> void:
	match String(message.get("type", "")):
		"player_state":
			var incoming = message.get("state")
			if incoming is Dictionary and _is_finite_number(incoming.get("x")) and _is_finite_number(incoming.get("y")):
				_apply_state(incoming)
		"error":
			server_error.emit(String(message.get("code", "UNKNOWN")))

func reset() -> void:
	_intent = Vector2.ZERO
	_last_sent = Vector2.ZERO
	_accumulator = 0.0
	_has_state = false
	_state = {}
	# Sequence keeps increasing so a reconnect can never replay old numbers.

func _process(delta: float) -> void:
	step(delta)

## Deterministic tick used by _process and tests.
func step(delta: float) -> void:
	_display = _smoothed(_display, _authoritative, delta)
	if not _has_state:
		return
	_accumulator = minf(_accumulator + delta, INPUT_INTERVAL * 2.0)
	if _accumulator < INPUT_INTERVAL:
		return
	_accumulator -= INPUT_INTERVAL
	var moving := _intent != Vector2.ZERO
	# Send while moving, plus exactly one stop frame when input is released.
	if not moving and _last_sent == Vector2.ZERO:
		return
	if _sender.is_valid() and _sender.call({"type": "move", "dx": _intent.x, "dy": _intent.y, "sequence": _sequence + 1}):
		_sequence += 1
		_last_sent = _intent

func _apply_state(incoming: Dictionary) -> void:
	_state = incoming.duplicate(true)
	_authoritative = Vector2(float(incoming["x"]), float(incoming["y"]))
	if not _has_state or _display.distance_to(_authoritative) > SNAP_DISTANCE:
		_display = _authoritative
	_has_state = true
	state_updated.emit(_state)

static func _smoothed(from: Vector2, to: Vector2, delta: float) -> Vector2:
	return from.lerp(to, 1.0 - exp(-SMOOTHING_RATE * maxf(delta, 0.0)))

static func _is_finite_number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))
