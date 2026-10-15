class_name IslesWebSocketAdapter
extends Node

signal status_changed(status: String)
signal message_received(message: Dictionary)

var _socket := WebSocketPeer.new()
var _url := ""
var _token := ""
var _authenticated := false

func configure(url: String, token: String) -> void:
	_url = url.strip_edges()
	_token = token

func connect_to_server() -> void:
	if _url.is_empty():
		status_changed.emit("No server endpoint configured")
		return
	status_changed.emit("Connecting…")
	var error := _socket.connect_to_url(_url)
	if error != OK:
		status_changed.emit("Connection failed (%s)" % error)

func _process(_delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _authenticated:
			_authenticated = true
			status_changed.emit("Connected; authenticating…")
			if _token.is_empty():
				status_changed.emit("Connected; login token required")
			else:
				_send_auth()
		while _socket.get_available_packet_count() > 0:
			var text := _socket.get_packet().get_string_from_utf8()
			var parsed = JSON.parse_string(text)
			if parsed is Dictionary:
				message_received.emit(parsed)
	elif state == WebSocketPeer.STATE_CLOSED and _authenticated:
		_authenticated = false
		status_changed.emit("Disconnected")

func _send_auth() -> void:
	_socket.send_text(JSON.stringify({"type": "auth", "token": _token}))
	status_changed.emit("Authenticated request sent")
