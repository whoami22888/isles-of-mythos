extends SceneTree

const Scene = preload("res://gameplay/vertical_slice.tscn")

class MockAttackProtocol extends Node:
	var attacks: Array[Dictionary] = []
	func is_authenticated() -> bool:
		return true
	func request_attack(target_id: String, facing: Vector2) -> String:
		# Match the production protocol's build_attack_message normalization.
		var direction := facing.normalized() if facing.length_squared() >= 0.00000001 else Vector2.ZERO
		attacks.append({"target_id": target_id, "facing": direction})
		return "attack-1"

func _init() -> void:
	var world = Scene.instantiate()
	root.add_child(world)
	await process_frame
	var attack_protocol := MockAttackProtocol.new()
	root.add_child(attack_protocol)
	world._client = attack_protocol
	world._player = Vector3.ZERO
	world._on_world_chunk("chunk-1", {
		"resources": [{"id": "wood:1", "x": 1, "y": 2}],
		"creatures": [
			{"id": "creature:3:4", "species": "slime", "x": 3, "y": 4, "level": 1},
			{"id": "creature:8:0", "species": "boar", "x": 8, "y": 0, "level": 1},
		],
	})
	await process_frame
	var first_marker = world._markers["wood:1"]
	var first_count: int = world._markers.size()
	_assert(world._creatures.size() == 2, "authoritative chunk stores valid creature targets")
	var flintlock_target: Dictionary = world._nearest_creature_for_attack("flintlock")
	_assert(flintlock_target.get("id") == "creature:3:4", "flintlock chooses the nearest server creature in range")
	_assert(world._nearest_creature_for_attack("cutlass").is_empty(),
		"cutlass does not target a creature outside its server range")
	world._attack_nearest_creature("flintlock")
	_assert(attack_protocol.attacks.size() == 1, "flintlock use sends one server attack request")
	_assert(attack_protocol.attacks[0].get("target_id") == "creature:3:4",
		"attack request uses the authoritative creature ID")
	var facing: Vector2 = attack_protocol.attacks[0].get("facing", Vector2.ZERO)
	_assert(facing.distance_to(Vector2(0.6, 0.8)) < 0.0001,
		"attack facing points from the server player position to the selected creature")

	world._on_world_chunk("chunk-2", {
		"resources": [{"id": "wood:1", "x": 3, "y": 4}],
		"creatures": [{"id": "creature:3:4", "species": "slime", "x": 6, "y": 0, "level": 1}],
	})
	await process_frame
	_assert(world._markers.size() == first_count, "repeated resource ID does not grow marker map")
	_assert(world._markers["wood:1"] == first_marker, "repeated resource ID reuses marker")
	_assert(world._creatures.size() == 1, "new server snapshot removes creatures no longer in the chunk")
	_assert(world._nearest_creature_for_attack("cutlass").is_empty(),
		"updated creature position is used for the next target-range check")
	world._on_world_chunk("chunk-3", {"resources": [], "creatures": []})
	await process_frame
	_assert(world._markers.is_empty(), "authoritative deletion frees depleted markers")
	_assert(world._creatures.is_empty(), "authoritative deletion clears depleted creature targets")
	world.queue_free()
	attack_protocol.queue_free()
	await process_frame
	quit(0)

func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("world regression failed: " + label)
		quit(1)
