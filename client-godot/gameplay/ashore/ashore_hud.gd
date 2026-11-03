extends CanvasLayer
## Touch HUD for the washed-ashore island. One quest line, chunky counters,
## warmth above hunger. No debug fields and no session token.

var world: Node

var _font: Font
var _ui: Font
var _stick := Vector2.ZERO
var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _state: Dictionary = {}
var _flies: Array = []
var _burst := ""
var _burst_age := 10.0
var _research_sig := ""
var _research_buttons: Dictionary = {}

var _line: Label
var _hint: Label
var _warm: ColorRect
var _warm_fill: ColorRect
var _hunger: ColorRect
var _hunger_fill: ColorRect
var _counts: HBoxContainer
var _count_labels: Dictionary = {}
var _action: Button
var _attack: Button
var _skip: Button
var _research_toggle: Button
var _research_panel: PanelContainer
var _research_box: VBoxContainer
var _name_panel: PanelContainer
var _name_edit: LineEdit
var _end_panel: PanelContainer
var _end_box: VBoxContainer
var _end_sig := ""
var _pet_sig := ""
var _mood: Label
var _fork_tame: Button
var _fork_kill: Button
var _feed: Button
var _qte: Button
var _pet_chip: Button
var _pet_panel: PanelContainer
var _pet_box: VBoxContainer
var _spyglass: ColorRect
var _bars: Array[ColorRect] = []
var _build: ProgressBar
var _health: Label
var _draw: Control


func stick() -> Vector2:
	return _stick


func note_fly(from: Vector2, kind: String, amount: int) -> void:
	_flies.append({"from": from, "kind": kind, "amount": amount, "age": 0.0, "life": 0.85})


func note_burst(text: String) -> void:
	_burst = text
	_burst_age = 0.0


func push_state(state: Dictionary) -> void:
	_state = state
	if _line:
		_line.text = str(state.get("line", ""))
		_hint.text = str(state.get("hint", ""))
		_hint.visible = _hint.text != ""
		_apply_meters()
		_apply_counts()
		_apply_buttons()
		_apply_research()
		_apply_pet()
		_apply_name()
		_apply_end()
		_spyglass.visible = bool(state.get("spyglass", false))
		for bar in _bars:
			bar.visible = bool(state.get("letterbox", false))
		if _draw:
			_draw.queue_redraw()


func _ready() -> void:
	layer = 20
	_font = load("res://assets/fonts/PirataOne-Regular.ttf")
	_ui = load("res://assets/fonts/IMFeENrm28P.ttf")
	_build_widgets()


