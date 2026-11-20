extends CanvasLayer
## Outpost HUD: resource strip, camp title + objective line, context action,
## build menu, joystick, and loot flying to the resource chips.

const FONT_PATH := "res://assets/fonts/PirataOne-Regular.ttf"
const ORDER := ["mill", "dock", "palisade", "forge", "watchtower", "barracks"]

var world: Node
var _font: Font
var _stick := Vector2.ZERO
var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _chips := {}
var _counts := {}
var _shown := {}
var _camp: Label
var _objective: Label
var _action: Button
var _build_btn: Button
var _menu: PanelContainer
var _menu_box: VBoxContainer
var _rows := {}
var _toast: Label
var _toast_t := 0.0
var _flies: Array = []
var _tags: Array = []
## Below the resource strip, camp line and objective line.
const TAG_TOP := 150.0


func _ready() -> void:
	layer = 5
	_font = load(FONT_PATH)
	var top := HBoxContainer.new()
	top.position = Vector2(24, 18)
	top.add_theme_constant_override("separation", 14)
	add_child(top)
	for kind in ["wood", "stone", "food", "iron"]:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _box(Color(0.1, 0.08, 0.06, 0.72)))
		var lab := _label(30)
		lab.text = "%s 0" % kind.capitalize()
		chip.add_child(lab)
		top.add_child(chip)
		_chips[kind] = chip
		_counts[kind] = lab
	_camp = _label(26)
	_camp.position = Vector2(26, 76)
	add_child(_camp)
	_objective = _label(30)
	_objective.position = Vector2(26, 108)
	_objective.add_theme_color_override("font_color", Color(1.0, 0.9, 0.62))
	add_child(_objective)
	_action = _button("", 34)
	_action.anchor_left = 1.0
	_action.anchor_right = 1.0
	_action.anchor_top = 1.0
	_action.anchor_bottom = 1.0
	_action.offset_left = -330
	_action.offset_right = -40
	_action.offset_top = -190
	_action.offset_bottom = -90
	_action.pressed.connect(func(): if world: world.on_action())
	add_child(_action)
	_build_btn = _button("Build", 30)
	_build_btn.anchor_left = 1.0
	_build_btn.anchor_right = 1.0
	_build_btn.offset_left = -190
	_build_btn.offset_right = -30
	_build_btn.offset_top = 20
	_build_btn.offset_bottom = 84
	_build_btn.pressed.connect(func(): _menu.visible = not _menu.visible)
	add_child(_build_btn)
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", _box(Color(0.09, 0.07, 0.05, 0.88)))
	_menu.anchor_left = 1.0
	_menu.anchor_right = 1.0
	_menu.offset_left = -640
	_menu.offset_right = -30
	_menu.offset_top = 96
	_menu.visible = false
	add_child(_menu)
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 6)
	_menu.add_child(_menu_box)
	for id in ["camp"] + ORDER:
		var row := HBoxContainer.new()
		var info := _label(24)
		info.custom_minimum_size = Vector2(420, 0)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var go := _button("Build", 24)
		go.custom_minimum_size = Vector2(150, 56)
		go.pressed.connect(func(): if world: world.on_build(id))
		row.add_child(info)
		row.add_child(go)
		_menu_box.add_child(row)
		_rows[id] = [info, go]
	_toast = _label(30)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -400
	_toast.offset_right = 400
	_toast.offset_top = 170
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_toast)


func _box(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.border_color = Color(0.55, 0.42, 0.26, 0.6)
	sb.set_border_width_all(2)
	return sb


func _label(size: int) -> Label:
	var lab := Label.new()
	if _font:
		lab.add_theme_font_override("font", _font)
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", Color(0.97, 0.93, 0.84))
	lab.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.9))
	lab.add_theme_constant_override("outline_size", 8)
	return lab


func _button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", _box(Color(0.24, 0.17, 0.1, 0.9)))
	b.add_theme_stylebox_override("hover", _box(Color(0.3, 0.21, 0.12, 0.92)))
	b.add_theme_stylebox_override("pressed", _box(Color(0.18, 0.12, 0.07, 0.95)))
	b.add_theme_stylebox_override("disabled", _box(Color(0.15, 0.13, 0.11, 0.7)))
	return b


func stick() -> Vector2:
	return _stick


func menu_open() -> bool:
	return _menu.visible


func close_menu() -> void:
	_menu.visible = false


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 3.0


## Resources fly from a screen point to their chip; the count ticks on arrival.
func fly(from: Vector2, kind: String, amount: int) -> void:
	var chip: Control = _chips.get(kind)
	if chip == null:
		return
	var lab := _label(30)
	lab.text = "+%d %s" % [amount, kind]
	lab.position = from
	add_child(lab)
	_flies.append({"node": lab, "from": from, "kind": kind, "amount": amount, "age": 0.0})


