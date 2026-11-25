extends SceneTree

const Protocol = preload("res://gameplay/vertical_slice_protocol.gd")

var _acks: Array[String] = []
var _unknown: Array[String] = []
var _combat_results: Array[Dictionary] = []
var _projectile_spawns: Array[Dictionary] = []

func _init() -> void:
	var protocol = Protocol.new()
	root.add_child(protocol)
	protocol.command_acknowledged.connect(func(request_id: String, _message: Dictionary): _acks.append(request_id))
	protocol.command_outcome_unknown.connect(func(request_id: String): _unknown.append(request_id))
	protocol.combat_result_received.connect(func(message: Dictionary): _combat_results.append(message))
	protocol.projectile_spawn_received.connect(func(message: Dictionary): _projectile_spawns.append(message))

	protocol._pending["chunk-1"] = {"action": "subscribe_chunks", "started_ms": Time.get_ticks_msec()}
	protocol._on_message({"type": "resource_gathered", "requestId": "chunk-1"})
	_assert(protocol._pending.has("chunk-1"), "wrong response type cannot clear chunk request")
	_assert(_acks.is_empty(), "wrong response type cannot ACK")
	protocol._on_message({"type": "world_chunk", "requestId": "chunk-1", "chunk": {"resources": []}})
	_assert(not protocol._pending.has("chunk-1"), "matching chunk ACK clears request")
	_assert(_acks == ["chunk-1"], "matching chunk ACK recorded once")
	protocol._on_message({"type": "world_chunk", "requestId": "chunk-1", "chunk": {"resources": []}})
	_assert(_acks == ["chunk-1"], "duplicate ACK ignored")

	protocol._pending["gather-1"] = {"action": "gather_resource", "started_ms": Time.get_ticks_msec()}
	protocol._on_message({"type": "world_chunk", "requestId": "gather-1", "chunk": {"resources": []}})
	_assert(protocol._pending.has("gather-1"), "wrong out-of-order response preserves gather request")
	protocol._on_message({"type": "resource_gathered", "requestId": "stale-id"})
	_assert(protocol._pending.has("gather-1"), "stale request ID ignored")
	protocol._on_message({"type": "resource_gathered", "requestId": "gather-1"})
	_assert(not protocol._pending.has("gather-1"), "matching gather ACK clears request")
	_assert(_acks == ["chunk-1", "gather-1"], "out-of-order matching ACK recorded")

	protocol._pending["disconnect-1"] = {"action": "gather_resource", "started_ms": Time.get_ticks_msec()}
	protocol._clear_pending_as_unknown()
	_assert(protocol._pending.is_empty(), "disconnect clears pending correlation")
	_assert(_unknown == ["disconnect-1"], "disconnect reports ambiguous outcome")
	_assert(not protocol.request_move(1.0, 0.0), "move intent is refused while unauthenticated")
	_assert(not protocol.request_move(INF, 0.0), "non-finite move intent is refused")
	_assert(not protocol.request_select_hotbar(0), "hotbar selection is refused while unauthenticated")
	_assert(not protocol.request_select_hotbar(-1) and not protocol.request_select_hotbar(8), "hotbar slot bounds are enforced")
	_assert(protocol.request_attack("creature:1:2", Vector2.RIGHT).is_empty(),
		"combat intent is refused while unauthenticated")
	var attack_message := Protocol.build_attack_message("creature:12:-4", Vector2(3.0, 4.0), "attack-1")
	_assert(attack_message.get("type") == "attack" and attack_message.get("targetId") == "creature:12:-4",
		"combat intent uses the existing server attack contract")
	_assert(is_equal_approx(float(attack_message.get("facingX", 0.0)), 0.6)
		and is_equal_approx(float(attack_message.get("facingY", 0.0)), 0.8),
		"combat facing is normalized before it reaches the server")
	_assert(Protocol.build_attack_message("resource:1:2", Vector2.RIGHT, "attack-2").is_empty(),
		"combat target must be a server creature identifier")
	_assert(Protocol.build_attack_message("creature:1:2", Vector2.ZERO, "attack-3").is_empty(),
		"zero facing cannot be sent to the server")
	_assert(Protocol.build_attack_message("creature:1:2", Vector2(INF, 0.0), "attack-4").is_empty(),
		"non-finite facing cannot be sent to the server")
	protocol._on_message({"type": "combat_result", "requestId": "attack-1", "targetId": "creature:12:-4", "damage": 20})
	protocol._on_message({"type": "projectile_spawn", "projectileId": "projectile:test:1", "targetId": "creature:12:-4"})
	_assert(_combat_results.size() == 1 and _combat_results[0].get("requestId") == "attack-1",
		"server combat results are surfaced without client-side damage prediction")
	_assert(_projectile_spawns.size() == 1 and _projectile_spawns[0].get("targetId") == "creature:12:-4",
		"server projectile launches are surfaced to the client")
	protocol.queue_free()
	await process_frame
	quit(0)

func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("protocol regression failed: " + label)
		quit(1)
