extends Node3D
class_name CitadelBuilding

## Client-side projection of server-owned Citadel progression.
## This node never spends resources or advances a level locally. It emits an
## upgrade intent; the authenticated server must validate and persist it.

signal upgrade_requested(target_level: int, queue_slot: int)
signal soft_wall_blocked(target_level: int)
signal guild_help_timer_reduced(seconds: int)
signal authoritative_state_changed

const MIN_LEVEL := 1
const MAX_LEVEL := 20
const SOFT_WALL_FROM_LEVEL := 15
const SOFT_WALL_TARGET_LEVEL := 16
const SOFT_WALL_WOOD := 5_000_000
const SOFT_WALL_STEEL := 5_000_000
const SOFT_WALL_FOOD := 1_000_000
const SOFT_WALL_BADGES := 500
const RESOURCE_FIELDS: Array[String] = ["wood", "steel", "food"]
const COST_FIELDS: Array[String] = ["wood", "steel", "food", "badge_alternative"]

var citadel_level: int = MIN_LEVEL
var upgrade_started_at_unix: int = 0
var upgrade_completes_at_unix: int = 0
var upgrade_target_level: int = 0
var primary_build_queue_busy: bool = false
var second_build_queue_enabled: bool = false
var secondary_build_queue_busy: bool = false
var guild_help_seconds_applied: int = 0

var _upgrade_costs: Dictionary = {}
var _server_now_unix: int = 0
var _snapshot_received_ticks_ms: int = 0
var _has_authoritative_state: bool = false
var _game_manager: Node


func _ready() -> void:
	_game_manager = get_node_or_null("/root/GameManager")


## Apply a validated server snapshot. Costs for levels 2–20 are supplied by
## server-side progression data; the client deliberately invents no balance.
## All timestamps are Unix seconds from the server, not client wall-clock time.
func apply_authoritative_state(state: Dictionary) -> bool:
	var level_value: Variant = state.get("citadel_level")
	var started_value: Variant = state.get("upgrade_started_at_unix")
	var completes_value: Variant = state.get("upgrade_completes_at_unix")
	var target_value: Variant = state.get("upgrade_target_level")
	var server_now_value: Variant = state.get("server_now_unix")
	var help_value: Variant = state.get("guild_help_seconds_applied")
	var queue_value: Variant = state.get("queue_flags")
	var costs_value: Variant = state.get("upgrade_costs")

	if not (level_value is int) or level_value < MIN_LEVEL or level_value > MAX_LEVEL:
		return false
	if not (started_value is int) or started_value < 0:
		return false
	if not (completes_value is int) or completes_value < 0:
		return false
	if not (target_value is int) or target_value < 0 or target_value > MAX_LEVEL:
		return false
	if not (server_now_value is int) or server_now_value <= 0:
		return false
	if not (help_value is int) or help_value < 0:
		return false
	if not (queue_value is Dictionary) or not (costs_value is Dictionary):
		return false

	var primary_busy_value: Variant = queue_value.get("primary_busy")
	var second_enabled_value: Variant = queue_value.get("second_queue_enabled")
	var secondary_busy_value: Variant = queue_value.get("secondary_busy")
	if not (primary_busy_value is bool):
		return false
	if not (second_enabled_value is bool):
		return false
	if not (secondary_busy_value is bool):
		return false
	if not second_enabled_value and secondary_busy_value:
		return false
	if not _is_valid_cost_matrix(costs_value):
		return false

	var started: int = started_value
	var completes: int = completes_value
	var target: int = target_value
	var level: int = level_value
	var help_seconds: int = help_value
	if started == 0:
		if completes != 0 or target != 0 or help_seconds != 0:
			return false
	else:
		if completes <= started or target != level + 1 or target > MAX_LEVEL:
			return false
		if help_seconds < 0:
			return false

	var same_upgrade := (
		_has_authoritative_state
		and started > 0
		and started == upgrade_started_at_unix
		and target == upgrade_target_level
	)
	if same_upgrade:
		if help_seconds < guild_help_seconds_applied:
			return false
		if help_seconds > guild_help_seconds_applied and completes >= upgrade_completes_at_unix:
			return false
	elif started > 0 and help_seconds != 0:
		return false

	var timer_reduction := 0
	if same_upgrade and completes < upgrade_completes_at_unix:
		timer_reduction = upgrade_completes_at_unix - completes

	citadel_level = level
	upgrade_started_at_unix = started
	upgrade_completes_at_unix = completes
	upgrade_target_level = target
	primary_build_queue_busy = primary_busy_value
	second_build_queue_enabled = second_enabled_value
	secondary_build_queue_busy = secondary_busy_value
	guild_help_seconds_applied = help_seconds
	_upgrade_costs = costs_value.duplicate(true)
	_server_now_unix = server_now_value
	_snapshot_received_ticks_ms = Time.get_ticks_msec()
	_has_authoritative_state = true

	if timer_reduction > 0 and help_seconds > 0:
		guild_help_timer_reduced.emit(timer_reduction)
	authoritative_state_changed.emit()
	return true


