extends SceneTree

const Protocol = preload("res://gameplay/vertical_slice_protocol.gd")

var _acks: Array[String] = []
var _unknown: Array[String] = []

func _init() -> void:
	var protocol = Protocol.new()
	root.add_child(protocol)
	protocol.command_acknowledged.connect(func(request_id: String, _message: Dictionary): _acks.append(request_id))
	protocol.command_outcome_unknown.connect(func(request_id: String): _unknown.append(request_id))

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
	protocol.queue_free()
	await process_frame
	quit(0)

func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("protocol regression failed: " + label)
		quit(1)