func _build_widgets() -> void:
	_draw = Control.new()
	_draw.name = "Draw"
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	add_child(_draw)
	_spyglass = ColorRect.new()
	_spyglass.set_anchors_preset(Control.PRESET_FULL_RECT)
	_spyglass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spyglass.color = Color(0, 0, 0, 0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ashore_spyglass.gdshader")
	_spyglass.material = mat
	_spyglass.visible = false
	add_child(_spyglass)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.02, 0.03, 0.04, 0.72)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.visible = false
		if top:
			bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
			bar.offset_bottom = 54
		else:
			bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			bar.offset_top = -54
		add_child(bar)
		_bars.append(bar)
	_line = _label(34)
	_line.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_line.offset_top = 62
	_line.offset_bottom = 108
	_line.offset_left = -420
	_line.offset_right = 420
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_line)
	_hint = _label(22)
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_top = 108
	_hint.offset_bottom = 140
	_hint.offset_left = -460
	_hint.offset_right = 460
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(0.98, 0.82, 0.45))
	add_child(_hint)
	_warm = ColorRect.new()
	_warm.color = Color(0.05, 0.1, 0.16, 0.7)
	_warm.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_warm.offset_left = 24
	_warm.offset_right = -24
	_warm.offset_top = 146
	_warm.offset_bottom = 172
	_warm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_warm)
	_warm_fill = ColorRect.new()
	_warm_fill.color = Color(0.35, 0.62, 0.95)
	_warm_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warm_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_warm_fill.offset_top = 3
	_warm_fill.offset_bottom = -3
	_warm_fill.offset_left = 3
	_warm.add_child(_warm_fill)
	_hunger = ColorRect.new()
	_hunger.color = Color(0.08, 0.12, 0.08, 0.65)
	_hunger.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hunger.offset_left = 24
	_hunger.offset_right = -24
	_hunger.offset_top = 176
	_hunger.offset_bottom = 192
	_hunger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hunger)
	_hunger_fill = ColorRect.new()
	_hunger_fill.color = Color(0.55, 0.75, 0.22)
	_hunger_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hunger_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_hunger_fill.offset_top = 2
	_hunger_fill.offset_bottom = -2
	_hunger_fill.offset_left = 2
	_hunger.add_child(_hunger_fill)
	_counts = HBoxContainer.new()
	_counts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_counts.offset_top = 198
	_counts.offset_bottom = 242
	_counts.offset_left = -520
	_counts.offset_right = 520
	_counts.alignment = BoxContainer.ALIGNMENT_CENTER
	_counts.add_theme_constant_override("separation", 14)
	add_child(_counts)
	for kind in ["planks", "rope", "cloth", "wood", "food", "meat", "flint", "fish", "cooked"]:
		var lab := _label(24)
		lab.text = "0"
		_counts.add_child(lab)
		_count_labels[kind] = lab
	_health = _label(26)
	_health.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_health.offset_top = 246
	_health.offset_bottom = 280
	_health.offset_left = -200
	_health.offset_right = 200
	_health.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health.visible = false
	add_child(_health)
	_build = ProgressBar.new()
	_build.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build.offset_left = -220
	_build.offset_right = 220
	_build.offset_top = -250
	_build.offset_bottom = -218
	_build.max_value = 1.0
	_build.show_percentage = false
	_build.visible = false
	_build.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_build)
	_action = _button("Act", 28)
	_action.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_action.offset_left = -210
	_action.offset_right = -28
	_action.offset_top = -150
	_action.offset_bottom = -36
	_action.pressed.connect(_emit_action)
	add_child(_action)
	_attack = _button("Strike", 24)
	_attack.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_attack.offset_left = -210
	_attack.offset_right = -28
	_attack.offset_top = -250
	_attack.offset_bottom = -164
	_attack.visible = false
	_attack.pressed.connect(_emit_attack)
	add_child(_attack)
	_skip = _button("Skip", 22)
	_skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip.offset_left = -160
	_skip.offset_right = -20
	_skip.offset_top = 16
	_skip.offset_bottom = 72
	_skip.visible = false
	_skip.pressed.connect(_emit_skip)
	add_child(_skip)
	_research_toggle = _button("Research", 20)
	_research_toggle.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_research_toggle.offset_left = 16
	_research_toggle.offset_right = 180
	_research_toggle.offset_top = 16
	_research_toggle.offset_bottom = 68
	_research_toggle.pressed.connect(_emit_research_toggle)
	add_child(_research_toggle)
	_pet_chip = _button("Pet", 20)
	_pet_chip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_pet_chip.offset_left = 200
	_pet_chip.offset_right = 420
	_pet_chip.offset_top = -120
	_pet_chip.offset_bottom = -36
	_pet_chip.visible = false
	_pet_chip.pressed.connect(_emit_pet_toggle)
	add_child(_pet_chip)
	_fork_tame = _button("TAME", 40)
	_fork_kill = _button("KILL", 40)
	for button in [_fork_tame, _fork_kill]:
		button.visible = false
		button.set_anchors_preset(Control.PRESET_CENTER)
		add_child(button)
	_fork_tame.offset_left = -340
	_fork_tame.offset_right = -20
	_fork_tame.offset_top = -40
	_fork_tame.offset_bottom = 120
	_fork_kill.offset_left = 20
	_fork_kill.offset_right = 340
	_fork_kill.offset_top = -40
	_fork_kill.offset_bottom = 120
	_fork_tame.pressed.connect(_emit_tame)
	_fork_kill.pressed.connect(_emit_kill)
	_qte = _button("FEED", 36)
	_qte.visible = false
	_qte.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_qte.offset_left = -160
	_qte.offset_right = 160
	_qte.offset_top = -220
	_qte.offset_bottom = -90
	_qte.pressed.connect(_emit_feed_qte)
	add_child(_qte)
	_research_panel = _panel()
	_research_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_research_panel.offset_left = 16
	_research_panel.offset_top = 78
	_research_panel.offset_right = 430
	_research_panel.offset_bottom = 620
	_research_panel.visible = false
	add_child(_research_panel)
	_research_box = VBoxContainer.new()
	_research_box.add_theme_constant_override("separation", 6)
	_research_panel.add_child(_research_box)
	_pet_panel = _panel()
	_pet_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_pet_panel.offset_left = 16
	_pet_panel.offset_top = -420
	_pet_panel.offset_right = 420
	_pet_panel.offset_bottom = -130
	_pet_panel.visible = false
	add_child(_pet_panel)
	_pet_box = VBoxContainer.new()
	_pet_box.add_theme_constant_override("separation", 4)
	_pet_panel.add_child(_pet_box)
	_feed = _button("Feed", 22)
	_feed.pressed.connect(_emit_feed_pet)
	_name_panel = _panel()
	_name_panel.set_anchors_preset(Control.PRESET_CENTER)
	_name_panel.offset_left = -260
	_name_panel.offset_right = 260
	_name_panel.offset_top = -120
	_name_panel.offset_bottom = 120
	_name_panel.visible = false
	add_child(_name_panel)
	var name_box := VBoxContainer.new()
	name_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_box.offset_left = 16
	name_box.offset_top = 16
	name_box.offset_right = -16
	name_box.offset_bottom = -16
	_name_panel.add_child(name_box)
	var name_label := _label(28)
	name_label.text = "Name"
	name_box.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Pip"
	_name_edit.text = "Pip"
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(0, 56)
	name_box.add_child(_name_edit)
	var name_ok := _button("OK", 24)
	name_ok.pressed.connect(_emit_name)
	name_box.add_child(name_ok)
	_end_panel = _panel()
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.offset_left = -340
	_end_panel.offset_right = 340
	_end_panel.offset_top = -260
	_end_panel.offset_bottom = 260
	_end_panel.visible = false
	add_child(_end_panel)
	_end_box = VBoxContainer.new()
	_end_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_box.offset_left = 18
	_end_box.offset_top = 18
	_end_box.offset_right = -18
	_end_box.offset_bottom = -18
	_end_panel.add_child(_end_box)


