extends CharacterBody3D

## Client presentation/input adapter for the server-authoritative player.
## Position, health, hunger, oxygen, stamina, inventory and hotbar state are
## projections of server snapshots. This node sends intents only; it never
## predicts movement or mutates survival/economy state locally.

signal player_died
signal survival_state_changed(health: float, hunger: float, oxygen: float, stamina: float)
signal hotbar_changed(hotbar: Array, selected_slot: int)
signal combat_result_received(request_id: String, result: Dictionary)

const HOTBAR_SLOT_COUNT := 8
const MAX_TARGET_ID_LENGTH := 128
const MIN_DIRECTION_LENGTH_SQUARED := 0.000001
const WEAPON_ITEMS := ["cutlass", "flintlock", "harpoon"]
const GATHER_TOOL_ITEM := "shovel"
const MAX_PLAYER_STAT := 100.0

var health := MAX_PLAYER_STAT
var hunger := MAX_PLAYER_STAT
var oxygen := MAX_PLAYER_STAT
var stamina := MAX_PLAYER_STAT
var max_stamina := MAX_PLAYER_STAT
var hotbar: Array = []
var selected_hotbar_slot := 0
var server_position := Vector2.ZERO

var _protocol: Node
var _dead := false
var _fallback_visual: MeshInstance3D


func _ready() -> void:
	# The server owns collision and movement resolution. The CharacterBody3D is
	# a presentation root; no local move_and_slide() or survival timer runs here.
	collision_layer = 0
	collision_mask = 0
	ensure_fallback_visual()


func set_protocol(protocol: Node) -> bool:
	_unbind_protocol()
	if protocol == null:
		return true
	for method_name in ["request_move", "request_select_hotbar", "request_attack", "request_gather"]:
		if not protocol.has_method(method_name):
			return false
	_protocol = protocol
	if protocol.has_signal("combat_result_received"):
		var callback := Callable(self, "_on_combat_result_received")
		if not protocol.is_connected("combat_result_received", callback):
			if protocol.connect("combat_result_received", callback) != OK:
				_unbind_protocol()
				return false
	return true


func _unbind_protocol() -> void:
	if not is_instance_valid(_protocol):
		_protocol = null
		return
	var callback := Callable(self, "_on_combat_result_received")
	if _protocol.has_signal("combat_result_received") and _protocol.is_connected("combat_result_received", callback):
		_protocol.disconnect("combat_result_received", callback)
	_protocol = null


## Sends a normalized 8-way direction only. The server computes position and
## speed from its own monotonic clock and terrain state.
func request_move_intent(direction: Vector2) -> bool:
	if not is_instance_valid(_protocol) or not _protocol.has_method("request_move"):
		return false
	if not is_finite(direction.x) or not is_finite(direction.y):
		return false
	var direction_length := direction.length()
	if not is_finite(direction_length) or direction_length < sqrt(MIN_DIRECTION_LENGTH_SQUARED):
		return false
	var normalized := direction / direction_length
	return bool(_protocol.call("request_move", normalized.x, normalized.y))


## Selection is confirmed only by the next authoritative player_state snapshot.
func select_hotbar_slot(slot: int) -> bool:
	if slot < 0 or slot >= HOTBAR_SLOT_COUNT:
		return false
	if not is_instance_valid(_protocol) or not _protocol.has_method("request_select_hotbar"):
		return false
	return bool(_protocol.call("request_select_hotbar", slot))


