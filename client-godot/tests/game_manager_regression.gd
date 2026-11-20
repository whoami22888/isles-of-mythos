extends RefCounted

const Protocol = preload("res://gameplay/vertical_slice_protocol.gd")


static func run(tree: SceneTree, check: Callable) -> void:
	var manager = tree.root.get_node_or_null("GameManager")
	check.call(manager != null, "GameManager autoload must be registered")
	if manager == null:
		return

	var state_events: Array[int] = []
	var resource_events: Array[Dictionary] = []
	var soft_wall_events: Array[int] = []
	var state_callback := func(new_state: int) -> void:
		state_events.append(new_state)
	var resource_callback := func(resource_type: String, amount: int) -> void:
		resource_events.append({"type": resource_type, "amount": amount})
	var soft_wall_callback := func() -> void:
		soft_wall_events.append(1)
	manager.state_changed.connect(state_callback)
	manager.resource_updated.connect(resource_callback)
	manager.soft_wall_reached.connect(soft_wall_callback)

	manager.set_game_state(GameManager.GameState.MENU)
	check.call(manager.set_game_state(GameManager.GameState.CINEMATIC), "GameManager must accept a valid cinematic state")
	check.call(manager.current_state == GameManager.GameState.CINEMATIC, "GameManager must expose the current state")
	check.call(state_events.size() == 1, "A real state transition must emit state_changed once")
	check.call(manager.set_game_state(GameManager.GameState.CINEMATIC), "Setting the current state again must be idempotent")
	check.call(state_events.size() == 1, "An idempotent state update must not emit a duplicate signal")
	check.call(not manager.set_game_state(99), "Unknown game states must be rejected")

	var protocol = Protocol.new()
	tree.root.add_child(protocol)
	check.call(manager.bind_protocol(protocol), "GameManager must bind to the existing authoritative protocol")
	check.call(protocol.is_connected("command_acknowledged", Callable(manager, "_on_command_acknowledged")), "GameManager must subscribe to authoritative command ACKs")

	protocol.player_state_received.emit({
		"inventory": {
			"resource.wood": 1000,
			"resource.steel": 5000000,
			"resource.food": 1000000,
			"resource.pearls": 4,
		},
		"gold": "750",
		"triumphBadges": "12",
	})
	check.call(manager.get_resource_amount("wood") == 1000, "Wood must come from the authoritative player_state snapshot")
	check.call(manager.get_resource_amount("steel") == 5000000, "Steel must map from the server inventory item id")
	check.call(manager.get_resource_amount("food") == 1000000, "Food must map from the server inventory item id")
	check.call(manager.get_resource_amount("pearls") == 4, "Pearls must map from the server inventory item id")
	check.call(manager.get_resource_amount("doubloons") == 750, "Doubloons must map from the server gold field")
	check.call(manager.get_resource_amount("triumph_badges") == 12, "Triumph badges must map from the server snapshot")
	check.call(manager.current_state == GameManager.GameState.OVERWORLD, "The first authoritative player state must leave MENU/CINEMATIC for OVERWORLD")
	check.call(resource_events.size() == 6, "The first authoritative snapshot must emit one update for each changed resource")

	var exposed_resources: Dictionary = manager.player_resources
	exposed_resources["wood"] = 999999
	check.call(manager.get_resource_amount("wood") == 1000, "The public resource snapshot must not expose mutable internal state")

	var resource_event_count := resource_events.size()
	check.call(not manager.modify_resource("wood", -500), "Client-side resource deltas must fail closed")
	check.call(manager.get_resource_amount("wood") == 1000, "A local delta must not mutate server-owned wood")
	check.call(resource_events.size() == resource_event_count, "A rejected local delta must not emit resource_updated")

	protocol.command_acknowledged.emit("gather-1", {
		"type": "resource_gathered",
		"state": {
			"inventory": {"resource.wood": 500},
			"gold": "750",
			"triumphBadges": "12",
		},
	})
	check.call(manager.get_resource_amount("wood") == 500, "A resource_gathered ACK must update the read-only projection")
	check.call(resource_events.size() == resource_event_count + 1, "Only the authoritative ACK must emit the wood resource update")
	check.call(resource_events.back().get("type") == "wood" and resource_events.back().get("amount") == 500, "resource_updated must report the authoritative new balance")

	check.call(not manager.check_citadel_soft_wall(16, 12), "Level 15 to 16 must block when both resource and badge paths are insufficient")
	check.call(soft_wall_events.size() == 1, "A blocked soft-wall preview must emit soft_wall_reached")
	check.call(not manager.check_citadel_soft_wall(16, 500), "A caller-supplied badge count must not override the authoritative snapshot")
	check.call(soft_wall_events.size() == 2, "A rejected badge override must remain a blocked preview")
	protocol.player_state_received.emit({
		"inventory": {
			"resource.wood": 500,
			"resource.steel": 0,
			"resource.food": 0,
			"resource.pearls": 4,
		},
		"gold": "750",
		"triumphBadges": "500",
	})
	check.call(manager.check_citadel_soft_wall(16, 500), "The 500-badge path must pass only after the authoritative snapshot confirms it")
	check.call(manager.check_citadel_soft_wall(15, 0), "The earlier citadel levels must not be blocked by the level-16 soft wall")
	check.call(not manager.check_citadel_soft_wall(17, 500), "Unspecified levels beyond the defined soft wall must fail closed")

	protocol.player_state_received.emit({
		"inventory": {
			"resource.wood": 5000000,
			"resource.steel": 5000000,
			"resource.food": 1000000,
		},
		"gold": "750",
		"triumphBadges": "12",
	})
	check.call(manager.check_citadel_soft_wall(16, 12), "The resource path must satisfy the level-16 soft-wall preview")

	manager.set_game_state(GameManager.GameState.BASE_BUILD)
	protocol.player_state_received.emit({"inventory": {"resource.wood": 5000000}})
	check.call(manager.current_state == GameManager.GameState.BASE_BUILD, "A player snapshot must not overwrite an active non-menu game mode")

	var replacement_protocol = Protocol.new()
	tree.root.add_child(replacement_protocol)
	check.call(manager.bind_protocol(replacement_protocol), "Rebinding must replace the previous protocol connection")
	protocol.player_state_received.emit({"inventory": {"resource.wood": 9000}})
	check.call(manager.get_resource_amount("wood") == 5000000, "The previous protocol must be disconnected after rebinding")
	replacement_protocol.player_state_received.emit({"inventory": {"resource.wood": 750}})
	check.call(manager.get_resource_amount("wood") == 750, "The replacement protocol must drive the resource projection")

	check.call(manager.bind_protocol(null), "The GameManager protocol binding must be safely releasable")
	manager.state_changed.disconnect(state_callback)
	manager.resource_updated.disconnect(resource_callback)
	manager.soft_wall_reached.disconnect(soft_wall_callback)
	protocol.queue_free()
	replacement_protocol.queue_free()
