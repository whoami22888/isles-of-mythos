extends RefCounted

const PlayerController = preload("res://entities/player/player.gd")

class MockProtocol:
	extends Node
	var requested_slots: Array[int] = []
	func request_select_hotbar(slot: int) -> bool:
		requested_slots.append(slot)
		return true

static func run(tree: SceneTree, check: Callable) -> void:
	var player = PlayerController.new()
	tree.root.add_child(player)
	await tree.process_frame
	check.call(player is CharacterBody3D, "Player proxy must extend CharacterBody3D")
	check.call(player.has_fallback_visual(), "Player proxy must retain a fallback visual without an assigned production mesh")
	check.call(player.get_blocked_controls().size() == 2, "Survival and hotbar panels must block camera/joystick gestures")
	var directions := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
		Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(-1, 1)]
	for direction in directions:
		var intent: Vector2 = PlayerController.movement_vector_for(direction, Vector2.ZERO, 0.0)
		check.call(absf(intent.length() - 1.0) < 0.0001, "Eight-way input must normalize to one server intent speed")
	var diagonal: Vector2 = PlayerController.movement_vector_for(Vector2(1, -1), Vector2.ZERO, 0.0)
	check.call(is_equal_approx(diagonal.x, sqrt(0.5)) and is_equal_approx(diagonal.y, -sqrt(0.5)),
		"Diagonal movement must not exceed cardinal movement speed")
	var rotated: Vector2 = PlayerController.movement_vector_for(Vector2.RIGHT, Vector2.ZERO, PI / 2.0)
	check.call(rotated.distance_to(Vector2.UP) < 0.0001, "Movement intent must rotate with the strategic camera")
	var cancelled: Vector2 = PlayerController.movement_vector_for(Vector2.RIGHT, Vector2.LEFT, 0.0)
	check.call(cancelled == Vector2.ZERO, "Opposing keyboard and joystick input must cancel safely")
	player.apply_server_state({
		"health": 75, "hunger": 50, "oxygen": 25,
		"hotbar": ["cutlass", "flintlock", "harpoon", "shovel", null, null, null, null],
		"selectedHotbarSlot": 3,
	})
	var survival: Dictionary = player.get_survival_values()
	check.call(survival.get("has_server_state") == true, "Survival HUD must consume a server snapshot")
	check.call(is_equal_approx(float(survival.get("health", 0.0)), 75.0), "Health display must use authoritative health")
	check.call(is_equal_approx(float(survival.get("hunger", 0.0)), 50.0), "Hunger display must use authoritative hunger")
	check.call(is_equal_approx(float(survival.get("oxygen", 0.0)), 25.0), "Oxygen display must use authoritative oxygen")
	check.call(player.get_hotbar_item(0) == "cutlass" and player.get_hotbar_item(1) == "flintlock"
		and player.get_hotbar_item(2) == "harpoon" and player.get_hotbar_item(3) == "shovel",
		"Hotbar must expose the four server-provided starter items")
	var gathered := [0]
	player.gather_requested.connect(func() -> void: gathered[0] += 1)
	check.call(player.use_selected_tool(), "Selecting the shovel must expose the gather tool action")
	check.call(gathered[0] == 1, "Shovel use must dispatch the existing gather action, not mutate inventory locally")
	var mock := MockProtocol.new()
	tree.root.add_child(mock)
	player.bind_protocol(mock)
	check.call(player.select_hotbar_slot(2), "A populated hotbar slot must send a server selection request")
	check.call(mock.requested_slots == [2], "Hotbar selection must send the selected slot to the server")
	check.call(player.get_selected_hotbar_slot() == 3, "Hotbar selection must wait for the server snapshot")
	player.apply_server_state({"selectedHotbarSlot": 2})
	check.call(player.get_selected_hotbar_slot() == 2, "The server snapshot must confirm hotbar selection")
	check.call(not player.use_selected_tool(), "A non-shovel slot must not dispatch the gather action")
	player.apply_server_state({"health": -5, "hunger": "invalid", "oxygen": 125})
	survival = player.get_survival_values()
	check.call(is_equal_approx(float(survival.get("health", 1.0)), 0.0), "Survival values must clamp to their lower bound")
	check.call(is_equal_approx(float(survival.get("hunger", 0.0)), 50.0), "Malformed survival values must preserve the last valid snapshot")
	check.call(is_equal_approx(float(survival.get("oxygen", 0.0)), 100.0), "Survival values must clamp to their upper bound")
	var server_position := Vector3(4.0, 0.9, -2.0)
	player.set_server_position(server_position)
	check.call(player.position.is_equal_approx(server_position), "Only a server position setter may move the player proxy")
	var before_input := player.position
	player.movement_intent(0.0)
	check.call(player.position.is_equal_approx(before_input), "Keyboard/joystick intent must not locally move the player proxy")
	mock.queue_free()
	player.queue_free()
	await tree.process_frame
