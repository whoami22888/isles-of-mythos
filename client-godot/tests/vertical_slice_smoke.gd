extends SceneTree

const SCENE_PATH := "res://gameplay/vertical_slice.tscn"
const Protocol = preload("res://gameplay/vertical_slice_protocol.gd")

func _init() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("vertical slice scene failed to load")
		quit(1)
		return
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	_assert(instance.get_node_or_null("ServerPlayerRepresentation") != null, "server player representation")
	_assert(instance.get_node_or_null("Interface/Panel/Margin/Content/Connect") != null, "connect control")
	_assert(instance.get_node_or_null("Interface/Panel/Margin/Content/Gather") != null, "gather control")
	var has_protocol := false
	for child in instance.get_children():
		if child is Protocol:
			has_protocol = true
	_assert(has_protocol, "protocol client")
	instance.queue_free()
	await process_frame
	quit(0)

func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("vertical slice smoke failed: " + label)
		quit(1)
