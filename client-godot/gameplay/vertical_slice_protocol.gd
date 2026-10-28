class_name IslesVerticalSliceProtocol
extends "res://scripts/websocket_adapter.gd"

## Non-premium vertical-slice transport. The server owns all player, world and
## inventory state; this client only renders server messages and waits for ACKs.
signal authenticated(user_id: String)
signal player_state_received(state: Dictionary)
signal world_chunk_received(request_id: String, chunk: Dictionary)
signal command_acknowledged(request_id: String, message: Dictionary)
signal server_rejected(code: String)
signal command_outcome_unknown(request_id: String)

const MAX_PENDING := 8
var _authenticated := false
var _pending: Dictionary = {}
var _crypto := Crypto.new()
## Movement intents carry a strictly increasing sequence. Seeding from the wall
## clock in milliseconds keeps it above any sequence a previous run could have
## sent (<= 40 packets/s) so the server never sees a duplicate after restart.
var _move_sequence: int = int(Time.get_unix_time_from_system() * 1000.0)

func _process(_delta: float) -> void:
	var was_open: bool = _attempt_active and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN
	super._process(_delta)
	if was_open and not _attempt_active:
		_clear_pending_as_unknown()
		_authenticated = false
	# A durable command must never be replayed after a timeout or disconnect.
	# Expire only the local correlation entry and surface the ambiguity.
	var expired: Array[String] = []
	var now_ms: int = Time.get_ticks_msec()
	for request_id in _pending:
		if now_ms - int(_pending[request_id]["started_ms"]) >= 30000:
			expired.append(request_id)
	for request_id in expired:
		_pending.erase(request_id)
		command_outcome_unknown.emit(request_id)

func _ready() -> void:
	message_received.connect(_on_message)

func connect_to_server() -> void:
	_authenticated = false
	_clear_pending_as_unknown()
	super.connect_to_server()

func _clear_pending_as_unknown() -> void:
	var pending_ids: Array[String] = []
	for request_id in _pending:
		pending_ids.append(request_id)
	_pending.clear()
	for request_id in pending_ids:
		command_outcome_unknown.emit(request_id)

func is_authenticated() -> bool:
	return _authenticated and _attempt_active and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func request_world_chunk(chunk_x: int, chunk_y: int) -> String:
	return _send_request("subscribe_chunks", {"chunks": [{"x": chunk_x, "y": chunk_y}]})

func request_gather(resource_id: String) -> String:
	return _send_request("gather_resource", {"resourceId": resource_id})

## Sends the existing server `move` intent (direction only, no request ID, no
## client-supplied time or speed). The server alone computes the new position.
func request_move(dx: float, dy: float) -> bool:
	if not is_authenticated() or not is_finite(dx) or not is_finite(dy):
		return false
	_move_sequence += 1
	var message := {"type": "move", "dx": clampf(dx, -1.0, 1.0), "dy": clampf(dy, -1.0, 1.0), "sequence": _move_sequence}
	return _socket.send_text(JSON.stringify(message)) == OK

func _send_request(action: String, fields: Dictionary) -> String:
	if not is_authenticated() or _pending.size() >= MAX_PENDING:
		return ""
	if action != "subscribe_chunks" and action != "gather_resource":
		return ""
	var request_id := _crypto.generate_random_bytes(16).hex_encode()
	if request_id.is_empty() or _pending.has(request_id):
		return ""
	var message: Dictionary = fields.duplicate(true)
	message["type"] = action
	message["requestId"] = request_id
	if _socket.send_text(JSON.stringify(message)) != OK:
		return ""
	_pending[request_id] = {"action": action, "started_ms": Time.get_ticks_msec()}
	return request_id

func _on_message(message: Dictionary) -> void:
	var message_type = message.get("type")
	if not message_type is String:
		return
	if message_type == "auth_ok":
		var user_id = message.get("userId")
		if _auth_sent and user_id is String and not user_id.is_empty():
			_authenticated = true
			authenticated.emit(user_id)
		return
	if message_type == "player_state":
		var state = message.get("state")
		if state is Dictionary:
			player_state_received.emit(state)
		return
	if message_type == "world_chunk":
		var request_id = message.get("requestId")
		var chunk = message.get("chunk")
		if request_id is String and chunk is Dictionary and _pending_action_matches(request_id, "subscribe_chunks"):
			_pending.erase(request_id)
			world_chunk_received.emit(request_id, chunk)
			command_acknowledged.emit(request_id, message)
		return
	if message_type == "resource_gathered":
		var gather_id = message.get("requestId")
		if gather_id is String and _pending_action_matches(gather_id, "gather_resource"):
			_pending.erase(gather_id)
			command_acknowledged.emit(gather_id, message)
		return
	if message_type == "error":
		var code = message.get("code")
		if code is String and not code.is_empty():
			# Current server errors carry no request ID. Never guess which durable
			# request they reject; the pending request remains outcome-unknown.
			server_rejected.emit(code)

func _pending_action_matches(request_id: String, expected_action: String) -> bool:
	if not _pending.has(request_id):
		return false
	var pending = _pending[request_id]
	return pending is Dictionary and pending.get("action") == expected_action
