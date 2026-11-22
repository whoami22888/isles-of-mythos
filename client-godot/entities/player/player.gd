class_name IslesPlayerController
extends CharacterBody3D

signal player_died
signal vitals_changed(health: float, hunger: float, oxygen: float)
signal hotbar_changed(items: Array, selected_slot: int)
signal hotbar_action_acknowledged(request_id: String, item_id: String, message: Dictionary)
signal hotbar_action_rejected(request_id: String, item_id: String, code: String)
signal hotbar_action_outcome_unknown(request_id: String, item_id: String)

const MAX_VITAL := 100.0
const HOTBAR_SIZE := 8
const COMBAT_ITEMS := ["cutlass", "flintlock", "harpoon"]

@export var visual_root: Node3D

var _health := MAX_VITAL
var health: float:
	get:
		return _health

var _hunger := MAX_VITAL
var hunger: float:
	get:
		return _hunger

var _oxygen := MAX_VITAL
var oxygen: float:
	get:
		return _oxygen

var _hotbar: Array[String] = []
var hotbar: Array[String]:
	get:
		return _hotbar.duplicate()

var _selected_hotbar_slot := 0
var selected_hotbar_slot: int:
	get:
		return _selected_hotbar_slot

var _protocol: Node
var _protocol_callbacks: Dictionary = {}
var _touch_controls: Node
var _touch_callback := Callable()
var _touch_direction := Vector2.ZERO
var _hotbar_requests: Dictionary = {}
var _has_authoritative_state := false
var _death_notified := false


func _ready() -> void:
	_ensure_fallback_visual()


func _exit_tree() -> void:
	_unbind_protocol()
	_unbind_touch_controls()


## Binds only to the existing authenticated protocol surface. The controller
## never changes persistent state locally; it sends intent and projects ACKs.
func bind_protocol(protocol: Node) -> bool:
	if protocol == null:
		_unbind_protocol()
		return true
	if not is_instance_valid(protocol) or protocol == _protocol:
		return is_instance_valid(protocol)

	for signal_name in [
		"player_state_received",
		"command_acknowledged",
		"command_rejected",
		"command_outcome_unknown",
		"attack_rejected",
		"attack_outcome_unknown",
	]:
		if not protocol.has_signal(signal_name):
			return false
	for method_name in [
		"is_authenticated",
		"request_select_hotbar",
		"request_attack",
		"request_gather",
	]:
		if not protocol.has_method(method_name):
			return false

	var callbacks := {
		"player_state_received": Callable(self, "_on_player_state_received"),
		"command_acknowledged": Callable(self, "_on_command_acknowledged"),
		"command_rejected": Callable(self, "_on_command_rejected"),
		"command_outcome_unknown": Callable(self, "_on_command_outcome_unknown"),
		"attack_rejected": Callable(self, "_on_attack_rejected"),
		"attack_outcome_unknown": Callable(self, "_on_attack_outcome_unknown"),
	}
	var added: Array = []
	for signal_name in callbacks:
		var callback: Callable = callbacks[signal_name]
		if protocol.is_connected(signal_name, callback):
			continue
		var error := protocol.connect(signal_name, callback)
		if error != OK:
			for pair in added:
				if protocol.is_connected(pair[0], pair[1]):
					protocol.disconnect(pair[0], pair[1])
			return false
		added.append([signal_name, callback])

	_unbind_protocol()
	_protocol = protocol
	_protocol_callbacks = callbacks
	return true


func _unbind_protocol() -> void:
	if is_instance_valid(_protocol):
		for signal_name in _protocol_callbacks:
			var callback: Callable = _protocol_callbacks[signal_name]
			if _protocol.is_connected(signal_name, callback):
				_protocol.disconnect(signal_name, callback)
	_protocol = null
	_protocol_callbacks.clear()
	for request_id in _hotbar_requests:
		hotbar_action_outcome_unknown.emit(str(request_id), str(_hotbar_requests[request_id]))
	_hotbar_requests.clear()


