extends RefCounted

const CitadelBuildingScript = preload("res://entities/citadel/citadel_building.gd")


class FakeGameManager extends Node:
	signal soft_wall_reached

	var resources: Dictionary = {}

	func get_resource_amount(resource_type: String) -> int:
		return int(resources.get(resource_type, 0))

	func check_citadel_soft_wall(target_level: int, _caller_badges: int) -> bool:
		if target_level < CitadelBuildingScript.SOFT_WALL_TARGET_LEVEL:
			return target_level >= CitadelBuildingScript.MIN_LEVEL
		if target_level != CitadelBuildingScript.SOFT_WALL_TARGET_LEVEL:
			return false

		var has_resources := (
			get_resource_amount("wood") >= int(CitadelBuildingScript.SOFT_WALL_RESOURCE_COST["wood"])
			and get_resource_amount("steel") >= int(CitadelBuildingScript.SOFT_WALL_RESOURCE_COST["steel"])
			and get_resource_amount("food") >= int(CitadelBuildingScript.SOFT_WALL_RESOURCE_COST["food"])
		)
		var has_badges := get_resource_amount("triumph_badges") >= int(CitadelBuildingScript.SOFT_WALL_BADGE_COST["triumph_badges"])
		if not has_resources and not has_badges:
			soft_wall_reached.emit()
		return has_resources or has_badges