func _apply_meters() -> void:
	var warmth := clampf(float(_state.get("warmth", 0.0)) / 100.0, 0.0, 1.0)
	var hunger := clampf(float(_state.get("hunger", 0.0)) / 100.0, 0.0, 1.0)
	var width := maxf(get_viewport().get_visible_rect().size.x - 54.0, 80.0)
	_warm_fill.offset_right = 3.0 + width * warmth
	_warm_fill.color = Color(0.32, 0.58, 0.95).lerp(Color(0.96, 0.42, 0.12), warmth)
	_hunger_fill.offset_right = 2.0 + width * hunger
	var hp := int(_state.get("health", 5))
	_health.visible = bool(_state.get("show_health", false))
	_health.text = "♥".repeat(maxi(hp, 0))
	_build.visible = bool(_state.get("build_on", false))
	_build.value = float(_state.get("build_ratio", 0.0))


func _apply_counts() -> void:
	var counts: Dictionary = _state.get("counts", {})
	for kind in _count_labels.keys():
		var label: Label = _count_labels[kind]
		label.text = "%s %d" % [_icon_word(kind), int(counts.get(kind, 0))]


func _apply_buttons() -> void:
	_action.text = str(_state.get("action", "Act"))
	_action.visible = not bool(_state.get("fork", false)) and not bool(_state.get("qte", false)) and not bool(_state.get("name_open", false))
	_attack.visible = bool(_state.get("attack", false))
	_skip.visible = bool(_state.get("skip", false))
	_fork_tame.visible = bool(_state.get("fork", false))
	_fork_kill.visible = bool(_state.get("fork", false))
	_qte.visible = bool(_state.get("qte", false))
	var alert := bool(_state.get("alert", false))
	if alert:
		_pet_chip.add_theme_color_override("font_color", Color(0.98, 0.35, 0.2))
	else:
		_pet_chip.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78))


