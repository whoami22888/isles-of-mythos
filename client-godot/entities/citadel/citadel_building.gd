class_name CitadelBuilding
extends Node3D

## Client-side citadel upgrade presentation and request contract.
## The server remains authoritative for balances, queue ownership, upgrade completion,
## guild-help eligibility and persisted level changes. This node never deducts resources
## or advances a level locally.

signal upgrade_requested(target_level: int, queue_slot: int, payment_preference: String)
signal upgrade_previewed(target_level: int, costs: Dictionary, payment_mode: String, duration_seconds: int)
signal soft_wall_blocked(target_level: int)
signal upgrade_blocked(target_level: int, missing_resources: Dictionary)
signal upgrade_request_rejected(reason: String)
signal timer_changed(remaining_seconds: float)
signal upgrade_timer_elapsed(target_level: int)
signal guild_help_requested(queue_slot: int)

const MIN_LEVEL := 1
const MAX_LEVEL := 20
const FIRST_QUEUE_SLOT := 0
const SECOND_QUEUE_SLOT := 1
const SOFT_WALL_TARGET_LEVEL := 16
const SOFT_WALL_RESOURCE_COST: Dictionary = {
	"wood": 5_000_000,
	"steel": 5_000_000,
	"food": 1_000_000,
}
const SOFT_WALL_BADGE_COST: Dictionary = {
	"triumph_badges": 500,
}

## Explicit client-preview costs for each target level. The authoritative server must
## validate the same progression table before wiring an upgrade command to this signal.
const UPGRADE_COSTS: Dictionary = {
	2: {"wood": 500, "steel": 250, "food": 100},
	3: {"wood": 1_000, "steel": 500, "food": 200},
	4: {"wood": 2_000, "steel": 1_000, "food": 400},
	5: {"wood": 4_000, "steel": 2_000, "food": 800},
	6: {"wood": 8_000, "steel": 4_000, "food": 1_600},
	7: {"wood": 16_000, "steel": 8_000, "food": 3_200},
	8: {"wood": 32_000, "steel": 16_000, "food": 6_400},
	9: {"wood": 64_000, "steel": 32_000, "food": 12_800},
	10: {"wood": 128_000, "steel": 64_000, "food": 25_600},
	11: {"wood": 256_000, "steel": 128_000, "food": 51_200},
	12: {"wood": 512_000, "steel": 256_000, "food": 102_400},
	13: {"wood": 1_024_000, "steel": 512_000, "food": 204_800},
	14: {"wood": 2_048_000, "steel": 1_024_000, "food": 409_600},
	15: {"wood": 4_096_000, "steel": 2_048_000, "food": 819_200},
	16: {"wood": 5_000_000, "steel": 5_000_000, "food": 1_000_000},
	17: {"wood": 6_000_000, "steel": 6_000_000, "food": 1_500_000},
	18: {"wood": 7_000_000, "steel": 7_000_000, "food": 2_000_000},
	19: {"wood": 8_000_000, "steel": 8_000_000, "food": 2_500_000},
	20: {"wood": 10_000_000, "steel": 10_000_000, "food": 3_000_000},
}

## Display-only duration defaults, in seconds, indexed by target level. The server supplies the real timer.
const UPGRADE_DURATION_SECONDS: Dictionary = {
	2: 900,
	3: 1_800,
	4: 3_600,
	5: 7_200,
	6: 10_800,
	7: 14_400,
	8: 21_600,
	9: 28_800,
	10: 43_200,
	11: 57_600,
	12: 86_400,
	13: 129_600,
	14: 172_800,
	15: 259_200,
	16: 345_600,
	17: 432_000,
	18: 518_400,
	19: 604_800,
	20: 691_200,
}

var _game_manager: Node
var _current_level := MIN_LEVEL
var _second_queue_enabled := false
var _upgrade_in_progress := false
var _queue_slot := -1
var _target_level := 0
var _remaining_seconds := 0.0
var _awaiting_server_confirmation := false
var _request_pending := false

var current_level: int:
	get:
		return _current_level

var second_queue_enabled: bool:
	get:
		return _second_queue_enabled

var upgrade_in_progress: bool:
	get:
		return _upgrade_in_progress

var queue_slot: int:
	get:
		return _queue_slot

var remaining_seconds: float:
	get:
		return _remaining_seconds

var awaiting_server_confirmation: bool:
	get:
		return _awaiting_server_confirmation

