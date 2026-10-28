extends Control

const Adapter = preload("res://scripts/network/authoritative_command_gateway.gd")
@onready var _status: Label = $Panel/Margin/Content/Status
@onready var _endpoint: LineEdit = $Panel/Margin/Content/Endpoint
@onready var _token: LineEdit = $Panel/Margin/Content/Token
@onready var _connect: Button = $Panel/Margin/Content/Connect
var _adapter: Node

func _ready() -> void:
	_status.text = "Preparing secure server connection…"
	_adapter = Adapter.new()
	add_child(_adapter)
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

func _connect_from_form() -> void:
	_adapter.configure(_endpoint.text, _token.text)
	_adapter.connect_to_server()

func _on_status_changed(status: String) -> void:
	_status.text = status

func _on_message(message: Dictionary) -> void:
	if message.get("type", "") == "auth_ok":
		_status.text = "Ready · server authenticated"