func _apply_research() -> void:
	var open := bool(_state.get("research_open", false))
	_research_panel.visible = open
	var rows: Array = _state.get("research", [])
	var sig := ""
	for row in rows:
		sig += str(row.get("id", "")) + str(row.get("state", ""))
	if sig != _research_sig:
		_research_sig = sig
		for child in _research_box.get_children():
			child.queue_free()
		_research_buttons.clear()
		for row in rows:
			var button := _button(_research_text(row), 20)
			button.disabled = str(row.get("state", "")) == "locked"
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var id := str(row.get("id", ""))
			button.pressed.connect(_emit_research.bind(id))
			_research_box.add_child(button)
			_research_buttons[id] = button
	else:
		for row in rows:
			var id := str(row.get("id", ""))
			if _research_buttons.has(id) and is_instance_valid(_research_buttons[id]):
				(_research_buttons[id] as Button).text = _research_text(row)


func _research_text(row: Dictionary) -> String:
	var state := str(row.get("state", ""))
	var title := str(row.get("title", ""))
	if state == "locked":
		return "Locked  " + title
	if state == "run":
		return "%s  %d%%" % [title, int(float(row.get("ratio", 0.0)) * 100.0)]
	if state == "done":
		return title + "  done"
	return title


func _apply_pet() -> void:
	var freed := bool(_state.get("pet_freed", false))
	_pet_chip.visible = freed
	if freed:
		_pet_chip.text = "%s  %d" % [str(_state.get("pet_name", "Pip")), int(_state.get("pet_level", 1))]
	var open := bool(_state.get("pet_open", false))
	_pet_panel.visible = open and freed
	if _mood == null:
		_mood = _label(20)
		_pet_box.add_child(_mood)
		_pet_box.add_child(_feed)
		for card in _state.get("pet_cards", []):
			var lab := _label(20)
			var on := bool(card.get("on", false))
			lab.text = str(card.get("t", "")) if on else "Locked  " + str(card.get("t", ""))
			lab.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78) if on else Color(0.55, 0.52, 0.48))
			_pet_box.add_child(lab)
			_pet_sig += str(card.get("t", ""))
	if _mood:
		_mood.text = "Mood %d   Hunger %d" % [int(_state.get("pet_mood", 0)), int(_state.get("pet_hunger", 0))]


func _apply_name() -> void:
	var open := bool(_state.get("name_open", false))
	if open and not _name_panel.visible:
		_name_edit.text = str(_state.get("name_default", "Pip"))
		_name_edit.grab_focus()
	_name_panel.visible = open


func _apply_end() -> void:
	var open := bool(_state.get("end_open", false))
	_end_panel.visible = open
	if not open:
		return
	var sig := ""
	for line in _state.get("end_lines", []):
		sig += str(line) + "|"
	if sig == _end_sig:
		return
	_end_sig = sig
	for child in _end_box.get_children():
		child.queue_free()
	for line in _state.get("end_lines", []):
		var lab := _label(26)
		lab.text = str(line)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_end_box.add_child(lab)
	var onward := _button("Onward", 24)
	onward.pressed.connect(_emit_end)
	_end_box.add_child(onward)


