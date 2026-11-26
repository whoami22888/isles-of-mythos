extends RefCounted

const TacticalTower = preload("res://scenes/tactical_tower.gd")


class InvaderDummy extends CharacterBody3D:
	var element = TacticalTower.Element.EARTH


	func _init(kind) -> void:
		element = TacticalTower.parse_element(kind)
		collision_layer = 1
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.4
		shape.shape = sphere
		add_child(shape)


	func get_element():
		return element


static func run(tree: SceneTree, check: Callable) -> void:
	check.call(is_equal_approx(TacticalTower.elemental_multiplier(TacticalTower.Element.FIRE, TacticalTower.Element.EARTH), 1.5), "Fire deals 1.5× to Earth")
	check.call(is_equal_approx(TacticalTower.elemental_multiplier(TacticalTower.Element.EARTH, TacticalTower.Element.AIR), 1.5), "Earth deals 1.5× to Air")
	check.call(is_equal_approx(TacticalTower.elemental_multiplier(TacticalTower.Element.AIR, TacticalTower.Element.WATER), 1.5), "Air deals 1.5× to Water")
	check.call(is_equal_approx(TacticalTower.elemental_multiplier(TacticalTower.Element.WATER, TacticalTower.Element.FIRE), 1.5), "Water deals 1.5× to Fire")
	check.call(is_equal_approx(TacticalTower.elemental_multiplier(TacticalTower.Element.EARTH, TacticalTower.Element.FIRE), 1.0 / 1.5), "Earth resists Fire at 1/1.5")
	check.call(is_equal_approx(TacticalTower.elemental_multiplier(TacticalTower.Element.FIRE, TacticalTower.Element.FIRE), 1.0), "Same-element attacks are 1×")
	check.call(TacticalTower.element_name(TacticalTower.Element.FIRE) == "fire", "Element names are lowercase")
	check.call(TacticalTower.parse_element(" Earth ") == TacticalTower.Element.EARTH, "Element names parse case-insensitively")

	var world := Node3D.new()
	tree.root.add_child(world)

	var tower := TacticalTower.new()
	tower.auto_tick = false
	tower.attack_range = 10.0
	tower.attack_cooldown = 1.0
	tower.base_damage = 10.0
	tower.element = TacticalTower.Element.FIRE
	tower.barrel_yaw_speed = INF
	world.add_child(tower)
	tower.set_physics_process(false)
	tower.global_position = Vector3.ZERO

	var close := InvaderDummy.new(TacticalTower.Element.EARTH)
	world.add_child(close)
	close.add_to_group(TacticalTower.INVADER_GROUP)
	close.global_position = Vector3(4.0, 0.0, 0.0)

	var farther := InvaderDummy.new(TacticalTower.Element.WATER)
	world.add_child(farther)
	farther.add_to_group(TacticalTower.INVADER_GROUP)
	farther.global_position = Vector3(8.0, 0.0, 0.0)

	var out_of_range := InvaderDummy.new(TacticalTower.Element.EARTH)
	world.add_child(out_of_range)
	out_of_range.add_to_group(TacticalTower.INVADER_GROUP)
	out_of_range.global_position = Vector3(25.0, 0.0, 0.0)

	for _i in range(4):
		await tree.physics_frame

	check.call(tower.get_detection_area() is Area3D, "The tower exposes a configurable Area3D detector")
	check.call(is_equal_approx(tower.get_detection_area().get_node("CollisionShape3D").shape.radius, 10.0), "The Area3D sphere matches attack_range")
	check.call(tower.is_in_range(close) and tower.is_in_range(farther) and not tower.is_in_range(out_of_range), "Range checks use the configured attack radius")
	check.call(tower.find_closest_invader() == close, "The tower acquires the closest invader in range")

	var shots: Array[Dictionary] = []
	tower.attack_fired.connect(func(target: Node3D, payload: Dictionary) -> void:
		shots.append({"target": target, "payload": payload})
	)

	tower.tick(0.0)
	check.call(tower.current_target == close, "tick() locks onto the closest dummy")
	var barrel_yaw := tower.get_barrel().rotation.y
	var expected_yaw := atan2(4.0, 0.0)
	check.call(is_equal_approx(barrel_yaw, expected_yaw) or absf(angle_difference(barrel_yaw, expected_yaw)) < 0.05, "The barrel yaws toward the closest target on the Y-axis")
	check.call(shots.size() == 1, "The first tick in range emits an attack signal")
	check.call(shots[0]["target"] == close, "The first shot is aimed at the closest dummy")
	check.call(is_equal_approx(float(shots[0]["payload"]["multiplier"]), 1.5) and is_equal_approx(float(shots[0]["payload"]["damage"]), 15.0), "Fire vs Earth applies a 1.5× proposed damage of 15")
	check.call(shots[0]["payload"]["attacker_element"] == "fire" and shots[0]["payload"]["defender_element"] == "earth", "The attack payload names both elements")
	check.call(not ("health" in close) or close.get("health") == null, "The tower does not invent or write invader health")

	tower.tick(0.4)
	check.call(shots.size() == 1, "A second shot is not emitted before the cooldown elapses")
	tower.tick(0.6)
	check.call(shots.size() == 2, "The attack signal repeats once the cooldown interval has elapsed")
	check.call(shots[1]["target"] == close, "The interval shot still tracks the closest dummy")

	close.queue_free()
	close = null
	for _i in range(3):
		await tree.physics_frame
	tower.tick(1.0)
	check.call(tower.current_target == farther, "When the closest dummy leaves, the tower switches to the next in-range invader")
	check.call(shots.size() == 3, "A retargeted invader is fired on immediately once the previous cooldown is clear")
	check.call(is_equal_approx(float(shots[2]["payload"]["multiplier"]), 1.0 / 1.5), "Fire vs Water is resisted at 1/1.5")

	farther.queue_free()
	out_of_range.queue_free()
	world.queue_free()