## The existing TouchControls joystick is the only touch movement source.
## Keyboard and joystick vectors are combined and clamped, never applied locally.
func bind_touch_controls(controls: Node) -> bool:
	if controls == null:
		_unbind_touch_controls()
		return true
	if not is_instance_valid(controls) or not controls.has_signal("joystick_changed"):
		return false
	if controls == _touch_controls:
		return true
	var callback := Callable(self, "set_touch_direction")
	if not controls.is_connected("joystick_changed", callback):
		var error := controls.connect("joystick_changed", callback)
		if error != OK:
			return false
	_unbind_touch_controls()
	_touch_controls = controls
	_touch_callback = callback
	if controls.has_method("joystick_vector"):
		set_touch_direction(controls.call("joystick_vector"))
	return true


func _unbind_touch_controls() -> void:
	if is_instance_valid(_touch_controls) and _touch_callback.is_valid():
		if _touch_controls.is_connected("joystick_changed", _touch_callback):
			_touch_controls.disconnect("joystick_changed", _touch_callback)
	_touch_controls = null
	_touch_callback = Callable()
	_touch_direction = Vector2.ZERO


func set_touch_direction(direction: Vector2) -> void:
	if not is_finite(direction.x) or not is_finite(direction.y):
		_touch_direction = Vector2.ZERO
		return
	_touch_direction = direction.limit_length(1.0)


func movement_intent(allow_keyboard: bool = true) -> Vector2:
	var direction := _touch_direction
	if allow_keyboard:
		direction += Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return direction.limit_length(1.0)


## Applies only server-authored coordinates and vitals. Hunger/oxygen decay and
## damage remain in server/src/player.ts; this client never predicts survival.
func apply_authoritative_state(state: Dictionary) -> bool:
	var changed := false
	var raw_x: Variant = state.get("x")
	var raw_y: Variant = state.get("y")
	if _is_finite_number(raw_x) and _is_finite_number(raw_y):
		var next_position := global_position
		next_position.x = float(raw_x)
		next_position.z = float(raw_y)
		if next_position != global_position:
			global_position = next_position
			changed = true

	var next_health := _bounded_vital(state.get("health", _health), _health)
	var next_hunger := _bounded_vital(state.get("hunger", _hunger), _hunger)
	var next_oxygen := _bounded_vital(state.get("oxygen", _oxygen), _oxygen)
	var vitals_changed_now := (
		next_health != _health
		or next_hunger != _hunger
		or next_oxygen != _oxygen
	)
	_health = next_health
	_hunger = next_hunger
	_oxygen = next_oxygen
	if vitals_changed_now:
		vitals_changed.emit(_health, _hunger, _oxygen)
		changed = true

	if _health <= 0.0:
		if not _death_notified:
			_death_notified = true
			player_died.emit()
	else:
		_death_notified = false

	var raw_hotbar: Variant = state.get("hotbar")
	if raw_hotbar is Array:
		var next_hotbar: Array[String] = []
		for slot_index in range(HOTBAR_SIZE):
			var item: Variant = raw_hotbar[slot_index] if slot_index < raw_hotbar.size() else null
			next_hotbar.append(item if item is String and item.length() <= 64 else "")
		var raw_selected: Variant = state.get("selectedHotbarSlot", state.get("selected_hotbar_slot", _selected_hotbar_slot))
		var next_selected := _selected_hotbar_slot
		if raw_selected is int and raw_selected >= 0 and raw_selected < HOTBAR_SIZE:
			next_selected = raw_selected
		if next_hotbar != _hotbar or next_selected != _selected_hotbar_slot:
			_hotbar = next_hotbar
			_selected_hotbar_slot = next_selected
			hotbar_changed.emit(_hotbar.duplicate(), _selected_hotbar_slot)
			changed = true

	_has_authoritative_state = true
	return changed


