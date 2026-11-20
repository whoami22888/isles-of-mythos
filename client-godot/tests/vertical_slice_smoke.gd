extends SceneTree

const SCENE_PATH := "res://gameplay/vertical_slice.tscn"
const Protocol = preload("res://gameplay/vertical_slice_protocol.gd")
const PlayerControllerRegression = preload("res://tests/player_controller_regression.gd")

func _init() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("vertical slice scene failed to load")
		quit(1)
		return
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	var player = instance.get_node_or_null("ServerPlayerRepresentation")
	_assert(player != null, "server player representation")
	_assert(player is CharacterBody3D, "server player representation must use the CharacterBody3D controller")
	_assert(player.has_method("apply_authoritative_state") and player.has_method("request_move_intent"), "server player must expose authoritative state and movement intent APIs")
	_assert(instance.get_node_or_null("Interface/Panel/Margin/Content/Connect") != null, "connect control")
	_assert(instance.get_node_or_null("Interface/Panel/Margin/Content/Gather") != null, "gather control")
	var has_protocol := false
	for child in instance.get_children():
		if child is Protocol:
			has_protocol = true
	_assert(has_protocol, "protocol client")
	PlayerControllerRegression.run(root, Callable(self, "_assert"))
	instance.queue_free()
	await process_frame
	quit(0)

func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("vertical slice smoke failed: " + label)
		quit(1)
