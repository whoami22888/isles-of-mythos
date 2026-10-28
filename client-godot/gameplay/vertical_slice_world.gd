extends Node3D

const Protocol = preload("res://gameplay/vertical_slice_protocol.gd")
var _client: Node
var _player := Vector3.ZERO
var _markers: Dictionary = {}
var _status: Label
var _state: Label
var _gather: Button
var _endpoint: LineEdit
var _token: LineEdit
var _connect_button: Button
var _handoff_endpoint := ""
var _handoff_token := ""
# Mirrors server CHUNK_SIZE (server/src/world.ts); display/request hint only.
const CHUNK_SIZE := 32.0
# Server gather range is 2.5 units (server/src/app.ts); stop short of it. The
# server still validates every gather, this only decides when to send intent.
const GATHER_APPROACH_DISTANCE := 2.0
const MOVE_INTERVAL_SECONDS := 0.08
# Chunk snapshots are not pushed, so re-read the authoritative chunk on a
# bounded schedule (respawns are 45-90 s) with at most one request in flight.
const CHUNK_REFRESH_SECONDS := 10.0
var _chunk := Vector2i.ZERO
var _chunk_known := false
var _chunk_in_flight := ""
var _refresh_clock := 0.0
var _approaching := false
var _approach_target := ""
var _move_clock := 0.0

func begin_authenticated_session(endpoint: String, token: String) -> void:
	_handoff_endpoint = endpoint
	_handoff_token = token

func _ready() -> void:
	_status = $Interface/Panel/Margin/Content/Status
	_state = $Interface/Panel/Margin/Content/State
	_gather = $Interface/Panel/Margin/Content/Gather
	_endpoint = $Interface/Panel/Margin/Content/Endpoint
	_token = $Interface/Panel/Margin/Content/Token
	_connect_button = $Interface/Panel/Margin/Content/Connect
	_gather.pressed.connect(_gather_nearest)
	_connect_button.pressed.connect(_connect)
	_build_scaffold_world()
	_client = Protocol.new()
	add_child(_client)
	_client.status_changed.connect(_on_transport_status)
	_client.authenticated.connect(_on_authenticated)
	_client.player_state_received.connect(_on_player_state)
	_client.world_chunk_received.connect(_on_world_chunk)
	_client.command_acknowledged.connect(_on_ack)
	_client.server_rejected.connect(_on_rejection)
	_client.command_outcome_unknown.connect(_on_outcome_unknown)
	var endpoint := OS.get_environment("IOM_WS_URL")
	if endpoint.is_empty():
		endpoint = ProjectSettings.get_setting("application/config/default_ws_url", "ws://127.0.0.1:3000/ws")
	_endpoint.text = endpoint
	_token.text = OS.get_environment("IOM_AUTH_TOKEN")
	if not _handoff_token.is_empty():
		_endpoint.text = _handoff_endpoint
		_token.text = ""
		_token.hide()
		# Keep the only recovery control; it reuses the in-memory session and
		# never displays the JWT.
		_connect_button.text = "Reconnect"
		_connect()
	elif not _token.text.is_empty():
		_connect()
	else:
		_status.text = "Enter a JWT token; this slice has no local authority"

func _connect() -> void:
	_client.configure(_handoff_endpoint if not _handoff_token.is_empty() else _endpoint.text,
		_handoff_token if not _handoff_token.is_empty() else _token.text)
	_client.connect_to_server()

func _build_scaffold_world() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(64, 64)
	ground.mesh = plane
	ground.material_override = _material(Color("#183b3a"))
	add_child(ground)
	var player := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	player.mesh = capsule
	player.material_override = _material(Color("#d9a441"))
	player.name = "ServerPlayerRepresentation"
	add_child(player)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.2
	add_child(light)
	var camera: Camera3D = $Camera
	camera.look_at_from_position(Vector3(0, 28, 24), Vector3.ZERO)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material

func _on_transport_status(status: String) -> void:
	_status.text = status

func _on_authenticated(_user_id: String) -> void:
	_status.text = "Authenticated; awaiting server player position…"
	# The chunk is requested once the server reports where the player is.
	_chunk_known = false
	_chunk_in_flight = ""
	_refresh_clock = 0.0
	_stop_approach()

func _chunk_for_position(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / CHUNK_SIZE), floori(position.z / CHUNK_SIZE))

func _request_current_chunk() -> void:
	if not _chunk_in_flight.is_empty():
		return
	var chunk := _chunk_for_position(_player)
	var request_id: String = _client.request_world_chunk(chunk.x, chunk.y)
	if request_id.is_empty():
		return
	_chunk = chunk
	_chunk_known = true
	_chunk_in_flight = request_id
	_refresh_clock = 0.0

func _process(delta: float) -> void:
	if _client == null or not _client.is_authenticated():
		_stop_approach()
		return
	_refresh_clock += delta
	if _chunk_known and _refresh_clock >= CHUNK_REFRESH_SECONDS:
		_refresh_clock = 0.0
		_request_current_chunk()
	if _approaching:
		_move_clock += delta
		if _move_clock >= MOVE_INTERVAL_SECONDS:
			_move_clock = 0.0
			_approach_step()

