extends Control

const Adapter = preload("res://scripts/websocket_adapter.gd")
const Session = preload("res://scripts/player_session.gd")
const Joystick = preload("res://scripts/virtual_joystick.gd")
const MOVE_KEYS := {
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
}

@onready var _panel: Control = $Panel
@onready var _status: Label = $Panel/Margin/Content/Status
@onready var _endpoint: LineEdit = $Panel/Margin/Content/Endpoint
@onready var _token: LineEdit = $Panel/Margin/Content/Token
@onready var _connect: Button = $Panel/Margin/Content/Connect
var _adapter: Node
var _session: Node
var _hud: Control
var _hud_vitals: Label
var _hud_notice: Label
var _joystick: Control
var _touch_direction := Vector2.ZERO

func _ready() -> void:
	_status.text = "Preparing secure server connection…"
	_register_move_actions()
	_adapter = Adapter.new()
	add_child(_adapter)
	_session = Session.new()
	add_child(_session)
	_session.bind_sender(_adapter.send_message)
	_session.state_updated.connect(_on_player_state)
	_session.server_error.connect(_on_server_error)
	_build_hud()
	_adapter.status_changed.connect(_on_status_changed)
	_adapter.message_received.connect(_on_message)
	_connect.pressed.connect(_connect_from_form)
	var endpoint := OS.get_environment("IOM_WS_URL")
	if endpoint.is_empty():
		endpoint = ProjectSettings.get_setting("application/config/default_ws_url", "ws://127.0.0.1:3000/ws")
	_endpoint.text = endpoint
	_token.text = OS.get_environment("IOM_AUTH_TOKEN")
	if not _token.text.is_empty():
		_adapter.configure(endpoint, _token.text)
		_adapter.connect_to_server()
	else:
		_status.text = "Enter a login token to connect"

func _process(_delta: float) -> void:
	if not _hud.visible:
		return
	var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_session.set_move_intent(keyboard if keyboard != Vector2.ZERO else _touch_direction)
	var p: Vector2 = _session.display_position()
	_hud_vitals.text = _vitals_text(_session.state(), p)

func _connect_from_form() -> void:
	_session.reset()
	_adapter.configure(_endpoint.text, _token.text)
	_adapter.connect_to_server()

func _on_status_changed(status: String) -> void:
	_status.text = status
	if not _adapter.is_authenticated():
		_show_gameplay(false)

func _on_message(message: Dictionary) -> void:
	if message.get("type", "") == "auth_ok":
		_status.text = "Ready · server authenticated"
	_session.apply_message(message)

func _on_player_state(_state: Dictionary) -> void:
	if _adapter.is_authenticated():
		_show_gameplay(true)

func _on_server_error(code: String) -> void:
	var notices := {
		"PLAYER_STUNNED": "Stunned!", "PLAYER_DEAD": "You have fallen",
		"RATE_LIMITED": "Slow down, captain", "AUTH_REQUIRED": "Session expired — reconnect",
	}
	_hud_notice.text = notices.get(code, "")
	if code == "AUTH_REQUIRED":
		_session.reset()
		_show_gameplay(false)

func _show_gameplay(active: bool) -> void:
	_hud.visible = active
	_panel.visible = not active
	if not active:
		_touch_direction = Vector2.ZERO
		_session.set_move_intent(Vector2.ZERO)

static func _vitals_text(state: Dictionary, position: Vector2) -> String:
	return "HP %s  ·  Stamina %s/%s  ·  Lv %s  ·  Gold %s\n(%.1f, %.1f)" % [
		state.get("health", "–"), state.get("stamina", "–"), state.get("maxStamina", "–"),
		state.get("level", "–"), state.get("gold", "–"), position.x, position.y]

func _register_move_actions() -> void:
	for action in MOVE_KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for key in MOVE_KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "GameplayHud"
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.visible = false
	add_child(_hud)
	_hud_vitals = Label.new()
	_hud_vitals.name = "Vitals"
	_hud_vitals.position = Vector2(24, 18)
	_hud_vitals.add_theme_font_size_override("font_size", 22)
	_hud.add_child(_hud_vitals)
	_hud_notice = Label.new()
	_hud_notice.name = "Notice"
	_hud_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud_notice.position.y = 80
	_hud_notice.add_theme_font_size_override("font_size", 26)
	_hud.add_child(_hud_notice)
	_joystick = Joystick.new()
	_joystick.name = "MoveJoystick"
	_hud.add_child(_joystick)
	_joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE, 48)
	_joystick.direction_changed.connect(func(direction: Vector2) -> void: _touch_direction = direction)