static func run(tree: SceneTree, check: Callable) -> void:
	var manager := FakeGameManager.new()
	tree.root.add_child(manager)

	var building := CitadelBuildingScript.new()
	tree.root.add_child(building)
	check.call(building.bind_game_manager(manager), "Citadel building must bind only to a manager exposing the required authoritative read methods")

	var blocked_events: Array[int] = []
	var rejection_reasons: Array[String] = []
	var manager_soft_wall_events: Array[int] = []
	var request_events: Array[Dictionary] = []
	var preview_events: Array[Dictionary] = []
	var guild_help_events: Array[int] = []
	var timer_events: Array[float] = []
	var timer_elapsed_events: Array[int] = []

	building.soft_wall_blocked.connect(func(target_level: int) -> void: blocked_events.append(target_level))
	building.upgrade_request_rejected.connect(func(reason: String) -> void: rejection_reasons.append(reason))
	manager.soft_wall_reached.connect(func() -> void: manager_soft_wall_events.append(1))
	building.upgrade_requested.connect(func(target_level: int, queue_slot: int, payment_preference: String) -> void:
		request_events.append({
			"target_level": target_level,
			"queue_slot": queue_slot,
			"payment_preference": payment_preference,
		})
	)
	building.upgrade_previewed.connect(func(target_level: int, costs: Dictionary, payment_mode: String, duration_seconds: int) -> void:
		preview_events.append({
			"target_level": target_level,
			"costs": costs.duplicate(true),
			"payment_mode": payment_mode,
			"duration_seconds": duration_seconds,
		})
	)
	building.guild_help_requested.connect(func(queue_slot: int) -> void: guild_help_events.append(queue_slot))
	building.timer_changed.connect(func(seconds: float) -> void: timer_events.append(seconds))
	building.upgrade_timer_elapsed.connect(func(target_level: int) -> void: timer_elapsed_events.append(target_level))

	for target_level in range(2, CitadelBuildingScript.MAX_LEVEL + 1):
		check.call(not CitadelBuildingScript.upgrade_cost_for_level(target_level).is_empty(), "Every citadel target level must have an explicit cost matrix entry")
		check.call(CitadelBuildingScript.upgrade_duration_for_level(target_level) > 0, "Every citadel target level must have a positive display-duration default")
	var copied_costs := CitadelBuildingScript.upgrade_cost_for_level(16)
	copied_costs["wood"] = 0
	check.call(int(CitadelBuildingScript.upgrade_cost_for_level(16)["wood"]) == 5_000_000, "Callers must not mutate the shared soft-wall cost matrix")

	check.call(building.apply_server_snapshot({
		"level": 15,
		"second_queue_enabled": false,
		"upgrade_in_progress": false,
	}), "A valid level-15 server snapshot must apply")

	manager.resources = {
		"wood": 4_999_999,
		"steel": 5_000_000,
		"food": 1_000_000,
		"triumph_badges": 0,
	}
	check.call(not building.request_upgrade(CitadelBuildingScript.FIRST_QUEUE_SLOT), "Level 15 to 16 must fail one unit below the exact wood requirement")
	check.call(blocked_events == [16], "A blocked level-16 request must emit soft_wall_blocked exactly once")
	check.call(manager_soft_wall_events.size() == 1, "The manager's authoritative soft-wall preview must also record the blocked attempt")
	check.call(not building.request_pending, "A blocked soft-wall request must not leave a pending request")
	check.call(manager.get_resource_amount("wood") == 4_999_999, "A rejected client preview must not mutate authoritative resource state")

	manager.resources = {
		"wood": 0,
		"steel": 0,
		"food": 0,
		"triumph_badges": 499,
	}
	check.call(not building.request_upgrade(CitadelBuildingScript.FIRST_QUEUE_SLOT), "The badge alternative must reject 499 Triumph Badges")
	check.call(blocked_events.size() == 2, "A second blocked level-16 attempt must emit soft_wall_blocked")

	manager.resources["triumph_badges"] = 500
	check.call(building.request_upgrade(CitadelBuildingScript.FIRST_QUEUE_SLOT), "Exactly 500 Triumph Badges must satisfy the level-16 client preview")
	check.call(request_events.size() == 1 and request_events.back()["target_level"] == 16, "A valid level-16 intent must emit one request for target level 16")
	check.call(request_events.back()["payment_preference"] == "triumph_badges", "The badge path must be sent only as a payment preference")
	check.call(preview_events.size() == 1 and preview_events.back()["costs"] == {"triumph_badges": 500}, "The UI preview must expose the exact badge alternative")
	check.call(manager.get_resource_amount("triumph_badges") == 500, "Emitting an upgrade intent must not deduct badges locally")

	check.call(building.apply_server_snapshot({
		"level": 15,
		"second_queue_enabled": false,
		"upgrade_in_progress": false,
	}), "A server rejection/resync must clear the pending badge request")
	manager.resources = {
		"wood": 5_000_000,
		"steel": 5_000_000,
		"food": 1_000_000,
		"triumph_badges": 0,
	}
	check.call(building.request_upgrade(CitadelBuildingScript.FIRST_QUEUE_SLOT), "The exact 5M/5M/1M resource path must satisfy the level-16 preview")
	check.call(request_events.size() == 2 and request_events.back()["payment_preference"] == "resources", "The resource path must be preferred when all required materials are present")
	check.call(preview_events.back()["costs"] == {"wood": 5_000_000, "steel": 5_000_000, "food": 1_000_000}, "The level-16 resource preview must preserve all three exact costs")
	check.call(manager.get_resource_amount("wood") == 5_000_000, "The resource path must not deduct wood on the client")

	check.call(building.apply_server_snapshot({
		"level": 16,
		"second_queue_enabled": false,
		"upgrade_in_progress": false,
	}), "The authoritative level-16 snapshot must advance the displayed level")
	manager.resources = {"wood": 6_000_000, "steel": 6_000_000, "food": 1_500_000, "triumph_badges": 0}
	check.call(not building.request_upgrade(CitadelBuildingScript.SECOND_QUEUE_SLOT), "The second building queue must remain locked until enabled by server state")
	check.call(rejection_reasons.back() == "SECOND_QUEUE_LOCKED", "A locked second queue must report a stable rejection reason")

	check.call(building.apply_server_snapshot({
		"level": 16,
		"second_queue_enabled": true,
		"upgrade_in_progress": false,
	}), "The server must be able to enable the second building queue")
	check.call(building.request_upgrade(CitadelBuildingScript.SECOND_QUEUE_SLOT), "An enabled second queue must accept a valid level-17 intent")
	check.call(request_events.back()["queue_slot"] == CitadelBuildingScript.SECOND_QUEUE_SLOT, "The requested queue slot must be preserved")
	check.call(request_events.back()["target_level"] == 17, "Level 17 must be the next target after authoritative level 16")

	check.call(building.apply_server_snapshot({
		"level": 16,
		"second_queue_enabled": true,
		"upgrade_in_progress": true,
		"queue_slot": CitadelBuildingScript.SECOND_QUEUE_SLOT,
		"target_level": 17,
		"remaining_seconds": 10.0,
	}), "An authoritative active-upgrade snapshot must start the display countdown")
	check.call(building.request_guild_help(), "An active queue must be able to request guild help through its server handler")
	check.call(guild_help_events == [CitadelBuildingScript.SECOND_QUEUE_SLOT], "Guild-help intent must identify the active server queue")
	check.call(building.apply_server_guild_help_reduction(3.0), "A server-confirmed guild-help reduction must shorten the display timer")
	check.call(is_equal_approx(building.remaining_seconds, 7.0), "Guild-help reduction must subtract only the acknowledged duration")
	check.call(not building.apply_server_guild_help_reduction(-1.0), "Negative guild-help reductions must be rejected")
	building._process(2.0)
	check.call(is_equal_approx(building.remaining_seconds, 5.0), "The timer must count down using elapsed frame time")
	building._process(5.0)
	check.call(building.awaiting_server_confirmation, "Timer expiry must wait for an authoritative completion snapshot")
	check.call(timer_elapsed_events == [17], "Timer expiry must emit exactly one completion-refresh signal")
	building._process(5.0)
	check.call(timer_elapsed_events.size() == 1, "A zero timer must not emit repeated completion events")
	check.call(building.current_level == 16, "The client countdown must never advance the authoritative citadel level")
	check.call(is_equal_approx(timer_events.back(), 0.0), "Timer change notifications must report the clamped zero value")

	check.call(building.apply_server_snapshot({
		"level": 17,
		"second_queue_enabled": true,
		"upgrade_in_progress": false,
	}), "Only the server snapshot may confirm level 17 and clear the completed queue")
	check.call(building.current_level == 17 and not building.upgrade_in_progress, "The authoritative completion snapshot must update level and clear the queue")

	check.call(not building.apply_server_snapshot({
		"level": 21,
		"second_queue_enabled": true,
		"upgrade_in_progress": false,
	}), "Out-of-range server levels must be rejected")
	check.call(building.current_level == 17, "An invalid snapshot must not partially mutate the current level")
	check.call(not building.apply_server_snapshot({
		"level": 17,
		"second_queue_enabled": true,
		"upgrade_in_progress": true,
		"queue_slot": CitadelBuildingScript.FIRST_QUEUE_SLOT,
		"target_level": 18,
		"remaining_seconds": -1.0,
	}), "Negative authoritative timers must be rejected")
	check.call(building.current_level == 17 and is_equal_approx(building.remaining_seconds, 0.0), "A rejected timer snapshot must leave existing state unchanged")

	check.call(building.apply_server_snapshot({
		"level": CitadelBuildingScript.MAX_LEVEL,
		"second_queue_enabled": true,
		"upgrade_in_progress": false,
	}), "The maximum level snapshot must be accepted")
	check.call(not building.request_upgrade(CitadelBuildingScript.FIRST_QUEUE_SLOT), "A level-20 citadel must reject further upgrade requests")
	check.call(rejection_reasons.back() == "MAX_LEVEL", "Maximum-level rejection must be explicit")
	check.call(not building.request_upgrade(2), "Queue slots outside the supported range must be rejected")

	var no_handler_building := CitadelBuildingScript.new()
	tree.root.add_child(no_handler_building)
	check.call(no_handler_building.bind_game_manager(manager), "A second building fixture must bind the test manager")
	check.call(no_handler_building.apply_server_snapshot({
		"level": 1,
		"second_queue_enabled": false,
		"upgrade_in_progress": false,
	}), "A new building must accept a valid level-one snapshot")
	manager.resources = {"wood": 500, "steel": 250, "food": 100}
	check.call(not no_handler_building.request_upgrade(CitadelBuildingScript.FIRST_QUEUE_SLOT), "An upgrade must fail closed when no authoritative request handler is connected")
	check.call(not no_handler_building.request_pending, "A missing server handler must not leave a pending request")

	no_handler_building.queue_free()
	building.queue_free()
	manager.queue_free()
	await tree.process_frame