func get_upgrade_cost(target_level: int) -> Dictionary:
	var value: Variant = _upgrade_costs.get(str(target_level), {})
	return value.duplicate(true) if value is Dictionary else {}


func get_next_upgrade_cost() -> Dictionary:
	if citadel_level >= MAX_LEVEL:
		return {}
	return get_upgrade_cost(citadel_level + 1)


func get_queue_flags() -> Dictionary:
	return {
		"primary_busy": primary_build_queue_busy,
		"second_queue_enabled": second_build_queue_enabled,
		"secondary_busy": secondary_build_queue_busy,
	}


## Estimate the remaining time using the server timestamp plus monotonic client
## elapsed time. A device clock change cannot extend or complete an upgrade.
func get_upgrade_remaining_seconds(now_ticks_ms: int = -1) -> int:
	if not _has_authoritative_state or upgrade_target_level == 0:
		return 0
	var current_ticks := now_ticks_ms if now_ticks_ms >= 0 else Time.get_ticks_msec()
	var elapsed_ms := maxi(0, current_ticks - _snapshot_received_ticks_ms)
	var estimated_server_now := _server_now_unix + int(elapsed_ms / 1000)
	return maxi(0, upgrade_completes_at_unix - estimated_server_now)


## An expired timer remains in progress until the server confirms completion.
func is_upgrade_in_progress() -> bool:
	return _has_authoritative_state and upgrade_target_level > 0


## Emit an intent only. No local level, resource, timer or queue mutation occurs.
func request_next_upgrade() -> bool:
	if not _has_authoritative_state or is_upgrade_in_progress() or citadel_level >= MAX_LEVEL:
		return false

	var target_level := citadel_level + 1
	var queue_slot := _available_queue_slot()
	if queue_slot == 0:
		return false

	if target_level == SOFT_WALL_TARGET_LEVEL:
		if citadel_level != SOFT_WALL_FROM_LEVEL:
			return false
		var manager := _get_game_manager()
		if manager == null or not manager.has_method("check_citadel_soft_wall"):
			soft_wall_blocked.emit(target_level)
			return false
		if not bool(manager.call("check_citadel_soft_wall", target_level, 0)):
			soft_wall_blocked.emit(target_level)
			return false
	else:
		var cost := get_upgrade_cost(target_level)
		if cost.is_empty() or not _can_afford(cost):
			return false

	upgrade_requested.emit(target_level, queue_slot)
	return true


func _available_queue_slot() -> int:
	if not primary_build_queue_busy:
		return 1
	if second_build_queue_enabled and not secondary_build_queue_busy:
		return 2
	return 0


func _can_afford(cost: Dictionary) -> bool:
	var manager := _get_game_manager()
	if manager == null or not manager.has_method("get_resource_amount"):
		return false

	var has_resource_cost := false
	var resources_sufficient := true
	for resource_key in RESOURCE_FIELDS:
		var required := int(cost.get(resource_key, 0))
		if required <= 0:
			continue
		has_resource_cost = true
		var available := int(manager.call("get_resource_amount", resource_key))
		if available < required:
			resources_sufficient = false

	var resource_path_sufficient := has_resource_cost and resources_sufficient
	var badge_cost := int(cost.get("badge_alternative", 0))
	var badges_sufficient := (
		badge_cost > 0
		and int(manager.call("get_resource_amount", "triumph_badges")) >= badge_cost
	)
	return resource_path_sufficient or badges_sufficient


func _get_game_manager() -> Node:
	if is_instance_valid(_game_manager):
		return _game_manager
	_game_manager = get_node_or_null("/root/GameManager")
	return _game_manager


func _is_valid_cost_matrix(costs: Dictionary) -> bool:
	# Require one explicit server-provided entry for every target level 2–20.
	if costs.size() != MAX_LEVEL - MIN_LEVEL:
		return false

	for target_level in range(MIN_LEVEL + 1, MAX_LEVEL + 1):
		var key := str(target_level)
		if not costs.has(key):
			return false
		var entry: Variant = costs.get(key)
		if not (entry is Dictionary):
			return false
		for field in entry.keys():
			if not (field is String) or not COST_FIELDS.has(field):
				return false
			var amount: Variant = entry.get(field)
			if not (amount is int) or amount < 0:
				return false
		for resource_key in RESOURCE_FIELDS:
			if not entry.has(resource_key):
				return false
		if not entry.has("badge_alternative"):
			return false

		var resource_total := (
			int(entry.get("wood", 0))
			+ int(entry.get("steel", 0))
			+ int(entry.get("food", 0))
		)
		if resource_total == 0 and int(entry.get("badge_alternative", 0)) == 0:
			return false

		if target_level == SOFT_WALL_TARGET_LEVEL:
			if (
				int(entry.get("wood", 0)) != SOFT_WALL_WOOD
				or int(entry.get("steel", 0)) != SOFT_WALL_STEEL
				or int(entry.get("food", 0)) != SOFT_WALL_FOOD
				or int(entry.get("badge_alternative", 0)) != SOFT_WALL_BADGES
			):
				return false
	return true
