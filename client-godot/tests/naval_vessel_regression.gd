extends RefCounted

const NavalVessel = preload("res://entities/ships/naval_vessel.gd")
const Gateway = preload("res://scripts/network/authoritative_command_gateway.gd")

static func run(tree: SceneTree, check: Callable) -> void:
	var vessel = NavalVessel.new()
	tree.root.add_child(vessel)
	await tree.process_frame
	check.call(vessel.find_child("BroadsideFx", true, false) != null, "Naval vessel must create presentation broadside FX")
	check.call(vessel.find_child("FallbackHull", true, false) != null, "Naval vessel must keep a fallback hull when no mesh is supplied")
	check.call(not vessel.apply_authoritative_ship({"heading": 0.0}), "A snapshot without a position must be rejected")
	check.call(vessel.send_heading_intent(1.0, 0.0) == "", "Heading intent must not be sent before a server snapshot")

	check.call(vessel.apply_authoritative_ship({"id": "ship-1", "x": 10.0, "y": 4.0, "heading": 0.5}), "A complete server ship snapshot must be accepted")
	check.call(vessel.has_server_snapshot(), "The vessel must record that it has an authoritative snapshot")
	check.call(is_equal_approx(vessel.position.x, 10.0) and is_equal_approx(vessel.position.z, 4.0), "The first snapshot must snap the presentation transform")

	var gateway = Gateway.new()
	check.call(gateway._valid_fields("sail", {"shipId": "ship-1", "dx": 1.0, "dy": 0.0}), "A unit heading must pass gateway validation")
	check.call(not gateway._valid_fields("sail", {"shipId": "ship-1", "dx": 0.0, "dy": 0.0}), "A zero heading must be rejected by the gateway")
	check.call(not gateway._valid_fields("sail", {"shipId": "ship-1", "dx": 2.0, "dy": 0.0}), "An out-of-range heading must be rejected by the gateway")
	check.call(gateway._valid_fields("fire_cannon", {"shipId": "ship-1", "targetShipId": "ship-2"}), "A fire command with both ship ids must pass validation")
	check.call(not gateway._valid_fields("fire_cannon", {"shipId": "ship-1"}), "A fire command without a target must be rejected")
	gateway.free()

	check.call(vessel.send_heading_intent(1.0, 0.0) == "", "Heading intent must still require an authenticated gateway")
	check.call(vessel.request_fire_cannon("ship-2") == "", "Fire intent must still require an authenticated gateway")

	var fired: Array[String] = []
	var cooldowns: Array[int] = []
	var shakes: Array[int] = []
	vessel.broadside_fired.connect(func(side: String, event_id: String) -> void:
		fired.append("%s:%s" % [side, event_id])
	)
	vessel.broadside_cooldown_started.connect(func(duration_ms: int) -> void:
		cooldowns.append(duration_ms)
	)
	vessel.hit_stop_started.connect(func() -> void:
		shakes.append(1)
	)
	var ack := {
		"type": "naval_combat_result",
		"requestId": "fire-1",
		"side": "starboard",
		"damage": 12,
		"cooldownMs": 1000,
	}
	check.call(vessel.apply_naval_combat_result(ack), "The first acknowledged broadside must play presentation effects")
	check.call(not vessel.apply_naval_combat_result(ack), "A repeated combat event must not replay particles or shake")
	check.call(fired == ["starboard:fire-1"], "The fire signal must use the server side and event id")
	check.call(cooldowns == [1000], "The cooldown timer must start from the server duration")
	check.call(shakes == [1], "Hit-stop shake must start once for the acknowledged hit")
	check.call(vessel.broadside_cooldown_remaining_ms() > 0, "The presentation cooldown timer must be running after a successful fire")
	var smoke = vessel.find_child("StarboardCannonSmoke", true, false)
	check.call(smoke is GPUParticles3D, "Starboard smoke must exist as a GPU particle emitter")
	if smoke is GPUParticles3D:
		check.call((smoke as GPUParticles3D).one_shot, "Cannon smoke must be a one-shot burst")
		check.call((smoke as GPUParticles3D).fixed_fps == 30, "Cannon smoke must stay on the 30 fps particle budget")
	var splinters = vessel.find_child("WoodSplinterBurst", true, false)
	check.call(splinters is GPUParticles3D, "Wood splinter debris must exist as a GPU particle emitter")
	vessel.queue_free()
