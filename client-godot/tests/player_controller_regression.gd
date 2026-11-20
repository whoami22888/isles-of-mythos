extends RefCounted

const PlayerController = preload("res://entities/player/player.gd")


class MockProtocol:
	extends Node

	signal combat_result_received(request_id: String, result: Dictionary)

	var move_requests: Array[Vector2] = []
	var selected_slots: Array[int] = []
	var attack_requests: Array[Dictionary] = []
	var gather_requests: Array[String] = []

	func request_move(dx: float, dy: float) -> bool:
		move_requests.append(Vector2(dx, dy))
		return true

	func request_select_hotbar(slot: int) -> bool:
		selected_slots.append(slot)
		return true

	func request_attack(target_id: String, facing_x: float, facing_y: float) -> String:
		attack_requests.append({
			"target_id": target_id,
			"facing": Vector2(facing_x, facing_y),
		})
		return "attack-%d" % attack_requests.size()

	func request_gather(resource_id: String) -> String:
		gather_requests.append(resource_id)
		return "gather-%d" % gather_requests.size()


static func run(root: Node, check: Callable) -> void:
	var player = PlayerController.new()
	player.name = "PlayerControllerRegression"
	root.add_child(player)
	var protocol = MockProtocol.new()
	protocol.name = "MockPlayerProtocol"
	root.add_child(protocol)

	check.call(player.get_node_or_null("FallbackBody") is MeshInstance3D, "PlayerController must create a fallback capsule when no mesh is assigned")
	check.call(player.set_protocol(protocol), "PlayerController must bind the authenticated protocol adapter")

	var death_events := 0
	var survival_events: Array[Dictionary] = []
	var combat_events: Array[Dictionary] = []
	player.player_died.connect(func() -> void: death_events += 1)
	player.survival_state_changed.connect(func(hp: float, food: float, air: float, energy: float) -> void:
		survival_events.append({"health": hp, "hunger": food, "oxygen": air, "stamina": energy})
	)
	player.combat_result_received.connect(func(request_id: String, result: Dictionary) -> void:
		combat_events.append({"request_id": request_id, "result": result})
	)

	var snapshot := {
		"x": 12.0,
		"y": -4.0,
		"health": 100.0,
		"stamina": 75.0,
		"maxStamina": 100.0,
		"hunger": 100.0,
		"oxygen": 80.0,
		"hotbar": ["cutlass", "flintlock", "harpoon", "shovel", null, null, null, null],
		"selectedHotbarSlot": 0,
	}
	player.apply_authoritative_state(snapshot)
	check.call(player.server_position == Vector2(12.0, -4.0), "PlayerController must read server position without moving itself")
	check.call(is_equal_approx(player.health, 100.0) and is_equal_approx(player.hunger, 100.0) and is_equal_approx(player.oxygen, 80.0), "Survival meters must use the authoritative snapshot")
	check.call(player.hotbar.size() == 8 and player.selected_hotbar_slot == 0, "Hotbar state must be normalized to eight server-owned slots")
	check.call(not survival_events.is_empty(), "A changed authoritative survival snapshot must emit survival_state_changed")

	check.call(player.request_move_intent(Vector2(1.0, 1.0)), "Diagonal movement intent must be sent")
	check.call(protocol.move_requests.size() == 1, "Movement must be forwarded exactly once")
	check.call(is_equal_approx(protocol.move_requests[0].length(), 1.0), "Eight-way movement must be normalized before it reaches the server")
	check.call(is_equal_approx(player.hunger, 100.0), "The client must not locally decay hunger while sending movement")
	check.call(not player.request_move_intent(Vector2.ZERO), "A zero movement vector must not be sent")
	check.call(not player.request_move_intent(Vector2(INF, 0.0)), "A non-finite movement vector must not be sent")

	check.call(not player.select_hotbar_slot(-1) and not player.select_hotbar_slot(8), "Hotbar selection must reject slots outside 0..7")
	check.call(player.select_hotbar_slot(1), "A valid hotbar slot must be sent to the server")
	check.call(protocol.selected_slots == [1], "Hotbar selection must be forwarded without optimistic local mutation")
	check.call(player.selected_hotbar_slot == 0, "The selected slot must remain server-owned until the next snapshot")

	player.apply_authoritative_state({"selectedHotbarSlot": 1})
	var flintlock_request := player.use_selected_hotbar("creature:1:2:3", Vector2(1.0, 1.0))
	check.call(flintlock_request == "attack-1", "Flintlock use must produce a tracked server attack request")
	check.call(protocol.attack_requests.size() == 1 and protocol.attack_requests[0].target_id == "creature:1:2:3", "Flintlock must target the supplied server creature id")
	check.call(is_equal_approx(protocol.attack_requests[0].facing.length(), 1.0), "Attack facing must be normalized")

	player.apply_authoritative_state({"selectedHotbarSlot": 2})
	check.call(player.use_selected_hotbar("creature:2:3:4", Vector2(0.0, 1.0)) == "attack-2", "Harpoon use must use the server attack command")
	player.apply_authoritative_state({"selectedHotbarSlot": 0})
	check.call(player.use_selected_hotbar("creature:3:4:5", Vector2(1.0, 0.0)) == "attack-3", "Cutlass use must use the server attack command")
	player.apply_authoritative_state({"selectedHotbarSlot": 3})
	check.call(player.use_selected_hotbar("resource:1:2:3", Vector2.ZERO) == "gather-1", "Shovel use must use the server-authoritative gather command")
	check.call(protocol.gather_requests == ["resource:1:2:3"], "Shovel must not mutate inventory locally")
	check.call(player.use_selected_hotbar("resource:1:2:3", Vector2.ZERO) == "gather-2", "Shovel gather must not require a facing vector")

	check.call(player.use_selected_hotbar("", Vector2(1.0, 0.0)).is_empty(), "Hotbar use must reject an empty target id")

	protocol.combat_result_received.emit("attack-1", {"damage": 20, "killed": false})
	check.call(combat_events.size() == 1 and combat_events[0].request_id == "attack-1", "Combat results must be forwarded to the player controller")

	player.apply_authoritative_state({"health": 0.0, "hunger": 0.0, "oxygen": 0.0})
	check.call(death_events == 1, "The first authoritative zero-health snapshot must emit player_died")
	player.apply_authoritative_state({"health": 0.0})
	check.call(death_events == 1, "Repeated zero-health snapshots must not duplicate player_died")
	player.apply_authoritative_state({"health": 100.0})
	player.apply_authoritative_state({"health": 0.0})
	check.call(death_events == 2, "A later authoritative death after respawn must emit player_died again")

	player.set_protocol(null)
	player.queue_free()
	protocol.queue_free()