func select_hotbar_slot(slot: int) -> bool:
	if not _has_authoritative_state or _hotbar.is_empty() or slot < 0 or slot >= _hotbar.size():
		return false
	if not _can_send():
		return false
	return bool(_protocol.call("request_select_hotbar", slot))


## Weapons use the existing server attack command. Shovel is a gather tool and
## maps to the existing server gather_resource command; no client-side inventory
## or resource mutation is performed.
func use_selected_hotbar_item(
	target_id: String = "",
	resource_id: String = "",
	facing: Vector2 = Vector2.RIGHT
) -> bool:
	if not _has_authoritative_state or _health <= 0.0 or not _can_send():
		return false
	if _selected_hotbar_slot < 0 or _selected_hotbar_slot >= _hotbar.size():
		return false
	var item_id := _hotbar[_selected_hotbar_slot]
	if COMBAT_ITEMS.has(item_id):
		var target := target_id.strip_edges()
		if target.is_empty() or target.length() > 128:
			return false
		if not is_finite(facing.x) or not is_finite(facing.y) or facing.length_squared() <= 0.000001:
			return false
		var direction := facing.normalized()
		var request_id := str(_protocol.call("request_attack", target, direction.x, direction.y))
		if request_id.is_empty():
			return false
		_hotbar_requests[request_id] = item_id
		return true
	if item_id == "shovel":
		var resource := resource_id.strip_edges()
		if resource.is_empty() or resource.length() > 128:
			return false
		var request_id := str(_protocol.call("request_gather", resource))
		if request_id.is_empty():
			return false
		_hotbar_requests[request_id] = item_id
		return true
	return false


func _can_send() -> bool:
	return is_instance_valid(_protocol) and bool(_protocol.call("is_authenticated"))


func _on_player_state_received(state: Dictionary) -> void:
	apply_authoritative_state(state)


func _on_command_acknowledged(request_id: String, message: Dictionary) -> void:
	if _hotbar_requests.has(request_id):
		var item_id := str(_hotbar_requests[request_id])
		_hotbar_requests.erase(request_id)
		hotbar_action_acknowledged.emit(request_id, item_id, message)


func _on_command_rejected(request_id: String, code: String) -> void:
	_resolve_hotbar_rejection(request_id, code)


func _on_attack_rejected(request_id: String, code: String) -> void:
	_resolve_hotbar_rejection(request_id, code)


func _resolve_hotbar_rejection(request_id: String, code: String) -> void:
	if not _hotbar_requests.has(request_id):
		return
	var item_id := str(_hotbar_requests[request_id])
	_hotbar_requests.erase(request_id)
	hotbar_action_rejected.emit(request_id, item_id, code)


func _on_command_outcome_unknown(request_id: String) -> void:
	_resolve_hotbar_unknown(request_id)


func _on_attack_outcome_unknown(request_id: String) -> void:
	_resolve_hotbar_unknown(request_id)


func _resolve_hotbar_unknown(request_id: String) -> void:
	if not _hotbar_requests.has(request_id):
		return
	var item_id := str(_hotbar_requests[request_id])
	_hotbar_requests.erase(request_id)
	hotbar_action_outcome_unknown.emit(request_id, item_id)


func _bounded_vital(value: Variant, fallback: float) -> float:
	if not _is_finite_number(value):
		return fallback
	return clampf(float(value), 0.0, MAX_VITAL)


func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _ensure_fallback_visual() -> void:
	var root: Node3D = visual_root if visual_root != null else self
	if _contains_visible_visual(root):
		return
	var fallback := MeshInstance3D.new()
	fallback.name = "FallbackVisual"
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	fallback.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#4edce3")
	material.roughness = 0.9
	fallback.material_override = material
	fallback.position.y = 0.9
	root.add_child(fallback)
	push_warning("PlayerController is using a diagnostic capsule fallback; this is not production character art.")


func _contains_visible_visual(node: Node) -> bool:
	if node is VisualInstance3D and (node as VisualInstance3D).visible:
		return true
	for child in node.get_children():
		if child is Node and _contains_visible_visual(child):
			return true
	return false
