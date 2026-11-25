extends Node3D

## Server-authoritative vessel proxy. Heading intents go through the authenticated
## command gateway; only server snapshots move the node. VFX and shake are presentation.

signal heading_intent_sent(request_id: String, dx: float, dy: float)
signal fire_requested(request_id: String, target_ship_id: String)
signal broadside_fired(side: String, event_id: String)
signal broadside_cooldown_started(duration_ms: int)
signal hit_stop_started

const SNAPSHOT_BLEND := 14.0
const SHAKE_DURATION := 0.18
const SHAKE_STRENGTH := 0.12
const DEFAULT_COOLDOWN_MS := 1000
const BroadsideFxScript = preload("res://scripts/naval_broadside_fx.gd")

var ship_id := ""
var _gateway: Node
var _fx: Node3D
var _camera: Camera3D
var _has_snapshot := false
var _server_position := Vector3.ZERO
var _server_heading := 0.0
var _visual_heading := 0.0
var _cooldown_ends_ms := 0
var _seen_events: Dictionary = {}
var _shake_remaining := 0.0
var _camera_base := Vector3.ZERO

func _ready() -> void:
	_fx = BroadsideFxScript.new()
	_fx.name = "BroadsideFx"
	add_child(_fx)
	_ensure_fallback_hull()

func bind_gateway(gateway: Node) -> void:
	_gateway = gateway if is_instance_valid(gateway) else null

func bind_camera(camera: Camera3D) -> void:
	_camera = camera if is_instance_valid(camera) else null
	if is_instance_valid(_camera):
		_camera_base = _camera.position

func apply_authoritative_ship(state: Dictionary) -> bool:
	var id_value: Variant = state.get("id", state.get("shipId", ship_id))
	if id_value is String and not id_value.is_empty():
		if not ship_id.is_empty() and ship_id != id_value:
			return false
		ship_id = id_value
	var x: Variant = state.get("x")
	var y: Variant = state.get("y")
	if not ((x is float or x is int) and (y is float or y is int)):
		return false
	if not is_finite(float(x)) or not is_finite(float(y)):
		return false
	var heading_value: Variant = state.get("heading", _server_heading)
	if not (heading_value is float or heading_value is int) or not is_finite(float(heading_value)):
		return false
	_server_position = Vector3(float(x), position.y, float(y))
	_server_heading = float(heading_value)
	if not _has_snapshot:
		position = _server_position
		_visual_heading = _server_heading
		rotation.y = -_visual_heading
	_has_snapshot = true
	return true

func send_heading_intent(dx: float, dy: float) -> String:
	if not _has_snapshot or ship_id.is_empty() or not is_instance_valid(_gateway):
		return ""
	if not _gateway.has_method("send_request"):
		return ""
	var request_id: Variant = _gateway.call("send_request", "sail", {"shipId": ship_id, "dx": dx, "dy": dy})
	if not (request_id is String) or request_id.is_empty():
		return ""
	heading_intent_sent.emit(request_id, dx, dy)
	return request_id

func request_fire_cannon(target_ship_id: String) -> String:
	if not _has_snapshot or ship_id.is_empty() or target_ship_id.is_empty() or not is_instance_valid(_gateway):
		return ""
	if not _gateway.has_method("send_request"):
		return ""
	var request_id: Variant = _gateway.call("send_request", "fire_cannon", {"shipId": ship_id, "targetShipId": target_ship_id})
	if not (request_id is String) or request_id.is_empty():
		return ""
	fire_requested.emit(request_id, target_ship_id)
	return request_id

func apply_naval_combat_result(message: Dictionary) -> bool:
	var event_id := _event_id(message)
	if event_id.is_empty() or _seen_events.has(event_id):
		return false
	_seen_events[event_id] = true
	var side := str(message.get("side", "port"))
	if side != "port" and side != "starboard":
		side = "port"
	if is_instance_valid(_fx) and _fx.has_method("play_fire"):
		_fx.call("play_fire", side)
		_fx.call("play_impact")
	var cooldown: Variant = message.get("cooldownMs", DEFAULT_COOLDOWN_MS)
	var cooldown_ms := DEFAULT_COOLDOWN_MS
	if cooldown is int or cooldown is float:
		cooldown_ms = maxi(0, int(cooldown))
	_cooldown_ends_ms = Time.get_ticks_msec() + cooldown_ms
	_shake_remaining = SHAKE_DURATION
	broadside_fired.emit(side, event_id)
	broadside_cooldown_started.emit(cooldown_ms)
	hit_stop_started.emit()
	return true

func broadside_cooldown_remaining_ms() -> int:
	return maxi(0, _cooldown_ends_ms - Time.get_ticks_msec())

func has_server_snapshot() -> bool:
	return _has_snapshot

func _process(delta: float) -> void:
	if _has_snapshot:
		var weight := 1.0 - exp(-SNAPSHOT_BLEND * maxf(delta, 0.0))
		position = position.lerp(_server_position, weight)
		_visual_heading = lerp_angle(_visual_heading, _server_heading, weight)
		rotation.y = -_visual_heading
	if _shake_remaining > 0.0 and is_instance_valid(_camera):
		_shake_remaining = maxf(0.0, _shake_remaining - delta)
		var envelope := _shake_remaining / SHAKE_DURATION
		var offset := Vector3(
			sin(Time.get_ticks_msec() * 0.08) * SHAKE_STRENGTH * envelope,
			cos(Time.get_ticks_msec() * 0.11) * SHAKE_STRENGTH * 0.5 * envelope,
			0.0
		)
		_camera.position = _camera_base + offset
		if _shake_remaining == 0.0:
			_camera.position = _camera_base

func _event_id(message: Dictionary) -> String:
	var request_id: Variant = message.get("requestId")
	if request_id is String and not request_id.is_empty():
		return request_id
	var damage: Variant = message.get("damage", "")
	var side: Variant = message.get("side", "")
	return "%s:%s:%s" % [str(ship_id), str(damage), str(side)]

func _ensure_fallback_hull() -> void:
	if not find_children("*", "MeshInstance3D", true, false).is_empty():
		return
	var hull := MeshInstance3D.new()
	hull.name = "FallbackHull"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.4, 0.8, 6.0)
	hull.mesh = mesh
	add_child(hull)
