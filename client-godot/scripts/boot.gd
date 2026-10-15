extends Control

const Adapter = preload("res://scripts/websocket_adapter.gd")
@onready var _status: Label = $Panel/Margin/Content/Status
var _adapter: Node

func _ready() -> void:
	_status.text = "Preparing secure server connection…"
	_adapter = Adapter.new()
	add_child(_adapter)
	_adapter.status_changed.connect(_on_status_changed)
	_adapter.message_received.connect(_on_message)
	var endpoint := OS.get_environment("IOM_WS_URL")
	if endpoint.is_empty():
		endpoint = "ws://127.0.0.1:3000/ws"
	_adapter.configure(endpoint, OS.get_environment("IOM_AUTH_TOKEN"))
	_adapter.connect_to_server()

func _on_status_changed(status: String) -> void:
	_status.text = status

func _on_message(message: Dictionary) -> void:
	if message.get("type", "") == "auth_ok":
		_status.text = "Ready · server authenticated"