## Executes the currently server-selected hotbar item. Weapon actions go through
## the server attack command; shovel is the existing gather_resource action.
## The server still validates the target, range, cooldown, ammo and inventory.
func use_selected_hotbar(target_id: String, facing: Vector2) -> String:
	if target_id.is_empty() or target_id.length() > MAX_TARGET_ID_LENGTH:
		return ""
	if not is_instance_valid(_protocol):
		return ""
	if selected_hotbar_slot < 0 or selected_hotbar_slot >= hotbar.size():
		return ""
	var item_id: Variant = hotbar[selected_hotbar_slot]
	if not item_id is String:
		return ""
	if WEAPON_ITEMS.has(item_id):
		if not is_finite(facing.x) or not is_finite(facing.y):
			return ""
		var facing_length := facing.length()
		if not is_finite(facing_length) or facing_length < sqrt(MIN_DIRECTION_LENGTH_SQUARED):
			return ""
		var direction := facing / facing_length
		var attack_id: Variant = _protocol.call("request_attack", target_id, direction.x, direction.y)
		return attack_id if attack_id is String else ""
	if item_id == GATHER_TOOL_ITEM:
		var gather_id: Variant = _protocol.call("request_gather", target_id)
		return gather_id if gather_id is String else ""
	return ""


## Applies a server snapshot. Missing or malformed fields never overwrite the
## last known value. This method deliberately contains no local decay/damage.
func apply_authoritative_state(state: Dictionary) -> void:
	var previous_health := health
	var previous_hunger := hunger
	var previous_oxygen := oxygen
	var previous_stamina := stamina
	var previous_hotbar := hotbar.duplicate(true)
	var previous_slot := selected_hotbar_slot

	health = _bounded_stat(state.get("health"), health)
	hunger = _bounded_stat(state.get("hunger"), hunger)
	oxygen = _bounded_stat(state.get("oxygen"), oxygen)
	stamina = _bounded_stat(state.get("stamina"), stamina)
	max_stamina = _bounded_stat(state.get("maxStamina", state.get("max_stamina")), max_stamina)
	stamina = minf(stamina, max_stamina)

	var x_value: Variant = state.get("x")
	var y_value: Variant = state.get("y")
	if _is_finite_number(x_value) and _is_finite_number(y_value):
		server_position = Vector2(float(x_value), float(y_value))

	var hotbar_value: Variant = state.get("hotbar")
	if hotbar_value is Array:
		var normalized_hotbar: Array = []
		for index in HOTBAR_SLOT_COUNT:
			var item: Variant = hotbar_value[index] if index < hotbar_value.size() else null
			normalized_hotbar.append(item if item is String and not item.is_empty() else null)
		hotbar = normalized_hotbar

	var selected_value: Variant = state.get("selectedHotbarSlot", state.get("selected_hotbar_slot", selected_hotbar_slot))
	if selected_value is int and selected_value >= 0 and selected_value < HOTBAR_SLOT_COUNT:
		selected_hotbar_slot = selected_value

	if health <= 0.0 and not _dead:
		_dead = true
		player_died.emit()
	elif health > 0.0:
		_dead = false

	if not is_equal_approx(previous_health, health) \
			or not is_equal_approx(previous_hunger, hunger) \
			or not is_equal_approx(previous_oxygen, oxygen) \
			or not is_equal_approx(previous_stamina, stamina):
		survival_state_changed.emit(health, hunger, oxygen, stamina)
	if hotbar != previous_hotbar or selected_hotbar_slot != previous_slot:
		hotbar_changed.emit(hotbar.duplicate(true), selected_hotbar_slot)


## Reuses an existing visual (including PlayerAvatar's rig/capsule) or creates
## a neutral capsule only when no MeshInstance3D has been assigned.
func ensure_fallback_visual() -> MeshInstance3D:
	var existing := _find_mesh_instance(self)
	if existing != null:
		_fallback_visual = existing
		return existing
	var fallback := MeshInstance3D.new()
	fallback.name = "FallbackBody"
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	fallback.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#d9a441")
	material.roughness = 0.72
	fallback.material_override = material
	add_child(fallback)
	_fallback_visual = fallback
	return fallback


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
		var nested := _find_mesh_instance(child)
		if nested != null:
			return nested
	return null


func _bounded_stat(value: Variant, fallback: float) -> float:
	if not _is_finite_number(value):
		return fallback
	return clampf(float(value), 0.0, MAX_PLAYER_STAT)


func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _on_combat_result_received(request_id: String, result: Dictionary) -> void:
	combat_result_received.emit(request_id, result.duplicate(true))
