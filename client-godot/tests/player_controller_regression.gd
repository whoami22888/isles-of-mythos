extends RefCounted

const PlayerController = preload("res://entities/player/player.gd")


class FakeProtocol extends Node:
	signal player_state_received(state: Dictionary)
	signal command_acknowledged(request_id: String, message: Dictionary)
	signal command_rejected(request_id: String, code: String)
	signal command_outcome_unknown(request_id: String)
	signal attack_rejected(request_id: String, code: String)
	signal attack_outcome_unknown(request_id: String)

	var authenticated := true
	var selected_slots: Array[int] = []
	var attacks: Array[Dictionary] = []
	var gathers: Array[Dictionary] = []
	var _attack_counter := 0
	var _gather_counter := 0

	func is_authenticated() -> bool:
		return authenticated

	func request_select_hotbar(slot: int) -> bool:
		if not authenticated or slot < 0 or slot >= 8:
			return false
		selected_slots.append(slot)
		return true

	func request_attack(target_id: String, facing_x: float, facing_y: float) -> String:
		if not authenticated:
			return ""
		_attack_counter += 1
		var request_id := "attack-%d" % _attack_counter
		attacks.append({
			"request_id": request_id,
			"target_id": target_id,
			"facing": Vector2(facing_x, facing_y),
		})
		return request_id

	func request_gather(resource_id: String) -> String:
		if not authenticated:
			return ""
		_gather_counter += 1
		var request_id := "gather-%d" % _gather_counter
		gathers.append({"request_id": request_id, "resource_id": resource_id})
		return request_id


class FakeTouchControls extends Node:
	signal joystick_changed(direction: Vector2)

	func joystick_vector() -> Vector2:
		return Vector2.ZERO


