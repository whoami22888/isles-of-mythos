extends RefCounted

const CitadelBuilding = preload("res://entities/citadel/citadel_building.gd")
const Protocol = preload("res://gameplay/vertical_slice_protocol.gd")


static func run(tree: SceneTree, check: Callable) -> void:
	var manager = tree.root.get_node_or_null("GameManager")
	check.call(manager != null, "Citadel progression requires the GameManager autoload")
	if manager == null:
		return

	var protocol = Protocol.new()
	tree.root.add_child(protocol)
	check.call(manager.bind_protocol(protocol), "Citadel regression must bind a fresh authoritative player-state protocol")

	var building = CitadelBuilding.new()
	tree.root.add_child(building)
	var blocked_events: Array[int] = []
	var requests: Array[Dictionary] = []
	var help_reductions: Array[int] = []
	building.soft_wall_blocked.connect(func(target_level: int) -> void:
		blocked_events.append(target_level)
	)
	building.upgrade_requested.connect(func(target_level: int, queue_slot: int) -> void:
		requests.append({"target_level": target_level, "queue_slot": queue_slot})
	)
	building.guild_help_timer_reduced.connect(func(seconds: int) -> void:
		help_reductions.append(seconds)
	)

	var costs := _test_cost_matrix()
	var state := _idle_state(15, costs)
	check.call(building.apply_authoritative_state(state), "Citadel must accept a complete, validated server snapshot")
	check.call(building.citadel_level == 15, "Citadel level must come from the server snapshot")

	protocol.player_state_received.emit({
		"inventory": {
			"resource.wood": 4999999,
			"resource.steel": 5000000,
			"resource.food": 1000000,
		},
		"gold": "0",
		"triumphBadges": "0",
	})
	check.call(not building.request_next_upgrade(), "Level 15 to 16 must reject 4,999,999 wood and zero badges")
	check.call(blocked_events == [16], "A blocked Level 16 request must emit soft_wall_blocked")
	check.call(requests.is_empty(), "A blocked soft wall must not emit an upgrade intent")

	protocol.player_state_received.emit({
		"inventory": {
			"resource.wood": 5000000,
			"resource.steel": 5000000,
			"resource.food": 1000000,
		},
		"gold": "0",
		"triumphBadges": "0",
	})
	check.call(building.request_next_upgrade(), "The exact resource path must permit a Level 16 upgrade intent")
	check.call(requests.size() == 1 and requests.back() == {"target_level": 16, "queue_slot": 1}, "The Level 16 resource path must use the free primary queue")
	check.call(building.citadel_level == 15 and building.upgrade_target_level == 0, "An upgrade intent must not mutate local Citadel state")

	protocol.player_state_received.emit({
		"inventory": {
			"resource.wood": 0,
			"resource.steel": 0,
			"resource.food": 0,
		},
		"gold": "0",
		"triumphBadges": "500",
	})
	check.call(building.request_next_upgrade(), "The 500-badge alternative must permit a Level 16 intent")
	check.call(requests.size() == 2, "The badge path must emit exactly one additional upgrade intent")

	var generic_state := _idle_state(1, costs)
	generic_state["queue_flags"] = {
		"primary_busy": true,
		"second_queue_enabled": true,
		"secondary_busy": false,
	}
	check.call(building.apply_authoritative_state(generic_state), "Citadel must accept both server-owned building queue flags")
	protocol.player_state_received.emit({
		"inventory": {
			"resource.wood": 200,
			"resource.steel": 100,
			"resource.food": 50,
		},
		"gold": "0",
		"triumphBadges": "0",
	})
	check.call(building.request_next_upgrade(), "A funded non-soft-wall upgrade must use the available second queue")
	check.call(requests.back() == {"target_level": 2, "queue_slot": 2}, "A busy primary queue must route intent to the enabled free secondary queue")

	protocol.player_state_received.emit({
		"inventory": {
			"resource.wood": 0,
			"resource.steel": 0,
			"resource.food": 0,
		},
		"gold": "0",
		"triumphBadges": "20",
	})
	check.call(building.request_next_upgrade(), "A server-provided badge alternative must be honored for non-soft-wall levels")

	var no_queue_state := _idle_state(1, costs)
	no_queue_state["queue_flags"] = {
		"primary_busy": true,
		"second_queue_enabled": false,
		"secondary_busy": false,
	}
	check.call(building.apply_authoritative_state(no_queue_state), "Citadel must accept a disabled secondary queue")
	check.call(not building.request_next_upgrade(), "No upgrade intent may be emitted when both building queues are unavailable")

	var active_state := _idle_state(15, costs)
	active_state["upgrade_started_at_unix"] = 1000
	active_state["upgrade_completes_at_unix"] = 1300
	active_state["upgrade_target_level"] = 16
	active_state["server_now_unix"] = 1000
	active_state["queue_flags"] = {
		"primary_busy": true,
		"second_queue_enabled": true,
		"secondary_busy": false,
	}
	check.call(building.apply_authoritative_state(active_state), "Citadel must accept an active server-timed upgrade")
	check.call(building.is_upgrade_in_progress(), "An active server target must keep the upgrade in progress")
	check.call(building.get_upgrade_remaining_seconds(Time.get_ticks_msec()) == 300, "Upgrade countdown must use server time plus monotonic elapsed time")
	check.call(not building.request_next_upgrade(), "A running Citadel upgrade must not be started twice")

	var helped_state := active_state.duplicate(true)
	helped_state["upgrade_completes_at_unix"] = 1100
	helped_state["guild_help_seconds_applied"] = 200
	check.call(building.apply_authoritative_state(helped_state), "A valid guild-help snapshot must shorten the active server timer")
	check.call(help_reductions == [200], "A server-confirmed 200-second guild-help reduction must be signalled")
	check.call(building.get_upgrade_remaining_seconds(Time.get_ticks_msec()) == 100, "Guild help must update the displayed remaining time from the new server completion timestamp")

	var completed_state := _idle_state(16, costs)
	completed_state["server_now_unix"] = 1200
	check.call(building.apply_authoritative_state(completed_state), "Citadel must accept the server-confirmed completed level")
	check.call(not building.is_upgrade_in_progress(), "The completed server snapshot must clear the active upgrade target")

	var invalid_matrix_state := _idle_state(16, costs)
	invalid_matrix_state["upgrade_costs"].erase("20")
	check.call(not building.apply_authoritative_state(invalid_matrix_state), "An incomplete level 2–20 server cost matrix must fail closed")
	check.call(building.citadel_level == 16, "A rejected cost matrix must not overwrite the last valid Citadel state")

	var invalid_soft_wall_state := _idle_state(15, costs)
	invalid_soft_wall_state["upgrade_costs"]["16"] = {
		"wood": 4999999,
		"steel": 5000000,
		"food": 1000000,
		"badge_alternative": 500,
	}
	check.call(not building.apply_authoritative_state(invalid_soft_wall_state), "The server cost matrix must preserve the exact Level 16 soft-wall values")
	check.call(building.citadel_level == 16, "A rejected soft-wall matrix must leave the prior level unchanged")

	manager.end_session()
	protocol.queue_free()
	building.queue_free()
	await tree.process_frame


static func _idle_state(level: int, costs: Dictionary) -> Dictionary:
	return {
		"citadel_level": level,
		"upgrade_started_at_unix": 0,
		"upgrade_completes_at_unix": 0,
		"upgrade_target_level": 0,
		"server_now_unix": 1700000000,
		"guild_help_seconds_applied": 0,
		"queue_flags": {
			"primary_busy": false,
			"second_queue_enabled": false,
			"secondary_busy": false,
		},
		"upgrade_costs": costs.duplicate(true),
	}


static func _test_cost_matrix() -> Dictionary:
	# Synthetic fixtures only. Production cost values must arrive from server data.
	var costs := {}
	for target_level in range(2, 21):
		costs[str(target_level)] = {
			"wood": target_level * 100,
			"steel": target_level * 50,
			"food": target_level * 25,
			"badge_alternative": target_level * 10,
		}
	costs["16"] = {
		"wood": 5000000,
		"steel": 5000000,
		"food": 1000000,
		"badge_alternative": 500,
	}
	return costs
