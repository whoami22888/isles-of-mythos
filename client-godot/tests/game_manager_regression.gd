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
			"inventory": {
				"resource.wood": 500,
				"resource.steel": 5000000,
				"resource.food": 1000000,
				"resource.pearls": 4,
			},
			"gold": "750",
			"triumphBadges": "12",
		},
	})
	check.call(manager.get_resource_amount("wood") == 500, "A resource_gathered ACK must update the read-only projection")
	check.call(resource_events.size() == resource_event_count + 1, "Only the authoritative ACK must emit the wood resource update")
	check.call(resource_events.back().get("type") == "wood" and resource_events.back().get("amount") == 500, "resource_updated must report the authoritative new balance")
	check.call(manager.get_resource_amount("steel") == 5000000 and manager.get_resource_amount("food") == 1000000 and manager.get_resource_amount("pearls") == 4, "A full gather ACK snapshot must preserve unrelated authoritative balances")

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
	check.call(manager.check_citadel_soft_wall(16, 0), "A stale lower caller badge count must not veto the authoritative 500-badge path")
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

	# A later resync snapshot on the same protocol must refresh balances without
	# forcing a cinematic that began after initial login back to OVERWORLD.
	manager.set_game_state(GameManager.GameState.CINEMATIC)
	protocol.player_state_received.emit({"inventory": {"resource.wood": 5000000}})
	check.call(manager.current_state == GameManager.GameState.CINEMATIC, "A reconnect/resync snapshot must preserve a later cinematic state")

	var replacement_protocol = Protocol.new()
	tree.root.add_child(replacement_protocol)
	check.call(manager.bind_protocol(replacement_protocol), "Rebinding must replace the previous protocol connection")
	for resource_type in manager.RESOURCE_KEYS:
		check.call(manager.get_resource_amount(resource_type) == 0, "A new protocol session must not inherit the previous account's %s projection" % resource_type)
	protocol.player_state_received.emit({"inventory": {"resource.wood": 9000}})
	check.call(manager.get_resource_amount("wood") == 0, "The previous protocol must be disconnected after rebinding")
	replacement_protocol.player_state_received.emit({"inventory": {"resource.wood": 750}})
	check.call(manager.get_resource_amount("wood") == 750, "The replacement protocol must drive the resource projection")
	check.call(manager.current_state == GameManager.GameState.OVERWORLD, "The first snapshot on a new protocol must perform its one-time initial state transition")

	# The one-shot guard is per protocol binding, not per socket connection.
	manager.set_game_state(GameManager.GameState.CINEMATIC)
	replacement_protocol.player_state_received.emit({"inventory": {"resource.wood": 625}})
	check.call(manager.get_resource_amount("wood") == 625, "A later snapshot must still update the authoritative resource projection")
	check.call(manager.current_state == GameManager.GameState.CINEMATIC, "A later snapshot on the same protocol must not overwrite CINEMATIC")

	# An invalid candidate must not disconnect the currently working protocol.
	var invalid_protocol := Node.new()
	tree.root.add_child(invalid_protocol)
	check.call(not manager.bind_protocol(invalid_protocol), "A replacement without the required authoritative signals must be rejected")
	check.call(replacement_protocol.is_connected("player_state_received", Callable(manager, "_on_player_state_received")), "Rejecting an invalid replacement must preserve the active player-state connection")
	check.call(replacement_protocol.is_connected("command_acknowledged", Callable(manager, "_on_command_acknowledged")), "Rejecting an invalid replacement must preserve the active ACK connection")
	replacement_protocol.player_state_received.emit({"inventory": {"resource.wood": 600}})
	check.call(manager.get_resource_amount("wood") == 600, "The active protocol must continue updating the projection after an invalid replacement")
	check.call(manager.current_state == GameManager.GameState.CINEMATIC, "An invalid replacement must not reset the active protocol's initial-snapshot guard")
	invalid_protocol.queue_free()

	check.call(manager.bind_protocol(null), "The GameManager protocol binding must be safely releasable")
	for resource_type in manager.RESOURCE_KEYS:
		check.call(manager.get_resource_amount(resource_type) == 0, "Unbinding a protocol must clear the previous account's %s projection" % resource_type)
	check.call(not manager.check_citadel_soft_wall(16, 500), "A signed-out session must not pass the soft-wall preview using previous account balances")

	# Freeing the protocol node is the normal scene-teardown path. It must clear
	# the projection even when callers do not explicitly bind null first.
	var exiting_protocol := Protocol.new()
	tree.root.add_child(exiting_protocol)
	manager.set_game_state(GameManager.GameState.CINEMATIC)
	check.call(manager.bind_protocol(exiting_protocol), "A new session must bind after explicit unbind")
	exiting_protocol.player_state_received.emit({"inventory": {"resource.wood": 42}})
	check.call(manager.get_resource_amount("wood") == 42, "The new session must populate from its own authoritative snapshot")
	check.call(manager.current_state == GameManager.GameState.OVERWORLD, "The new session's first snapshot must perform the initial state transition")
	exiting_protocol.queue_free()
	await tree.process_frame
	for resource_type in manager.RESOURCE_KEYS:
		check.call(manager.get_resource_amount(resource_type) == 0, "Protocol tree exit must clear the %s projection" % resource_type)
	check.call(not manager.check_citadel_soft_wall(16, 500), "A freed protocol must not leave prior session balances available")

	manager.state_changed.disconnect(state_callback)
	manager.resource_updated.disconnect(resource_callback)
	manager.soft_wall_reached.disconnect(soft_wall_callback)
	protocol.queue_free()
	replacement_protocol.queue_free()