func _process(delta: float) -> void:
	_burst_age += delta
	var keep: Array = []
	for fly in _flies:
		fly.age += delta
		if float(fly.age) < float(fly.life):
			keep.append(fly)
	_flies = keep
	if _draw:
		_draw.queue_redraw()


func _on_draw() -> void:
	var size := get_viewport().get_visible_rect().size
	var origin := Vector2(150, size.y - 150)
	_draw.draw_circle(origin, 78, Color(0.05, 0.12, 0.14, 0.45))
	_draw.draw_arc(origin, 78, 0, TAU, 48, Color(0.96, 0.9, 0.78, 0.8), 4.0)
	_draw.draw_circle(origin + _stick * 52.0, 34, Color(0.85, 0.62, 0.28, 0.95))
	if _burst != "" and _burst_age < 0.7:
		var punch := 1.0 + sin(clampf(_burst_age / 0.7, 0.0, 1.0) * PI) * 0.35
		var font := _font if _font else ThemeDB.fallback_font
		var text_size := font.get_string_size(_burst, HORIZONTAL_ALIGNMENT_CENTER, -1, int(64 * punch))
		var pos := Vector2(size.x * 0.5 - text_size.x * 0.5, 340)
		_draw.draw_string(font, pos, _burst, HORIZONTAL_ALIGNMENT_LEFT, -1, int(64 * punch), Color(1, 0.95, 0.75))
	var slot := _count_anchor()
	for fly in _flies:
		var t := clampf(float(fly.age) / float(fly.life), 0.0, 1.0)
		var from: Vector2 = fly.from
		var mid := (from + slot) * 0.5 + Vector2(0, -120)
		var p := from.lerp(mid, t).lerp(mid.lerp(slot, t), t)
		_draw_icon(p, str(fly.kind), 28)
		var plus := "+%d" % int(fly.amount)
		var font2 := _ui if _ui else ThemeDB.fallback_font
		_draw.draw_string(font2, p + Vector2(16, -8), plus, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 0.95, 0.8))
	if bool(_state.get("pointer", false)):
		var aim: Vector2 = _state.get("pointer_at", Vector2.ZERO)
		var center := size * 0.5
		var dir := aim - center
		if dir.length() < 8.0:
			dir = Vector2.UP
		dir = dir.normalized()
		var edge := center + dir * minf(size.x, size.y) * 0.36
		_draw.draw_colored_polygon(PackedVector2Array([
			edge + dir * 28,
			edge + dir.rotated(2.4) * 18,
			edge + dir.rotated(-2.4) * 18,
		]), Color(0.98, 0.86, 0.35, 0.95))
	if bool(_state.get("qte", false)):
		var marker := float(_state.get("qte_marker", 0.0))
		var za := float(_state.get("qte_a", 0.68))
		var zb := float(_state.get("qte_b", 0.84))
		var bar := Rect2(size.x * 0.5 - 260, size.y - 300, 520, 28)
		_draw.draw_rect(bar, Color(0.05, 0.08, 0.1, 0.8))
		_draw.draw_rect(Rect2(bar.position.x + bar.size.x * za, bar.position.y, bar.size.x * (zb - za), bar.size.y), Color(0.95, 0.78, 0.28))
		_draw.draw_rect(Rect2(bar.position.x + bar.size.x * marker - 4, bar.position.y - 8, 8, bar.size.y + 16), Color(0.98, 0.96, 0.9))
		var ratio := float(_state.get("qte_ratio", 1.0))
		_draw.draw_rect(Rect2(bar.position.x, bar.position.y + 36, bar.size.x * ratio, 10), Color(0.45, 0.85, 0.7))


