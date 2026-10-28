class_name IslesWebSocketAdapter
extends Node

signal status_changed(status: String)
signal message_received(message: Dictionary)

var _socket := WebSocketPeer.new()
var _url := ""
var _token := ""
var _attempt_active := false
var _auth_sent := false
var _authenticated := false

func configure(url: String, token: String) -> void:
	_url = url.strip_edges()
	_token = token

func connect_to_server() -> void:
	# Each explicit Connect replaces the previous attempt and its credentials.
	_socket.close()
	_socket = WebSocketPeer.new()
	_attempt_active = false
	_auth_sent = false
	_authenticated = false
	if _url.is_empty():
		status_changed.emit("No server endpoint configured")
		return
	if not _is_safe_authenticated_url(_url):
		status_changed.emit("Use wss://, or ws:// loopback for local testing")
		return
	if _token.is_empty():
		status_changed.emit("Login token required")
		return
	status_changed.emit("Connecting…")
	var error := _socket.connect_to_url(_url)
	if error != OK:
		status_changed.emit("Connection failed (%s)" % error)
		return
	_attempt_active = true

func _process(_delta: float) -> void:
	if not _attempt_active:
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _auth_sent:
			_auth_sent = true
			if _socket.send_text(JSON.stringify({"type": "auth", "token": _token})) != OK:
				_socket.close()
				_attempt_active = false
				status_changed.emit("Authentication request could not be sent")
				return
			status_changed.emit("Connected; awaiting authentication…")
		while _socket.get_available_packet_count() > 0:
			var parsed = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
			if parsed is Dictionary:
				if parsed.get("type", "") == "auth_ok":
					_authenticated = true
				message_received.emit(parsed)
	elif state == WebSocketPeer.STATE_CLOSED:
		_attempt_active = false
		status_changed.emit("Disconnected" if _auth_sent else "Connection failed; check endpoint and server availability")

func is_authenticated() -> bool:
	return _authenticated

# Sends one gameplay intent. Refused until the server has confirmed authentication.
func send_message(payload: Dictionary) -> Error:
	if not _attempt_active or not _authenticated or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	return _socket.send_text(JSON.stringify(payload))

func _is_safe_authenticated_url(url: String) -> bool:
	var pattern := RegEx.new()
	# Match the entire authority: lookalike hosts and userinfo are never loopback.
	pattern.compile("^wss://[^/@?#\\s]+(?:/[^\\s]*)?$|^ws://(?:127\\.0\\.0\\.1|localhost|\\[::1\\])(?::[0-9]{1,5})?(?:/[^\\s]*)?$")
	return pattern.search(url) != null