var request_pending: bool:
	get:
		return _request_pending


func _ready() -> void:
	if not is_instance_valid(_game_manager):
		_game_manager = get_node_or_null("/root/GameManager")


func _process(delta: float) -> void:
	if not _upgrade_in_progress or _awaiting_server_confirmation:
		return
	if not is_finite(delta) or delta <= 0.0:
		return

	var next_remaining := maxf(0.0, _remaining_seconds - delta)
	if is_equal_approx(next_remaining, _remaining_seconds):
		return

	_remaining_seconds = next_remaining
	timer_changed.emit(_remaining_seconds)
	if _remaining_seconds <= 0.0:
		# Timer expiry is only a UI event. The server snapshot must confirm the new level.
		_awaiting_server_confirmation = true
		upgrade_timer_elapsed.emit(_target_level)


func bind_game_manager(manager: Node) -> bool:
	if not is_instance_valid(manager):
		return false
	if not manager.has_method("get_resource_amount") or not manager.has_method("check_citadel_soft_wall"):
		return false
	_game_manager = manager
	return true


static func upgrade_cost_for_level(target_level: int) -> Dictionary:
	var value: Variant = UPGRADE_COSTS.get(target_level, {})
	if not (value is Dictionary):
		return {}
	return value.duplicate(true)


static func upgrade_duration_for_level(target_level: int) -> int:
	return int(UPGRADE_DURATION_SECONDS.get(target_level, 0))


func request_upgrade(requested_queue_slot: int) -> bool:
	if requested_queue_slot != FIRST_QUEUE_SLOT and requested_queue_slot != SECOND_QUEUE_SLOT:
		upgrade_request_rejected.emit("INVALID_QUEUE_SLOT")
		return false
	if _current_level >= MAX_LEVEL:
		upgrade_request_rejected.emit("MAX_LEVEL")
		return false
	if _upgrade_in_progress or _request_pending:
		upgrade_request_rejected.emit("UPGRADE_ALREADY_ACTIVE")
		return false
	if requested_queue_slot == SECOND_QUEUE_SLOT and not _second_queue_enabled:
		upgrade_request_rejected.emit("SECOND_QUEUE_LOCKED")
		return false

	var target_level := _current_level + 1
	var costs := upgrade_cost_for_level(target_level)
	if costs.is_empty():
		upgrade_request_rejected.emit("UPGRADE_COST_UNAVAILABLE")
		return false

	var payment_mode := "resources"
	if target_level == SOFT_WALL_TARGET_LEVEL:
		var manager := _get_game_manager()
		if not is_instance_valid(manager) or not manager.has_method("check_citadel_soft_wall"):
			soft_wall_blocked.emit(target_level)
			return false
		if not bool(manager.call("check_citadel_soft_wall", target_level, 0)):
			soft_wall_blocked.emit(target_level)
			return false

		var missing_resources := _missing_resources(SOFT_WALL_RESOURCE_COST)
		if missing_resources.is_empty():
			costs = SOFT_WALL_RESOURCE_COST.duplicate(true)
		elif _get_resource_amount("triumph_badges") >= int(SOFT_WALL_BADGE_COST["triumph_badges"]):
			costs = SOFT_WALL_BADGE_COST.duplicate(true)
			payment_mode = "triumph_badges"
		else:
			soft_wall_blocked.emit(target_level)
			return false
	else:
		var missing := _missing_resources(costs)
		if not missing.is_empty():
			upgrade_blocked.emit(target_level, missing)
			return false

	if upgrade_requested.get_connections().is_empty():
		upgrade_request_rejected.emit("SERVER_HANDLER_UNAVAILABLE")
		return false

	_request_pending = true
	upgrade_previewed.emit(
		target_level,
		costs.duplicate(true),
		payment_mode,
		upgrade_duration_for_level(target_level)
	)
	# Only player intent crosses the request signal. Costs and durations are never trusted by the server.
	upgrade_requested.emit(target_level, requested_queue_slot, payment_mode)
	return true