func _draw_icon(at: Vector2, kind: String, s: float) -> void:
	var col := Color(0.86, 0.67, 0.32)
	match kind:
		"rope":
			col = Color(0.72, 0.55, 0.3)
		"cloth":
			col = Color(0.85, 0.28, 0.32)
		"wood":
			col = Color(0.45, 0.28, 0.14)
		"food":
			col = Color(0.9, 0.24, 0.18)
		"meat":
			col = Color(0.7, 0.22, 0.24)
		"flint":
			col = Color(0.35, 0.38, 0.42)
		"fish":
			col = Color(0.25, 0.65, 0.72)
		"cooked":
			col = Color(0.85, 0.48, 0.16)
	_draw.draw_rect(Rect2(at - Vector2(s * 0.5, s * 0.35), Vector2(s, s * 0.7)), col)


func _icon_word(kind: String) -> String:
	match kind:
		"planks":
			return "Planks"
		"rope":
			return "Rope"
		"cloth":
			return "Cloth"
		"wood":
			return "Wood"
		"food":
			return "Food"
		"meat":
			return "Meat"
		"flint":
			return "Flint"
		"fish":
			return "Fish"
		"cooked":
			return "Cooked"
	return kind


func _count_anchor() -> Vector2:
	if _counts:
		return _counts.global_position + _counts.size * 0.5
	return Vector2(640, 210)


func _input(event: InputEvent) -> void:
	var rect := get_viewport().get_visible_rect().size
	var in_joy := false
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or event is InputEventMouseMotion:
		in_joy = event.position.x < rect.x * 0.42 and event.position.y > rect.y * 0.42
	if event is InputEventScreenTouch:
		if event.pressed and in_joy and _joy_id < 0:
			_joy_id = event.index
			_joy_origin = event.position
			_stick = Vector2.ZERO
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _joy_id:
			_joy_id = -1
			_stick = Vector2.ZERO
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _joy_id:
		_stick = (event.position - _joy_origin) / 74.0
		if _stick.length() > 1.0:
			_stick = _stick.normalized()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and in_joy:
			_joy_id = 0
			_joy_origin = event.position
			get_viewport().set_input_as_handled()
		elif not event.pressed and _joy_id == 0:
			_joy_id = -1
			_stick = Vector2.ZERO
	elif event is InputEventMouseMotion and _joy_id == 0 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_stick = (event.position - _joy_origin) / 74.0
		if _stick.length() > 1.0:
			_stick = _stick.normalized()


func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.97, 0.91, 0.78))
	label.add_theme_color_override("font_shadow_color", Color(0.05, 0.04, 0.03, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	if _font:
		label.add_theme_font_override("font", _font)
	return label


func _button(text: String, size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120, 64)
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", Color(0.98, 0.93, 0.82))
	if _font:
		button.add_theme_font_override("font", _font)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.36, 0.4)
	normal.set_corner_radius_all(18)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.12, 0.48, 0.5)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.1, 0.12, 0.88)
	box.set_corner_radius_all(16)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", box)
	return panel


func _emit_action() -> void:
	if world:
		world.on_action()


func _emit_attack() -> void:
	if world:
		world.on_attack()


func _emit_skip() -> void:
	if world:
		world.skip_cinematic()


func _emit_tame() -> void:
	if world:
		world.on_tame()


func _emit_kill() -> void:
	if world:
		world.on_kill()


func _emit_feed_qte() -> void:
	if world:
		world.on_qte_tap()


func _emit_feed_pet() -> void:
	if world:
		world.on_feed_pet()


func _emit_name() -> void:
	if world:
		world.on_name(_name_edit.text)


func _emit_end() -> void:
	if world:
		world.on_end_closed()


func _emit_research_toggle() -> void:
	if world:
		world.on_research_toggle()


func _emit_pet_toggle() -> void:
	if world:
		world.on_pet_toggle()


func _emit_research(id: String) -> void:
	if world:
		world.on_research(id)
