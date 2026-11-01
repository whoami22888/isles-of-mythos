class_name IslesWebSocketAdapter
extends Node

# Authenticated WebSocket transport. The server stays authoritative: this
# adapter only moves bounded, validated frames and recovers lost sessions.
#
# Bounds: inbound frames are capped at 64 KiB, the same figure as the server's
# own frame limit (config.websocketMaxPayloadBytes). Measured headroom: the
# largest of 6,561 generated 32x32 world chunks serialises to 4,626 bytes.
# The server's 120 msgs/s per-socket throttle is enforced server-side only.
#
# Resync after a lost session uses only existing server messages. Re-sending
# `auth` makes the server push auth_ok, player_state, creature_party and
# base_state again; the adapter additionally replays the chunk set registered
# through subscribe_chunks() (server parser: 1-9 chunks, |x|,|y| <= 1,000,000).

signal status_changed(status: String)
# Emitted when the server closes with 1008 (policy violation). reason is the explicit
# auth code mapped from the close reason: "INVALID_TOKEN", "AUTH_TIMEOUT", or
# "POLICY_VIOLATION" for any other 1008 close.
signal auth_failed(reason: String)
signal message_received(message: Dictionary)
# Emitted for inbound packets that cannot be delivered. Bounded per window so a
# hostile peer cannot flood listeners: see invalid_packet_count for exact totals.
signal protocol_error(reason: String)
# Session recovery after an established, authenticated session is lost.
signal reconnect_scheduled(attempt: int, delay_seconds: float)
signal reconnected()
signal reconnect_failed()
# The tracked chunk subscription was replayed after a reconnect.
signal resync_requested(chunk_count: int)

# The server caps only client->server frames (64 KiB). Server->client creature snapshots
# are now paginated into <=48 KiB frames (MYTHOS-NET-05), but the inbound bound keeps
# headroom for other large server messages: 1 MiB per packet inside a 2 MiB receive buffer.
const INBOUND_BUFFER_BYTES := 2097152
const MAX_PACKET_BYTES := 1048576
const MAX_PACKETS_PER_FRAME_LIMIT := 256
const MAX_ERROR_SIGNALS_PER_WINDOW := 8
const MIN_ERROR_WINDOW_MSEC := 100
const MAX_CHUNK_SUBSCRIPTIONS := 9
const MAX_CHUNK_COORDINATE := 1000000
# Server closes with 1008 for invalid/expired credentials: never retry those.
const NO_RECONNECT_CLOSE_CODES := [1008]

# Clamped to 1..MAX_PACKETS_PER_FRAME_LIMIT so a bad value can never stall delivery.
var max_packets_per_frame := 64:
	set(value):
		max_packets_per_frame = clampi(value, 1, MAX_PACKETS_PER_FRAME_LIMIT)
var error_window_msec := 1000:
	set(value):
		error_window_msec = maxi(value, MIN_ERROR_WINDOW_MSEC)
# Exact totals; never suppressed.
var invalid_packet_count := 0
var suppressed_error_count := 0
var max_reconnect_attempts := 6
var reconnect_base_delay := 1.0
var max_reconnect_delay := 30.0

const SnapshotAssembler = preload("res://scripts/creature_snapshot_assembler.gd")

var _socket := WebSocketPeer.new()
# MYTHOS-NET-05: paginated creature snapshots are reassembled here, so consumers of
# message_received only ever see ONE complete `creature_party`, never a partial page.
var _snapshots := SnapshotAssembler.new()
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
var _tracked_chunks: Array = []
var _request_counter := 0
var _error_window_start_msec := 0
var _error_window_emitted := 0
var _error_window_summarised := false

func configure(url: String, token: String) -> void:
	_url = url.strip_edges()
	_token = token

# Registers the chunk set this session wants and requests it. Invalid input
# returns false, sends nothing and keeps any previously tracked set. If the
# session is not authenticated yet the request is sent once auth_ok arrives.
# Tracked chunks belong to one session: an explicit connect_to_server() clears
# them, and a reconnect replays them automatically.
func subscribe_chunks(chunks: Array) -> bool:
	var normalized := _normalize_chunks(chunks)
	if normalized.is_empty():
		return false
	_tracked_chunks = normalized
	if _authenticated:
		_send_subscribe_chunks()
	return true

func reset_error_window() -> void:
	_start_error_window(Time.get_ticks_msec())

func connect_to_server() -> void:
	# Each explicit Connect replaces the previous attempt, credentials, tracked
	# chunks and any recovery cycle in progress.
	_tracked_chunks = []
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
	_snapshots.reset()
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
			_report_invalid("packet_too_large")
			continue
		# JSON.new().parse() reports failure by code; parse_string would print an
		# engine error per bad packet and let a hostile peer flood the log.
		var json := JSON.new()
		var parsed = json.data if json.parse(packet.get_string_from_utf8()) == OK else null
		if not (parsed is Dictionary):
			_report_invalid("packet_not_json_object")
			continue
		if parsed.get("type", "") == "auth_ok":
			_on_authenticated()
		_dispatch(parsed)
		# A snapshot assembly error closes the socket: stop draining this connection.
		if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
			break

