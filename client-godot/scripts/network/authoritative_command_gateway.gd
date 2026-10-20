class_name IslesAuthoritativeCommandGateway
extends "res://scripts/websocket_adapter.gd"

## Client presentation only; Fastify/PostgreSQL owns all gameplay state.
## Never automatically replay a mutation with an ambiguous outcome.
signal authenticated(user_id: String)
signal request_acknowledged(request_id: String, message: Dictionary)
signal request_outcome_unknown(request_id: String, reason: String)
signal server_error(code: String)

const MAX_PENDING := 32
const REQUEST_TIMEOUT_MS := 30000
const BLOCKED_ACTIONS := ["auth", "ping", "move", "dodge", "block", "select_hotbar"]

var _authenticated := false
var _pending: Dictionary = {}
var _crypto := Crypto.new()
var _action_pattern := RegEx.new()

func _ready() -> void:
	_action_pattern.compile("^[a-z][a-z0-9_]{0,63}$")
	message_received.connect(_on_protocol_message)

func connect_to_server() -> void:
	_clear_session("reconnect")
	super.connect_to_server()

func _process(delta: float) -> void:
	super._process(delta)
	if not _attempt_active and (_authenticated or not _pending.is_empty()):
		_clear_session("connection_lost")
	var now := Time.get_ticks_msec()
	for request_id in _pending.keys():
		if now - int(_pending[request_id]) >= REQUEST_TIMEOUT_MS:
			_pending.erase(request_id)
			request_outcome_unknown.emit(request_id, "reply_timeout")

func is_authenticated() -> bool:
	return _authenticated and _attempt_active and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func pending_count() -> int:
	return _pending.size()

func send_request(action: String, fields: Dictionary = {}) -> String:
	if not is_authenticated():
		return ""
	if _pending.size() >= MAX_PENDING:
		return ""
	if _action_pattern.search(action) == null or action in BLOCKED_ACTIONS:
		return ""
	if fields.has("type") or fields.has("requestId"):
		return ""
	var request_id := _crypto.generate_random_bytes(16).hex_encode()
	if request_id.is_empty() or _pending.has(request_id):
		return ""
	var message: Dictionary = fields.duplicate(true)
	message["type"] = action
	message["requestId"] = request_id
	# UI must wait for a correlated server acknowledgement before displaying success.
	var send_error := _socket.send_text(JSON.stringify(message))
	if send_error != OK:
		request_outcome_unknown.emit(request_id, "send_failed")
		return ""
	_pending[request_id] = Time.get_ticks_msec()
	return request_id

func _on_protocol_message(message: Dictionary) -> void:
	var message_type = message.get("type")
	if not message_type is String:
		return
	if message_type == "auth_ok":
		var user_id = message.get("userId")
		if _auth_sent and user_id is String and not user_id.is_empty():
			_authenticated = true
			authenticated.emit(user_id)
		return
	if message_type == "error":
		var code = message.get("code")
		if code is String:
			server_error.emit(code)
		# Generic server error has no requestId: never guess which mutation failed.
		return
	if not is_authenticated():
		return
	var request_id = message.get("requestId")
	if request_id is String and _pending.has(request_id):
		_pending.erase(request_id)
		request_acknowledged.emit(request_id, message)

func _clear_session(reason: String) -> void:
	_authenticated = false
	for request_id in _pending.keys():
		request_outcome_unknown.emit(request_id, reason)
	_pending.clear()
