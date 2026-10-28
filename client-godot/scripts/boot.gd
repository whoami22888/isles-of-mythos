extends Control

# Register / login front door. Credentials go to the real /auth routes over HTTPS (or loopback HTTP
# for local testing); the returned access token is kept in memory only and used for the WebSocket
# auth frame. Nothing is written to disk.

const Adapter = preload("res://scripts/websocket_adapter.gd")
const Auth = preload("res://scripts/auth_client.gd")
const WorldScene = preload("res://scenes/world.tscn")

@onready var _status: Label = $Panel/Margin/Content/Status
@onready var _endpoint: LineEdit = $Panel/Margin/Content/Endpoint
@onready var _login_mode: Button = $Panel/Margin/Content/ModeRow/LoginMode
@onready var _register_mode: Button = $Panel/Margin/Content/ModeRow/RegisterMode
@onready var _username: LineEdit = $Panel/Margin/Content/Username
@onready var _email: LineEdit = $Panel/Margin/Content/Email
@onready var _password: LineEdit = $Panel/Margin/Content/Password
@onready var _submit: Button = $Panel/Margin/Content/Submit
@onready var _http: HTTPRequest = $Http
@onready var _panel: Control = $Panel

var _adapter: Node
var _mode := "login"
var _pending := false

func _ready() -> void:
	_status.text = "Enter your details to begin"
	_adapter = Adapter.new()
	add_child(_adapter)
	_adapter.status_changed.connect(_on_status_changed)
	_adapter.message_received.connect(_on_message)
	_http.request_completed.connect(_on_auth_response)
	_login_mode.pressed.connect(_set_mode.bind("login"))
	_register_mode.pressed.connect(_set_mode.bind("register"))
	_submit.pressed.connect(_on_submit)
	var endpoint := OS.get_environment("IOM_WS_URL")
	if endpoint.is_empty():
		endpoint = ProjectSettings.get_setting("application/config/default_ws_url", "ws://127.0.0.1:3000/ws")
	_endpoint.text = endpoint
	_set_mode("login")

func _set_mode(mode: String) -> void:
	_mode = mode
	var registering := mode == "register"
	_login_mode.button_pressed = not registering
	_register_mode.button_pressed = registering
	_email.visible = registering
	_username.placeholder_text = "Username" if registering else "Username or email"
	_submit.text = "CREATE ACCOUNT" if registering else "ENTER WORLD"

func _on_submit() -> void:
	if _pending:
		return
	var username := _username.text
	var email := _email.text
	var password := _password.text
	var problem := Auth.validate(_mode, username, email, password)
	if not problem.is_empty():
		_status.text = problem
		return
	var base := Auth.api_base_from_ws(_endpoint.text)
	if base.is_empty():
		_status.text = "Server URL must start with wss:// or ws:// (loopback)"
		return
	var request := Auth.build_request(_mode, username, email, password)
	_pending = true
	_submit.disabled = true
	_status.text = "Creating account…" if _mode == "register" else "Signing in…"
	var error := _http.request(
		base + request["path"],
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(request["body"]),
	)
	# The password has been handed to the request; clear the field so it is not left on screen.
	_password.clear()
	if error != OK:
		_pending = false
		_submit.disabled = false
		_status.text = "Could not send the sign-in request"

func _on_auth_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	_submit.disabled = false
	var problem := Auth.message_for_result(_mode, result, code)
	if not problem.is_empty():
		_status.text = problem
		return
	var token := Auth.token_from_body(body)
	if token.is_empty():
		_status.text = "Unexpected response from the server"
		return
	_status.text = "Connecting to the world…"
	_adapter.configure(_endpoint.text, token)
	_adapter.connect_to_server()

func _on_status_changed(status: String) -> void:
	_status.text = status

func _on_message(message: Dictionary) -> void:
	if message.get("type", "") == "auth_ok":
		_enter_world()

func _enter_world() -> void:
	_panel.visible = false
	var world: IslesWorldScreen = WorldScene.instantiate()
	add_child(world)
	world.setup(_adapter)
	_adapter.status_changed.disconnect(_on_status_changed)