func _report_invalid(reason: String) -> void:
	# Every invalid packet is counted. At most MAX_ERROR_SIGNALS_PER_WINDOW
	# signals are raised per window, then one "errors_suppressed" summary.
	invalid_packet_count += 1
	var now := Time.get_ticks_msec()
	if now - _error_window_start_msec >= error_window_msec:
		_start_error_window(now)
	if _error_window_emitted < MAX_ERROR_SIGNALS_PER_WINDOW:
		_error_window_emitted += 1
		protocol_error.emit(reason)
		return
	suppressed_error_count += 1
	if not _error_window_summarised:
		_error_window_summarised = true
		protocol_error.emit("errors_suppressed")

func _start_error_window(now_msec: int) -> void:
	_error_window_start_msec = now_msec
	_error_window_emitted = 0
	_error_window_summarised = false

func _normalize_chunks(chunks: Array) -> Array:
	# Mirrors the server parser for subscribe_chunks; returns [] when invalid.
	if chunks.is_empty() or chunks.size() > MAX_CHUNK_SUBSCRIPTIONS:
		return []
	var result: Array = []
	for entry in chunks:
		if not (entry is Dictionary) or not entry.has("x") or not entry.has("y"):
			return []
		var x = entry["x"]
		var y = entry["y"]
		if not _is_chunk_coordinate(x) or not _is_chunk_coordinate(y):
			return []
		result.append({"x": int(x), "y": int(y)})
	return result

func _is_chunk_coordinate(value: Variant) -> bool:
	var kind := typeof(value)
	if kind != TYPE_INT and kind != TYPE_FLOAT:
		return false
	if kind == TYPE_FLOAT and (is_nan(value) or is_inf(value) or value != floorf(value)):
		return false
	return absf(float(value)) <= MAX_CHUNK_COORDINATE

func _send_subscribe_chunks() -> bool:
	_request_counter += 1
	var request := {
		"type": "subscribe_chunks",
		"requestId": "chunks-%d" % _request_counter,
		"chunks": _tracked_chunks,
	}
	if _socket.send_text(JSON.stringify(request)) != OK:
		status_changed.emit("Chunk subscription could not be sent")
		return false
	return true

func _on_authenticated() -> void:
	_authenticated = true
	if _reconnecting:
		_reconnecting = false
		_reconnect_attempt = 0
		status_changed.emit("Reconnected")
		reconnected.emit()
		# The server re-pushes player/creature/base state after auth; chunks must
		# be requested again by the client.
		if not _tracked_chunks.is_empty() and _send_subscribe_chunks():
			resync_requested.emit(_tracked_chunks.size())
	elif not _tracked_chunks.is_empty():
		# subscribe_chunks() was called before authentication completed.
		_send_subscribe_chunks()

func _handle_closed() -> void:
	_attempt_active = false
	# A partial creature snapshot can never be completed after the connection is lost.
	_snapshots.reset()
	if _deliberate_close:
		status_changed.emit("Disconnected")
		return
	var code := _socket.get_close_code()
	if code in NO_RECONNECT_CLOSE_CODES:
		_reconnecting = false
		_authenticated = false
		auth_failed.emit(_auth_failure_reason(_socket.get_close_reason()))
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

# Maps the server's close reason for a 1008 close to an explicit auth failure code.
# The server closes with "invalid_token" or "authentication_timeout" (app.ts); any
# other 1008 reason is reported as a generic policy violation.
func _auth_failure_reason(close_reason: String) -> String:
	match close_reason:
		"invalid_token":
			return "INVALID_TOKEN"
		"authentication_timeout":
			return "AUTH_TIMEOUT"
		_:
			return "POLICY_VIOLATION"

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

func _dispatch(message: Dictionary) -> void:
	var result: Dictionary = _snapshots.feed(message)
	match result["status"]:
		"ignored":
			message_received.emit(message)
		"complete":
			message_received.emit(result["message"])
		"error":
			# The server re-sends a fresh complete snapshot after every authentication, so a
			# broken snapshot is recovered by dropping the connection: an authenticated session
			# that closes this way is reconnected and resynchronised by the recovery logic above.
			_socket.close()
			status_changed.emit("Creature sync failed (%s); reconnect required" % result["reason"])
		_:
			pass # "partial": held back until the snapshot is complete

func _is_safe_authenticated_url(url: String) -> bool:
	var pattern := RegEx.new()
	# Match the entire authority: lookalike hosts and userinfo are never loopback.
	pattern.compile("^wss://[^/@?#\\s]+(?:/[^\\s]*)?$|^ws://(?:127\\.0\\.0\\.1|localhost|\\[::1\\])(?::[0-9]{1,5})?(?:/[^\\s]*)?$")
	return pattern.search(url) != null
