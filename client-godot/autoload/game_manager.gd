extends Node

## Client-side game-mode state and a read-only projection of server-owned player data.
## This singleton never authorizes inventory, economy, crafting, combat, or progression.
## The server remains authoritative for every resource change.

enum GameState {
	MENU,
	OVERWORLD,
	BASE_BUILD,
	COMBAT,
	TACTICAL_DEFENSE,
	CINEMATIC,
}

signal state_changed(new_state: int)
signal resource_updated(type: String, amount: int)
signal soft_wall_reached

const RESOURCE_KEYS: Array[String] = [
	"wood",
	"steel",
	"food",
	"doubloons",
	"pearls",
	"triumph_badges",
]

const SOFT_WALL_TARGET_LEVEL := 16
const SOFT_WALL_WOOD := 5_000_000
const SOFT_WALL_STEEL := 5_000_000
const SOFT_WALL_FOOD := 1_000_000
const SOFT_WALL_BADGES := 500

var _current_state: int = GameState.MENU
var current_state: int:
	get:
		return _current_state

var _player_resources: Dictionary = {
	"wood": 0,
	"steel": 0,
	"food": 0,
	"doubloons": 0,
	"pearls": 0,
	"triumph_badges": 0,
}
var player_resources: Dictionary:
	get:
		return _player_resources.duplicate(true)

var _protocol: Node


func set_game_state(next_state: int) -> bool:
	if next_state < GameState.MENU or next_state > GameState.CINEMATIC:
		return false
	if next_state == _current_state:
		return true
	_current_state = next_state
	state_changed.emit(_current_state)
	return true


func get_resource_amount(resource_type: String) -> int:
	return int(_player_resources.get(resource_type, 0))


func modify_resource(resource_type: String, amount: int) -> bool:
	# Prompt 011's original local-delta test conflicts with the server-authority
	# contract. Keep the requested API as a fail-closed guard: callers must use
	# an allow-listed server operation and wait for its authoritative ACK/state.
	if not RESOURCE_KEYS.has(resource_type) or amount == 0:
		return false
	return false


func bind_protocol(protocol: Node) -> bool:
	if protocol == null:
		_unbind_protocol()
		return true
	if protocol == _protocol:
		return is_instance_valid(protocol)
	if not is_instance_valid(protocol):
		return false
	if not protocol.has_signal("player_state_received") or not protocol.has_signal("command_acknowledged"):
		return false

	# Prepare the replacement completely before releasing the active protocol.
	# A rejected or partially-connectable candidate must not interrupt live state.
	var player_state_callable := Callable(self, "_on_player_state_received")
	var command_ack_callable := Callable(self, "_on_command_acknowledged")
	var tree_exit_callable := Callable(self, "_on_protocol_tree_exiting")
	var added_player_state := false
	var added_command_ack := false
	if not protocol.is_connected("player_state_received", player_state_callable):
		var player_state_error := protocol.connect("player_state_received", player_state_callable)
		if player_state_error != OK:
			return false
		added_player_state = true
	if not protocol.is_connected("command_acknowledged", command_ack_callable):
		var command_ack_error := protocol.connect("command_acknowledged", command_ack_callable)
		if command_ack_error != OK:
			if added_player_state:
				protocol.disconnect("player_state_received", player_state_callable)
			return false
		added_command_ack = true
	if not protocol.tree_exiting.is_connected(tree_exit_callable):
		var tree_exit_error := protocol.tree_exiting.connect(tree_exit_callable, CONNECT_ONE_SHOT)
		if tree_exit_error != OK:
			if added_command_ack:
				protocol.disconnect("command_acknowledged", command_ack_callable)
			if added_player_state:
				protocol.disconnect("player_state_received", player_state_callable)
			return false

	# The candidate is valid and subscribed; now swap the active binding.
	_unbind_protocol()
	_protocol = protocol
	return true