func flying() -> int:
	return _flies.size()


func push(state: Dictionary) -> void:
	var inv: Dictionary = state.get("inv", {})
	for kind in _counts.keys():
		var held := 0
		for f in _flies:
			if f["kind"] == kind:
				held += int(f["amount"])
		_counts[kind].text = "%s %d" % [kind.capitalize(), int(inv.get(kind, 0)) - held]
	_camp.text = str(state.get("camp_line", ""))
	_objective.text = "Next: " + str(state.get("objective", ""))
	var act := str(state.get("action", ""))
	_action.visible = act != ""
	_action.text = act
	_build_btn.visible = not bool(state.get("cinematic", false))
	_layout_tags(state.get("tags", []))
	var rows: Dictionary = state.get("menu", {})
	for id in _rows.keys():
		var r: Dictionary = rows.get(id, {})
		var info: Label = _rows[id][0]
		var go: Button = _rows[id][1]
		info.text = str(r.get("text", id))
		go.text = str(r.get("button", "Build"))
		go.disabled = not bool(r.get("can", false))


## Place world labels, stacking any that overlap, below the top HUD band.
func _layout_tags(tags: Array) -> void:
	while _tags.size() < tags.size():
		var lab := _label(26)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(lab)
		move_child(lab, 0)
		_tags.append(lab)
	var rect := get_viewport().get_visible_rect().size
	var placed: Array = []
	var order := range(tags.size())
	order.sort_custom(func(a, b): return (tags[a]["pos"] as Vector2).y < (tags[b]["pos"] as Vector2).y)
	for k in _tags.size():
		_tags[k].visible = k < tags.size()
	for k in order:
		var lab: Label = _tags[k]
		lab.text = str(tags[k]["text"])
		lab.add_theme_color_override("font_color", Color(1.0, 0.9, 0.62) if bool(tags[k]["focus"]) else Color(0.97, 0.93, 0.84))
		lab.size = lab.get_minimum_size()
		var p: Vector2 = tags[k]["pos"] - Vector2(lab.size.x * 0.5, lab.size.y)
		p.x = clampf(p.x, 8.0, rect.x - lab.size.x - 8.0)
		p.y = maxf(p.y, TAG_TOP)
		var moved := true
		var guard := 0
		while moved and guard < 8:
			moved = false
			guard += 1
			for r in placed:
				if Rect2(p, lab.size).grow(4.0).intersects(r):
					p.y = (r as Rect2).end.y + 4.0
					moved = true
		lab.position = p
		placed.append(Rect2(p, lab.size))


func tag_rects() -> Array:
	var out: Array = []
	for lab in _tags:
		if lab.visible:
			out.append(Rect2(lab.position, lab.size))
	return out


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	var keep: Array = []
	for f in _flies:
		f["age"] = float(f["age"]) + delta
		var k := clampf(float(f["age"]) / 0.48, 0.0, 1.0)
		var chip: Control = _chips[f["kind"]]
		var to := chip.global_position + chip.size * 0.5
		var e := k * k * (3.0 - 2.0 * k)
		var lab: Label = f["node"]
		var from: Vector2 = f["from"]
		lab.position = from.lerp(to, e) + Vector2(0, -80.0 * sin(PI * k))
		lab.scale = Vector2.ONE * lerpf(1.2, 0.7, k)
		if k >= 1.0:
			lab.queue_free()
			chip.scale = Vector2.ONE * 1.15
			chip.create_tween().tween_property(chip, "scale", Vector2.ONE, 0.18)
		else:
			keep.append(f)
	_flies = keep


func _over_button(p: Vector2) -> bool:
	for c in [_action, _build_btn, _menu]:
		if c.visible and c.get_global_rect().has_point(p):
			return true
	return false


func _input(event: InputEvent) -> void:
	var rect := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var in_joy: bool = event.position.x < rect.x * 0.42 and event.position.y > rect.y * 0.42 and not _over_button(event.position)
		if event.pressed and in_joy and _joy_id < 0:
			_joy_id = event.index
			_joy_origin = event.position
			_stick = Vector2.ZERO
		elif not event.pressed and event.index == _joy_id:
			_joy_id = -1
			_stick = Vector2.ZERO
		elif event.pressed and not in_joy and not _over_button(event.position) and world:
			world.on_tap(event.position)
	elif event is InputEventScreenDrag and event.index == _joy_id:
		_stick = ((event.position - _joy_origin) / 74.0).limit_length(1.0)