static func run(tree: SceneTree, check: Callable) -> void:
	var protocol := FakeProtocol.new()
	var touch := FakeTouchControls.new()
	var player = PlayerController.new()
	tree.root.add_child(protocol)
	tree.root.add_child(touch)
	tree.root.add_child(player)

	check.call(player.get_node_or_null("FallbackVisual") != null, "Player controller must create a diagnostic fallback when no visual is assigned")
	check.call(player.bind_protocol(protocol), "Player controller must bind to the existing authoritative protocol")
	check.call(player.bind_touch_controls(touch), "Player controller must bind the existing virtual joystick signal")

	var touch_events: Array = []
	touch.joystick_changed.emit(Vector2(1.0, 1.0))
	var touch_direction: Vector2 = player.movement_intent(false)
	check.call(touch_direction.length() <= 1.0001 and touch_direction.x > 0.0 and touch_direction.y > 0.0, "Touch movement must be normalized to a bounded 8-way vector")
	player.set_touch_direction(Vector2.ZERO)

	Input.action_press("move_forward")
	var keyboard_direction: Vector2 = player.movement_intent()
	Input.action_release("move_forward")
	check.call(keyboard_direction.y < -0.9, "Keyboard movement must read the existing forward action")
	var before_input_position: Vector3 = player.global_position
	player.set_touch_direction(Vector2(0.5, -0.5))
	var combined_direction: Vector2 = player.movement_intent()
	check.call(combined_direction.length() <= 1.0001, "Combined keyboard and joystick input must remain bounded")
	check.call(player.global_position == before_input_position, "Input collection must never move the player locally")

	var initial_state := {
		"x": 12.5,
		"y": -3.25,
		"health": 100.0,
		"hunger": 87.5,
		"oxygen": 65.0,
		"hotbar": ["cutlass", "flintlock", "harpoon", "shovel", null, null, null, null],
		"selectedHotbarSlot": 0,
	}
	protocol.player_state_received.emit(initial_state)
	check.call(absf(player.global_position.x - 12.5) < 0.001 and absf(player.global_position.z + 3.25) < 0.001, "Authoritative server coordinates must update the controller transform")
	check.call(is_equal_approx(player.health, 100.0) and is_equal_approx(player.hunger, 87.5) and is_equal_approx(player.oxygen, 65.0), "Health, hunger and oxygen must project the server snapshot")
	var hunger_before_input := player.hunger
	var oxygen_before_input := player.oxygen
	for _index in range(20):
		player.movement_intent()
	check.call(is_equal_approx(player.hunger, hunger_before_input) and is_equal_approx(player.oxygen, oxygen_before_input), "Client input must not locally decay server-owned survival meters")

	var exposed_hotbar: Array[String] = player.hotbar
	exposed_hotbar[2] = "shovel"
	check.call(player.hotbar[2] == "harpoon", "The hotbar getter must not expose mutable internal state")
	check.call(player.select_hotbar_slot(2), "Hotbar selection must send an authenticated server request")
	check.call(protocol.selected_slots == [2] and player.selected_hotbar_slot == 0, "Hotbar selection must wait for the authoritative player_state response")
	var selected_harpoon_state := initial_state.duplicate(true)
	selected_harpoon_state["selectedHotbarSlot"] = 2
	protocol.player_state_received.emit(selected_harpoon_state)
	check.call(player.selected_hotbar_slot == 2, "The server snapshot must confirm the selected hotbar slot")
	check.call(player.use_selected_hotbar_item("creature:0:0:0", "", Vector2(1.0, 0.0)), "Harpoon use must issue the existing authoritative attack command")
	check.call(protocol.attacks.size() == 1 and protocol.attacks[0].get("target_id") == "creature:0:0:0", "Harpoon use must preserve the server target and facing intent")

	var ack_events: Array = []
	player.hotbar_action_acknowledged.connect(func(request_id: String, item_id: String, message: Dictionary) -> void:
		ack_events.append({"id": request_id, "item": item_id, "type": message.get("type")})
	)
	var attack_request_id := str(protocol.attacks[0].get("request_id", ""))
	protocol.command_acknowledged.emit(attack_request_id, {"type": "combat_result"})
	check.call(ack_events.size() == 1 and ack_events[0].get("item") == "harpoon", "Combat ACKs must resolve the matching hotbar request")

	var selected_shovel_state := initial_state.duplicate(true)
	selected_shovel_state["selectedHotbarSlot"] = 3
	protocol.player_state_received.emit(selected_shovel_state)
	check.call(not player.use_selected_hotbar_item(), "Shovel use must fail closed without a resource target")
	check.call(player.use_selected_hotbar_item("", "resource:wood:0:0"), "Shovel use must route through the existing authoritative gather command")
	check.call(protocol.gathers.size() == 1 and protocol.gathers[0].get("resource_id") == "resource:wood:0:0", "Shovel use must send the selected resource identifier")
	var gather_request_id := str(protocol.gathers[0].get("request_id", ""))
	protocol.command_acknowledged.emit(gather_request_id, {"type": "resource_gathered"})
	check.call(ack_events.size() == 2 and ack_events[1].get("item") == "shovel", "Gather ACKs must resolve the matching shovel request")

	var rejected_events: Array = []
	player.hotbar_action_rejected.connect(func(request_id: String, item_id: String, code: String) -> void:
		rejected_events.append({"id": request_id, "item": item_id, "code": code})
	)
	var selected_flintlock_state := initial_state.duplicate(true)
	selected_flintlock_state["selectedHotbarSlot"] = 1
	protocol.player_state_received.emit(selected_flintlock_state)
	check.call(player.use_selected_hotbar_item("creature:0:0:0", "", Vector2(1.0, 0.0)), "Flintlock use must issue an attack request")
	var flintlock_request_id := str(protocol.attacks.back().get("request_id", ""))
	protocol.attack_rejected.emit(flintlock_request_id, "NO_AMMO")
	check.call(rejected_events.size() == 1 and rejected_events[0].get("item") == "flintlock" and rejected_events[0].get("code") == "NO_AMMO", "Attack rejection must be correlated to the selected hotbar item")

	var unknown_events: Array = []
	player.hotbar_action_outcome_unknown.connect(func(request_id: String, item_id: String) -> void:
		unknown_events.append({"id": request_id, "item": item_id})
	)
	check.call(player.use_selected_hotbar_item("creature:0:0:0", "", Vector2(1.0, 0.0)), "Cutlass use must issue an attack request")
	var cutlass_request_id := str(protocol.attacks.back().get("request_id", ""))
	protocol.attack_outcome_unknown.emit(cutlass_request_id)
	check.call(unknown_events.size() == 1 and unknown_events[0].get("item") == "flintlock", "Unknown combat outcomes must be surfaced without retrying the request")

	var death_events := [0]
	player.player_died.connect(func() -> void:
		death_events[0] += 1
	)
	var dead_state := initial_state.duplicate(true)
	dead_state["health"] = 0
	protocol.player_state_received.emit(dead_state)
	protocol.player_state_received.emit(dead_state)
	check.call(death_events[0] == 1, "The player_died signal must emit once when authoritative health reaches zero")
	var revived_state := initial_state.duplicate(true)
	revived_state["health"] = 100
	protocol.player_state_received.emit(revived_state)
	dead_state["health"] = 0
	protocol.player_state_received.emit(dead_state)
	check.call(death_events[0] == 2, "A later authoritative death transition must emit again")

	protocol.authenticated = false
	check.call(not player.select_hotbar_slot(1), "Hotbar selection must fail closed while unauthenticated")
	check.call(not player.use_selected_hotbar_item("creature:0:0:0"), "Hotbar actions must fail closed while unauthenticated")
	protocol.authenticated = true
	check.call(not player.select_hotbar_slot(8), "Out-of-range hotbar slots must be rejected")
	check.call(not player.use_selected_hotbar_item("", "", Vector2.ZERO), "Attack actions must reject a zero facing vector")

	var unknown_state := initial_state.duplicate(true)
	unknown_state["hotbar"] = ["unsupported", null, null, null, null, null, null, null]
	unknown_state["selectedHotbarSlot"] = 0
	protocol.player_state_received.emit(unknown_state)
	check.call(not player.use_selected_hotbar_item("creature:0:0:0"), "Unsupported hotbar items must fail closed")

	var visual_player = PlayerController.new()
	var visual_root := Node3D.new()
	var visual_mesh := MeshInstance3D.new()
	visual_mesh.mesh = BoxMesh.new()
	visual_root.add_child(visual_mesh)
	visual_player.visual_root = visual_root
	visual_player.add_child(visual_root)
	tree.root.add_child(visual_player)
	check.call(visual_player.get_node_or_null("FallbackVisual") == null, "An assigned mesh must suppress the diagnostic fallback")

	var invalid_protocol := Node.new()
	tree.root.add_child(invalid_protocol)
	check.call(not player.bind_protocol(invalid_protocol), "An incomplete protocol must be rejected")
	check.call(player.bind_protocol(null), "Protocol unbinding must be safe")
	check.call(player.bind_touch_controls(null), "Touch-control unbinding must be safe")

	player.queue_free()
	visual_player.queue_free()
	protocol.queue_free()
	touch.queue_free()
	invalid_protocol.queue_free()