func _unbind_protocol() -> void:
	if not is_instance_valid(_protocol):
		_protocol = null
		return

	var player_state_callable := Callable(self, "_on_player_state_received")
	var command_ack_callable := Callable(self, "_on_command_acknowledged")
	var tree_exit_callable := Callable(self, "_on_protocol_tree_exiting")
	if _protocol.is_connected("player_state_received", player_state_callable):
		_protocol.disconnect("player_state_received", player_state_callable)
	if _protocol.is_connected("command_acknowledged", command_ack_callable):
		_protocol.disconnect("command_acknowledged", command_ack_callable)
	if _protocol.tree_exiting.is_connected(tree_exit_callable):
		_protocol.tree_exiting.disconnect(tree_exit_callable)
	_protocol = null


func _on_protocol_tree_exiting() -> void:
	_protocol = null


func _on_player_state_received(state: Dictionary) -> void:
	_apply_authoritative_player_state(state)
	if _current_state == GameState.MENU or _current_state == GameState.CINEMATIC:
		set_game_state(GameState.OVERWORLD)


func _on_command_acknowledged(_request_id: String, message: Dictionary) -> void:
	var state_debug: Variant = message.get("state")
	var inventory_debug: Variant = state_debug.get("inventory") if state_debug is Dictionary else null
	var state: Variant = message.get("state")
	if state is Dictionary:
		_apply_authoritative_player_state(state)
	elif message.has("inventory") or message.has("gold") or message.has("triumphBadges"):
		_apply_authoritative_player_state(message)


func _apply_authoritative_player_state(state: Dictionary) -> void:
	var inventory: Variant = state.get("inventory")
	if inventory is Dictionary:
		_apply_inventory_resource("wood", inventory, "resource.wood")
		_apply_inventory_resource("steel", inventory, "resource.steel")
		_apply_inventory_resource("food", inventory, "resource.food")
		_apply_inventory_resource("pearls", inventory, "resource.pearls")

	var gold: Variant = _parse_nonnegative_integer(state.get("gold"))
	if gold != null:
		_set_authoritative_resource("doubloons", int(gold))

	var badges_value: Variant = state.get("triumphBadges", state.get("triumph_badges"))
	var badges: Variant = _parse_nonnegative_integer(badges_value)
	if badges != null:
		_set_authoritative_resource("triumph_badges", int(badges))


func _apply_inventory_resource(resource_type: String, inventory: Dictionary, item_id: String) -> void:
	var amount: Variant = _parse_nonnegative_integer(inventory.get(item_id, 0))
	if amount == null:
		return
	_set_authoritative_resource(resource_type, int(amount))


func _parse_nonnegative_integer(value: Variant) -> Variant:
	if value is int:
		return value if value >= 0 else null
	if value is String and value.is_valid_int():
		var parsed: int = value.to_int()
		return parsed if parsed >= 0 else null
	return null


func _set_authoritative_resource(resource_type: String, amount: int) -> void:
	if not _player_resources.has(resource_type):
		return
	if int(_player_resources[resource_type]) == amount:
		return
	_player_resources[resource_type] = amount
	resource_updated.emit(resource_type, amount)


func check_citadel_soft_wall(target_level: int, _caller_badges: int) -> bool:
	# This is a UI preview only. The server must re-check all requirements when
	# processing an actual citadel upgrade command. The caller's badge count is
	# retained for API compatibility but cannot override or veto server state.
	if target_level < 1:
		return false
	if target_level < SOFT_WALL_TARGET_LEVEL:
		return true
	if target_level != SOFT_WALL_TARGET_LEVEL:
		return false

	var has_badge_override: bool = get_resource_amount("triumph_badges") >= SOFT_WALL_BADGES
	var has_resource_requirements: bool = (
		get_resource_amount("wood") >= SOFT_WALL_WOOD
		and get_resource_amount("steel") >= SOFT_WALL_STEEL
		and get_resource_amount("food") >= SOFT_WALL_FOOD
	)
	if has_badge_override or has_resource_requirements:
		return true

	soft_wall_reached.emit()
	return false
