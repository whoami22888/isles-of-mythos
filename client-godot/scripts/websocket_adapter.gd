class_name IslesWebSocketAdapter
extends Node

signal status_changed(status: String)
signal message_received(message: Dictionary)

const SnapshotAssembler = preload("res://scripts/creature_snapshot_assembler.gd")

var _socket := WebSocketPeer.new()
# MYTHOS-NET-05: paginated creature snapshots are reassembled here, so consumers of
# message_received only ever see ONE complete `creature_party`, never a partial page.
var _snapshots := SnapshotAssembler.new()
var _url := ""
var _token := ""
var _attempt_active := false
var _auth_sent := false

func configure(url: String, token: String) -> void:
	_url = url.strip_edges()
	_token = token

func connect_to_server() -> void:
	# Each explicit Connect replaces the previous attempt and its credentials.
	_socket.close()
	_socket = WebSocketPeer.new()
	_attempt_active = false
	_auth_sent = false
	_snapshots.reset()
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
				_dispatch(parsed)
				if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
					break
	elif state == WebSocketPeer.STATE_CLOSED:
		_attempt_active = false
		# A partial snapshot can never be completed after the connection is lost.
		_snapshots.reset()
		status_changed.emit("Disconnected" if _auth_sent else "Connection failed; check endpoint and server availability")

func _dispatch(message: Dictionary) -> void:
	var result: Dictionary = _snapshots.feed(message)
	match result["status"]:
		"ignored":
			message_received.emit(message)
		"complete":
			message_received.emit(result["message"])
		"error":
			# The server re-sends a fresh complete snapshot after every authentication, so a
			# broken snapshot is recovered by dropping the connection and reconnecting.
			_socket.close()
			status_changed.emit("Creature sync failed (%s); reconnect required" % result["reason"])
		_:
			pass # "partial": held back until the snapshot is complete

func _is_safe_authenticated_url(url: String) -> bool:
	var pattern := RegEx.new()
	# Match the entire authority: lookalike hosts and userinfo are never loopback.
	pattern.compile("^wss://[^/@?#\\s]+(?:/[^\\s]*)?$|^ws://(?:127\\.0\\.0\\.1|localhost|\\[::1\\])(?::[0-9]{1,5})?(?:/[^\\s]*)?$")
	return pattern.search(url) != null