func _stop_approach() -> void:
	_approaching = false
	_approach_target = ""

## One step of "walk to the target, then gather". Movement is only the existing
## server `move` intent; the server computes the position and the client keeps
## walking until the server-reported position is within gather range.
func _approach_step() -> void:
	if not _approaching:
		return
	if not _client.is_authenticated() or not _markers.has(_approach_target):
		_stop_approach()
		return
	var marker: Node3D = _markers[_approach_target]
	var offset := Vector2(marker.position.x - _player.x, marker.position.z - _player.z)
	if offset.length() <= GATHER_APPROACH_DISTANCE:
		var target := _approach_target
		_stop_approach()
		_send_gather(target)
		return
	var direction := offset.normalized()
	_client.request_move(direction.x, direction.y)

func _on_player_state(state: Dictionary) -> void:
	var x = state.get("x")
	var y = state.get("y")
	if x is int or x is float:
		var world_y = y if y is int or y is float else 0
		_player = Vector3(float(x), 0.9, float(world_y))
		$ServerPlayerRepresentation.position = _player
		_state.text = "Server player position: (%d, %d)" % [int(_player.x), int(_player.z)]
		# Follow the authoritative position: request the chunk containing the
		# player on first state and whenever the player crosses a boundary.
		if _client.is_authenticated() and (not _chunk_known or _chunk_for_position(_player) != _chunk):
			_chunk_in_flight = ""
			_request_current_chunk()

func _on_world_chunk(request_id: String, chunk: Dictionary) -> void:
	if request_id == _chunk_in_flight:
		_chunk_in_flight = ""
	# Ignore snapshots for a chunk the player is no longer in.
	var chunk_x = chunk.get("x")
	var chunk_y = chunk.get("y")
	if (chunk_x is int or chunk_x is float) and (chunk_y is int or chunk_y is float):
		if _chunk_known and Vector2i(int(chunk_x), int(chunk_y)) != _chunk:
			return
	_status.text = "Authoritative world chunk received"
	var current_ids: Dictionary = {}
	for resource in chunk.get("resources", []):
		if not resource is Dictionary:
			continue
		var resource_id = resource.get("id")
		if not resource_id is String:
			continue
		current_ids[resource_id] = true
		var marker: MeshInstance3D
		if _markers.has(resource_id):
			marker = _markers[resource_id]
		else:
			marker = _create_resource_marker(resource_id)
		marker.position = Vector3(float(resource.get("x", 0)), 0.3, float(resource.get("y", 0)))
	# The server's chunk snapshot is authoritative: remove resources no longer
	# present, including depleted nodes, without retaining orphaned MeshInstances.
	for resource_id in _markers.keys():
		if not current_ids.has(resource_id):
			_markers[resource_id].queue_free()
			_markers.erase(resource_id)

func _create_resource_marker(resource_id: String) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	marker.mesh = sphere
	marker.material_override = _material(Color("#67d4a3"))
	marker.name = "ServerResource_" + resource_id.replace(":", "_")
	add_child(marker)
	_markers[resource_id] = marker
	return marker

func _gather_nearest() -> void:
	if _markers.is_empty():
		_status.text = "No server-visible resource in this chunk"
		return
	var nearest_id := ""
	var nearest_distance := INF
	for resource_id in _markers:
		var marker: Node3D = _markers[resource_id]
		var distance := marker.position.distance_to(_player)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = resource_id
	if not _client.is_authenticated():
		_status.text = "Authenticate before issuing a server command"
		return
	var marker_position: Vector3 = _markers[nearest_id].position
	if Vector2(marker_position.x - _player.x, marker_position.z - _player.z).length() > GATHER_APPROACH_DISTANCE:
		_approaching = true
		_approach_target = nearest_id
		_move_clock = MOVE_INTERVAL_SECONDS
		_status.text = "Moving toward resource; server validates position"
		return
	_send_gather(nearest_id)

func _send_gather(nearest_id: String) -> void:
	var request_id: String = _client.request_gather(nearest_id)
	_status.text = "Awaiting server gather ACK (%s)" % request_id if not request_id.is_empty() else "Command window unavailable"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_gather_nearest()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_gather_nearest()

func _on_ack(_request_id: String, message: Dictionary) -> void:
	if message.get("type") == "resource_gathered":
		var resource_id = message.get("resourceId")
		if resource_id is String and _markers.has(resource_id):
			_markers[resource_id].queue_free()
			_markers.erase(resource_id)
		_status.text = "Server ACK: resource persisted; local view refreshed"
		var state = message.get("state")
		if state is Dictionary:
			_state.text = "Authoritative inventory state received"

func _on_rejection(code: String) -> void:
	_status.text = "Server rejected command: %s" % code

func _on_outcome_unknown(request_id: String) -> void:
	if request_id == _chunk_in_flight:
		_chunk_in_flight = ""
	_status.text = "Command outcome unknown; reconnect manually before retrying"