## Apply a complete authoritative citadel/queue snapshot. Invalid or partial state is rejected atomically.
func apply_server_snapshot(snapshot: Dictionary) -> bool:
	var level_value: Variant = snapshot.get("level")
	var second_queue_value: Variant = snapshot.get("second_queue_enabled")
	var in_progress_value: Variant = snapshot.get("upgrade_in_progress")
	if not (level_value is int) or int(level_value) < MIN_LEVEL or int(level_value) > MAX_LEVEL:
		return false
	if not (second_queue_value is bool) or not in_progress_value is bool:
		return false

	var next_queue_slot := -1
	var next_target_level := 0
	var next_remaining_seconds := 0.0
	if bool(in_progress_value):
		var queue_value: Variant = snapshot.get("queue_slot")
		var target_value: Variant = snapshot.get("target_level")
		var remaining_value: Variant = snapshot.get("remaining_seconds")
		if not (queue_value is int) or int(queue_value) < FIRST_QUEUE_SLOT or int(queue_value) > SECOND_QUEUE_SLOT:
			return false
		if int(queue_value) == SECOND_QUEUE_SLOT and not bool(second_queue_value):
			return false
		if not (target_value is int) or int(target_value) != int(level_value) + 1 or int(target_value) > MAX_LEVEL:
			return false
		if not (remaining_value is int or remaining_value is float):
			return false
		next_remaining_seconds = float(remaining_value)
		if not is_finite(next_remaining_seconds) or next_remaining_seconds < 0.0:
			return false
		next_queue_slot = int(queue_value)
		next_target_level = int(target_value)

	_current_level = int(level_value)
	_second_queue_enabled = bool(second_queue_value)
	_upgrade_in_progress = bool(in_progress_value)
	_queue_slot = next_queue_slot
	_target_level = next_target_level
	_remaining_seconds = next_remaining_seconds
	_awaiting_server_confirmation = _upgrade_in_progress and _remaining_seconds <= 0.0
	_request_pending = false
	timer_changed.emit(_remaining_seconds)
	return true


func request_guild_help() -> bool:
	if not _upgrade_in_progress or _awaiting_server_confirmation or _remaining_seconds <= 0.0:
		return false
	if guild_help_requested.get_connections().is_empty():
		upgrade_request_rejected.emit("GUILD_HELP_HANDLER_UNAVAILABLE")
		return false
	guild_help_requested.emit(_queue_slot)
	return true


## Call only after an authoritative guild-help acknowledgement; never apply client-invented reductions.
func apply_server_guild_help_reduction(reduction_seconds: float) -> bool:
	if not _upgrade_in_progress or _awaiting_server_confirmation:
		return false
	if not is_finite(reduction_seconds) or reduction_seconds <= 0.0:
		return false

	var next_remaining := maxf(0.0, _remaining_seconds - reduction_seconds)
	if next_remaining >= _remaining_seconds:
		return false
	_remaining_seconds = next_remaining
	timer_changed.emit(_remaining_seconds)
	if _remaining_seconds <= 0.0:
		_awaiting_server_confirmation = true
		upgrade_timer_elapsed.emit(_target_level)
	return true


func reject_pending_upgrade(reason: String) -> void:
	if not _request_pending:
		return
	_request_pending = false
	upgrade_request_rejected.emit(reason if not reason.is_empty() else "UPGRADE_REJECTED")


func get_queue_snapshot() -> Dictionary:
	return {
		"level": _current_level,
		"second_queue_enabled": _second_queue_enabled,
		"upgrade_in_progress": _upgrade_in_progress,
		"queue_slot": _queue_slot,
		"target_level": _target_level,
		"remaining_seconds": _remaining_seconds,
		"awaiting_server_confirmation": _awaiting_server_confirmation,
		"request_pending": _request_pending,
	}


func _get_game_manager() -> Node:
	if not is_instance_valid(_game_manager):
		_game_manager = get_node_or_null("/root/GameManager")
	return _game_manager


func _get_resource_amount(resource_type: String) -> int:
	var manager := _get_game_manager()
	if not is_instance_valid(manager) or not manager.has_method("get_resource_amount"):
		return 0
	var value: Variant = manager.call("get_resource_amount", resource_type)
	if value is int:
		return maxi(0, int(value))
	if value is float and is_finite(value) and float(value) >= 0.0:
		return int(value)
	return 0


func _missing_resources(costs: Dictionary) -> Dictionary:
	var missing: Dictionary = {}
	for resource_type in costs:
		var required := int(costs[resource_type])
		var available := _get_resource_amount(str(resource_type))
		if required < 0:
			return {"invalid_cost": 1}
		if available < required:
			missing[str(resource_type)] = required - available
	return missing
