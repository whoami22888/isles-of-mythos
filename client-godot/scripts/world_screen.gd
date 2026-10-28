class_name IslesWorldScreen
extends Control

# First playable surface: status chip + touch joystick. Sends `move` intents at 20 Hz while the
# stick is held (server limit: 40 packets/s per socket). The server stays authoritative; this
# screen only renders the position from `player_state`.

const MOVE_INTERVAL := 0.05
const CHIP_MARGIN := 16.0

var _adapter: Node
var _stick: IslesTouchJoystick
var _chip: Label
var _sequence := 1
var _timer := 0.0
var _authenticated := false

func setup(adapter: Node) -> void:
	_adapter = adapter
	_adapter.message_received.connect(_on_message)
	_adapter.status_changed.connect(_on_status)
	# The world is created inside the auth_ok handler, so it cannot rely on receiving that message.
	if _adapter.is_authenticated():
		_authenticated = true
		_chip.text = "Connected · waiting for position"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip = $StatusChip
	_stick = $Joystick
	_layout()
	resized.connect(_layout)
	_chip.text = "Connecting…"

func _layout() -> void:
	var margin := IslesTouchJoystick.margin_for_viewport(size)
	var radius := IslesTouchJoystick.radius_for_viewport(size)
	var diameter := radius * 2.0
	_stick.custom_minimum_size = Vector2(diameter, diameter)
	_stick.size = Vector2(diameter, diameter)
	_stick.position = Vector2(margin, size.y - diameter - margin)
	_chip.position = Vector2(CHIP_MARGIN, CHIP_MARGIN)

func _process(delta: float) -> void:
	if not _authenticated or _adapter == null:
		return
	var vector := _stick.current_vector()
	if vector == Vector2.ZERO:
		_timer = 0.0
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = MOVE_INTERVAL
	_adapter.send_message({"type": "move", "dx": vector.x, "dy": vector.y, "sequence": _sequence})
	_sequence += 1

func _on_status(status: String) -> void:
	if not _authenticated:
		_chip.text = status

func _on_message(message: Dictionary) -> void:
	match message.get("type", ""):
		"auth_ok":
			_authenticated = true
			_chip.text = "Connected · waiting for position"
		"player_state":
			var state: Variant = message.get("state", {})
			if state is Dictionary:
				_chip.text = "Position %.1f, %.1f" % [float(state.get("x", 0.0)), float(state.get("y", 0.0))]
		"error":
			_chip.text = "Server: %s" % str(message.get("code", "error"))
