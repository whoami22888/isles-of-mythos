class_name IslesWebSocketAdapter
extends Node

# Authenticated WebSocket transport. The server stays authoritative: this
# adapter only moves bounded, validated frames and recovers lost sessions.
# Bounds mirror the server (64 KiB inbound frames, bounded per-socket rate).

signal status_changed(status: String)
signal message_received(message: Dictionary)
# Emitted for every inbound packet that cannot be delivered; never dropped silently.
signal protocol_error(reason: String)
# Session recovery after an established, authenticated session is lost.
signal reconnect_scheduled(attempt: int, delay_seconds: float)
signal reconnected()
signal reconnect_failed()

const INBOUND_BUFFER_BYTES := 262144
const MAX_PACKET_BYTES := 131072
# Server closes with 1008 for invalid/expired credentials: never retry those.
const NO_RECONNECT_CLOSE_CODES := [1008]

var max_packets_per_frame := 64
var max_reconnect_attempts := 6
var reconnect_base_delay := 1.0
var max_reconnect_delay := 30.0

var _socket := WebSocketPeer.new()
var _url := ""
var _token := ""
var _attempt_active := false
var _auth_sent := false
var _authenticated := false
var _deliberate_close := false
var _reconnecting := false
var _reconnect_pending := false
var _reconnect_attempt := 0
var _reconnect_at_msec := 0

func configure(url: String, token: String) -> void:
	_url = url.strip_edges()
	_token = token

func connect_to_server() -> void:
	# Each explicit Connect replaces the previous attempt, credentials and any
	# recovery cycle in progress.
	_deliberate_close = false
	_reconnecting = false
	_reconnect_pending = false
	_reconnect_attempt = 0
	_authenticated = false
	_open_connection()

func disconnect_from_server() -> void:
	# Deliberate close: never triggers reconnect.
	_deliberate_close = true
	_reconnecting = false
	_reconnect_pending = false
	_authenticated = false
	if _attempt_active:
		_socket.close(1000, "client_disconnect")
	else:
		status_changed.emit("Disconnected")

func _open_connection() -> bool:
	_socket.close()
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = INBOUND_BUFFER_BYTES
	_attempt_active = false
	_auth_sent = false
	if _url.is_empty():
		status_changed.emit("No server endpoint configured")
		return false
	if not _is_safe_authenticated_url(_url):
		status_changed.emit("Use wss://, or ws:// loopback for local testing")
		return false
	if _token.is_empty():
		status_changed.emit("Login token required")
		return false
	status_changed.emit("Connecting…")
	var error := _socket.connect_to_url(_url)
	if error != OK:
		status_changed.emit("Connection failed (%s)" % error)
		return false
	_attempt_active = true
	return true

func _process(_delta: float) -> void:
	if _reconnect_pending:
		if Time.get_ticks_msec() >= _reconnect_at_msec:
			_reconnect_pending = false
			if not _open_connection():
				_schedule_reconnect()
		return
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
				if _reconnecting:
					_schedule_reconnect()
				return
			status_changed.emit("Connected; awaiting authentication…")
		_drain_packets()
	elif state == WebSocketPeer.STATE_CLOSED:
		_handle_closed()

func _drain_packets() -> void:
	# Bounded per frame: leftover packets stay queued for the next frame.
	var drained := 0
	while drained < max_packets_per_frame and _socket.get_available_packet_count() > 0:
		drained += 1
		var packet := _socket.get_packet()
		if packet.size() > MAX_PACKET_BYTES:
			protocol_error.emit("packet_too_large")
			continue
		# JSON.new().parse() reports failure by code; parse_string would print an
		# engine error per bad packet and let a hostile peer flood the log.
		var json := JSON.new()
		var parsed = json.data if json.parse(packet.get_string_from_utf8()) == OK else null
		if not (parsed is Dictionary):
			protocol_error.emit("packet_not_json_object")
			continue
		if parsed.get("type", "") == "auth_ok":
			_on_authenticated()
		message_received.emit(parsed)

func _on_authenticated() -> void:
	_authenticated = true
	if _reconnecting:
		_reconnecting = false
		_reconnect_attempt = 0
		status_changed.emit("Reconnected")
		reconnected.emit()

func _handle_closed() -> void:
	_attempt_active = false
	if _deliberate_close:
		status_changed.emit("Disconnected")
		return
	var code := _socket.get_close_code()
	if code in NO_RECONNECT_CLOSE_CODES:
		_reconnecting = false
		_authenticated = false
		status_changed.emit("Disconnected; server rejected the session")
		return
	if _authenticated:
		# An established session was lost: begin recovery.
		_authenticated = false
		_reconnecting = true
		_schedule_reconnect()
		return
	if _reconnecting:
		_schedule_reconnect()
		return
	status_changed.emit("Disconnected" if _auth_sent else "Connection failed; check endpoint and server availability")

func _schedule_reconnect() -> void:
	if _reconnect_attempt >= max_reconnect_attempts:
		_reconnecting = false
		status_changed.emit("Reconnect failed; connect manually")
		reconnect_failed.emit()
		return
	_reconnect_attempt += 1
	var delay := _backoff_delay(_reconnect_attempt)
	_reconnect_pending = true
	_reconnect_at_msec = Time.get_ticks_msec() + int(delay * 1000.0)
	status_changed.emit("Connection lost; retrying (%s/%s)…" % [_reconnect_attempt, max_reconnect_attempts])
	reconnect_scheduled.emit(_reconnect_attempt, delay)

func _backoff_delay(attempt: int) -> float:
	return minf(reconnect_base_delay * pow(2.0, attempt - 1), max_reconnect_delay)

func _is_safe_authenticated_url(url: String) -> bool:
	var pattern := RegEx.new()
	# Match the entire authority: lookalike hosts and userinfo are never loopback.
	pattern.compile("^wss://[^/@?#\\s]+(?:/[^\\s]*)?$|^ws://(?:127\\.0\\.0\\.1|localhost|\\[::1\\])(?::[0-9]{1,5})?(?:/[^\\s]*)?$")
	return pattern.search(url) != null
