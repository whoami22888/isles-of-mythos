extends CharacterBody3D

## Server-authoritative proxy: input creates intents; only server snapshots move it.
## Survival and hotbar values are read-only projections of server state.

signal gather_requested
signal survival_changed(health: float, hunger: float, oxygen: float)

const PlayerAvatarScript = preload("res://gameplay/player_avatar.gd")
const HOTBAR_SIZE := 8
const HOTBAR_ITEM_IDS := ["cutlass", "flintlock", "harpoon", "shovel"]
const SURVIVAL_MAX := 100.0

var feet_offset := 0.9
var _avatar: Node3D
var _touch_controls: Node
var _protocol: Node
var _health := 100.0
var _hunger := 100.0
var _oxygen := 100.0
var _has_server_state := false
var _hotbar: Array[String] = ["", "", "", "", "", "", "", ""]
var _selected_hotbar_slot := 0
var _survival_panel: PanelContainer
var _hotbar_panel: PanelContainer
var _survival_labels: Dictionary = {}
var _survival_bars: Dictionary = {}
var _hotbar_buttons: Array[Button] = []
var _use_button: Button

func _ready() -> void:
	# Presentation proxy only: no collision authority and no move_and_slide().
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_avatar = PlayerAvatarScript.new()
	_avatar.name = "PlayerAvatar"
	_avatar.set("feet_offset", feet_offset)
	add_child(_avatar)
	_ensure_fallback_visual()
	_build_hud()

func bind_touch_controls(controls: Node) -> void:
	_touch_controls = controls if is_instance_valid(controls) else null

func bind_protocol(protocol: Node) -> void:
	_protocol = protocol if is_instance_valid(protocol) else null

func movement_intent(camera_yaw: float) -> Vector2:
	var keyboard := Vector2.ZERO
	var viewport := get_viewport()
	var focus := viewport.gui_get_focus_owner() if viewport != null else null
	if not (focus is LineEdit):
		keyboard = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var joystick := Vector2.ZERO
	if is_instance_valid(_touch_controls) and _touch_controls.has_method("joystick_vector"):
		var value: Variant = _touch_controls.call("joystick_vector")
		if value is Vector2:
			joystick = value
	return movement_vector_for(keyboard, joystick, camera_yaw)

static func movement_vector_for(keyboard: Vector2, joystick: Vector2, camera_yaw: float) -> Vector2:
	var screen := keyboard + joystick
	if not is_finite(screen.x) or not is_finite(screen.y) or not is_finite(camera_yaw):
		return Vector2.ZERO
	if screen.length_squared() < 0.00000001:
		return Vector2.ZERO
	return screen.normalized().rotated(-camera_yaw)

func set_server_position(world_position: Vector3) -> void:
	if not is_finite(world_position.x) or not is_finite(world_position.y) or not is_finite(world_position.z):
		return
	position = world_position
	velocity = Vector3.ZERO
	observe_server_position(world_position)

func observe_server_position(world_position: Vector3) -> void:
	if is_instance_valid(_avatar) and _avatar.has_method("observe_server_position"):
		_avatar.call("observe_server_position", world_position)

func apply_server_state(state: Dictionary) -> void:
	var previous_health := _health
	var previous_hunger := _hunger
	var previous_oxygen := _oxygen
	_health = _read_percent(state, "health", _health)
	_hunger = _read_percent(state, "hunger", _hunger)
	_oxygen = _read_percent(state, "oxygen", _oxygen)
	_has_server_state = true
	var raw_hotbar: Variant = state.get("hotbar")
	if raw_hotbar is Array:
		var next_hotbar: Array[String] = ["", "", "", "", "", "", "", ""]
		for slot in range(mini(HOTBAR_SIZE, raw_hotbar.size())):
			var item: Variant = raw_hotbar[slot]
			if item is String and HOTBAR_ITEM_IDS.has(item):
				next_hotbar[slot] = item
		_hotbar = next_hotbar
	var selected: Variant = state.get("selectedHotbarSlot")
	if selected is int and selected >= 0 and selected < HOTBAR_SIZE:
		_selected_hotbar_slot = selected
	_update_survival_ui()
	_update_hotbar_ui()
	if not is_equal_approx(previous_health, _health) or not is_equal_approx(previous_hunger, _hunger) or not is_equal_approx(previous_oxygen, _oxygen):
		survival_changed.emit(_health, _hunger, _oxygen)

static func _read_percent(state: Dictionary, key: String, fallback: float) -> float:
	var raw: Variant = state.get(key, null)
	if raw is int or raw is float:
		var value := float(raw)
		if is_finite(value):
			return clampf(value, 0.0, SURVIVAL_MAX)
	return fallback

func get_survival_values() -> Dictionary:
	return {"has_server_state": _has_server_state, "health": _health, "hunger": _hunger, "oxygen": _oxygen}

func get_hotbar_item(slot: int) -> String:
	if slot < 0 or slot >= HOTBAR_SIZE:
		return ""
	return _hotbar[slot]

func get_selected_hotbar_slot() -> int:
	return _selected_hotbar_slot

func select_hotbar_slot(slot: int) -> bool:
	if slot < 0 or slot >= HOTBAR_SIZE or not _has_server_state or _hotbar[slot].is_empty():
		return false
	if not is_instance_valid(_protocol) or not _protocol.has_method("request_select_hotbar"):
		return false
	# Wait for the next server snapshot; never optimistically change selection.
	return bool(_protocol.call("request_select_hotbar", slot))

func use_selected_tool() -> bool:
	if not _has_server_state or _hotbar[_selected_hotbar_slot] != "shovel":
		return false
	gather_requested.emit()
	return true

func has_fallback_visual() -> bool:
	return (
		not find_children("*", "MeshInstance3D", true, false).is_empty()
		or not find_children("*", "Sprite3D", true, false).is_empty()
	)

func get_blocked_controls() -> Array[Control]:
	var blocked: Array[Control] = []
	if is_instance_valid(_survival_panel):
		blocked.append(_survival_panel)
	if is_instance_valid(_hotbar_panel):
		blocked.append(_hotbar_panel)
	return blocked

static func hotbar_slot_for_key(keycode: int) -> int:
	if keycode < KEY_1 or keycode > KEY_8:
		return -1
	return keycode - KEY_1


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var viewport := get_viewport()
	var focus := viewport.gui_get_focus_owner() if viewport != null else null
	if focus is LineEdit:
		return
	var hotbar_slot := hotbar_slot_for_key(event.keycode)
	if hotbar_slot >= 0:
		select_hotbar_slot(hotbar_slot)
		viewport.set_input_as_handled()
	elif event.keycode == KEY_E and use_selected_tool():
		viewport.set_input_as_handled()

func _ensure_fallback_visual() -> void:
	if has_fallback_visual():
		return
	var fallback := MeshInstance3D.new()
	fallback.name = "FallbackCapsule"
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	fallback.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#d9a441")
	fallback.material_override = material
	add_child(fallback)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PlayerHud"
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_survival_panel = PanelContainer.new()
	_survival_panel.name = "SurvivalPanel"
	_survival_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_survival_panel.offset_left = -224.0
	_survival_panel.offset_top = 18.0
	_survival_panel.offset_right = -18.0
	_survival_panel.offset_bottom = 146.0
	_survival_panel.custom_minimum_size = Vector2(206.0, 128.0)
	root.add_child(_survival_panel)
	var survival_column := VBoxContainer.new()
	survival_column.add_theme_constant_override("separation", 3)
	_survival_panel.add_child(survival_column)
	_add_survival_row(survival_column, "health", "Health")
	_add_survival_row(survival_column, "hunger", "Hunger")
	_add_survival_row(survival_column, "oxygen", "Oxygen")
	_hotbar_panel = PanelContainer.new()
	_hotbar_panel.name = "HotbarPanel"
	_hotbar_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hotbar_panel.offset_left = -442.0
	_hotbar_panel.offset_top = -128.0
	_hotbar_panel.offset_right = -18.0
	_hotbar_panel.offset_bottom = -12.0
	_hotbar_panel.custom_minimum_size = Vector2(424.0, 116.0)
	root.add_child(_hotbar_panel)
	var hotbar_column := VBoxContainer.new()
	hotbar_column.add_theme_constant_override("separation", 4)
	_hotbar_panel.add_child(hotbar_column)
	var first_row := HBoxContainer.new()
	first_row.alignment = BoxContainer.ALIGNMENT_CENTER
	first_row.add_theme_constant_override("separation", 4)
	hotbar_column.add_child(first_row)
	var second_row := HBoxContainer.new()
	second_row.alignment = BoxContainer.ALIGNMENT_CENTER
	second_row.add_theme_constant_override("separation", 4)
	hotbar_column.add_child(second_row)
	for slot in range(HOTBAR_SIZE):
		var button := Button.new()
		button.name = "HotbarSlot%d" % (slot + 1)
		button.custom_minimum_size = Vector2(74.0, 44.0)
		button.add_theme_font_size_override("font_size", 11)
		button.toggle_mode = true
		button.text = "%d Empty" % (slot + 1)
		button.pressed.connect(_on_hotbar_pressed.bind(slot))
		_hotbar_buttons.append(button)
		if slot < 4:
			first_row.add_child(button)
		else:
			second_row.add_child(button)
	_use_button = Button.new()
	_use_button.name = "UseSelectedTool"
	_use_button.custom_minimum_size = Vector2(92.0, 44.0)
	_use_button.add_theme_font_size_override("font_size", 11)
	_use_button.text = "Gather"
	_use_button.disabled = true
	_use_button.pressed.connect(use_selected_tool)
	second_row.add_child(_use_button)
	_update_survival_ui()
	_update_hotbar_ui()

func _add_survival_row(container: VBoxContainer, key: String, title: String) -> void:
	var label := Label.new()
	label.text = title + " —"
	container.add_child(label)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = SURVIVAL_MAX
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(176.0, 12.0)
	container.add_child(bar)
	_survival_labels[key] = label
	_survival_bars[key] = bar

func _update_survival_ui() -> void:
	for key in ["health", "hunger", "oxygen"]:
		var label := _survival_labels.get(key) as Label
		var bar := _survival_bars.get(key) as ProgressBar
		if label == null or bar == null:
			continue
		if not _has_server_state:
			label.text = key.capitalize() + " —"
			bar.value = 0.0
		else:
			var value := float(get_survival_values()[key])
			label.text = "%s %d / 100" % [key.capitalize(), roundi(value)]
			bar.value = value

func _update_hotbar_ui() -> void:
	for slot in range(HOTBAR_SIZE):
		if slot >= _hotbar_buttons.size():
			continue
		var button := _hotbar_buttons[slot]
		var item := _hotbar[slot]
		button.text = "%d %s" % [slot + 1, "Empty" if item.is_empty() else item.capitalize()]
		button.disabled = not _has_server_state or item.is_empty()
		button.button_pressed = slot == _selected_hotbar_slot
	if is_instance_valid(_use_button):
		_use_button.disabled = not _has_server_state or _hotbar[_selected_hotbar_slot] != "shovel"

func _on_hotbar_pressed(slot: int) -> void:
	select_hotbar_slot(slot)
