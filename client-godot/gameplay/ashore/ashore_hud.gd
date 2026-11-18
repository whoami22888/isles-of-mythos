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
var _build_btn: Button
var _build_panel: PanelContainer
var _build_box: VBoxContainer
var _build_sig := ""
var _build_campfire: Button
var _build_lean_to: Button
var _build_storage: Button
var _place_btn: Button
var _cancel_btn: Button
var _sub_panel: Button
var _tool_glyph: Control
var _sub_speaker: Label
var _sub_text: Label
var _menu_btn: Button
var _journal_panel: PanelContainer
var _journal_box: VBoxContainer
var _journal_sig := ""
const ALWAYS_COUNTS := ["wood", "stone", "fibre", "planks", "rope"]


func stick() -> Vector2:
	return _stick


func note_fly(from: Vector2, kind: String, amount: int) -> void:
	_flies.append({"from": from, "kind": kind, "amount": amount, "age": 0.0, "life": 0.85})


## "+2 Wood" toast near the top of the screen and a pulse on the bag counts.
var _toasts: Array = []
var _bag_pulse := 0.0


func note_toast(text: String, kind: String) -> void:
	_toasts.append({"text": text, "kind": kind, "age": 0.0})
	if _toasts.size() > 3:
		_toasts.pop_front()
	_bag_pulse = 0.35


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
		_apply_build()
		_apply_story()
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
	_build_story_widgets()


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
	_line = _label(25)
	_line.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_line.offset_top = 14
	_line.offset_bottom = 52
	_line.offset_left = -330
	_line.offset_right = 330
	_line.add_theme_stylebox_override("normal", _pill(Color(0.03, 0.08, 0.12, 0.55), Color(0.98, 0.82, 0.45, 0.0)))
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_line)
	_hint = _label(20)
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_top = 54
	_hint.offset_bottom = 80
	_hint.offset_left = -460
	_hint.offset_right = 460
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(0.98, 0.82, 0.45))
	add_child(_hint)
	_warm = ColorRect.new()
	_warm.color = Color(0.05, 0.1, 0.16, 0.7)
	_warm.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_warm.offset_left = 18
	_warm.offset_right = 198
	_warm.offset_top = 64
	_warm.offset_bottom = 76
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
	_hunger.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hunger.offset_left = 18
	_hunger.offset_right = 198
	_hunger.offset_top = 80
	_hunger.offset_bottom = 90
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
	_counts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_counts.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_counts.offset_top = 96
	_counts.offset_bottom = 128
	_counts.offset_left = 16
	_counts.offset_right = 760
	_counts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_counts.add_theme_constant_override("separation", 6)
	add_child(_counts)
	for kind in ["wood", "stone", "fibre", "planks", "rope", "cloth", "food", "flint", "meat", "fish", "cooked"]:
		var lab := _label(20)
		lab.text = "0"
		lab.custom_minimum_size = Vector2(48, 30)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lab.add_theme_stylebox_override("normal", _pill(Color(0.03, 0.08, 0.12, 0.6), _icon_color(kind)))
		lab.visible = false
		_counts.add_child(lab)
		_count_labels[kind] = lab
	_health = _label(26)
	_health.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_health.offset_top = 84
	_health.offset_bottom = 114
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
	_tool_glyph = Control.new()
	_tool_glyph.name = "ToolGlyph"
	_tool_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tool_glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tool_glyph.draw.connect(func() -> void:
		var tool := str(_state.get("tool_icon", ""))
		if tool != "":
			_draw_tool(_tool_glyph, Rect2(Vector2.ZERO, _tool_glyph.size), tool))
	_action.add_child(_tool_glyph)
	_action.button_down.connect(func() -> void:
		if world and world.has_method("on_action_hold"):
			world.on_action_hold(true))
	_action.button_up.connect(func() -> void:
		if world and world.has_method("on_action_hold"):
			world.on_action_hold(false))
	add_child(_action)
	_attack = _button("Strike", 24)
	_attack.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_attack.offset_left = -210
	_attack.offset_right = -28
	_attack.offset_top = -350
	_attack.offset_bottom = -264
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
	_research_toggle.visible = false
	add_child(_research_toggle)
	_build_btn = _button("Build", 24)
	_build_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_build_btn.offset_left = -210
	_build_btn.offset_right = -28
	_build_btn.offset_top = -250
	_build_btn.offset_bottom = -164
	_build_btn.pressed.connect(_emit_build_toggle)
	add_child(_build_btn)
	_build_panel = _panel()
	_build_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_build_panel.offset_left = -650
	_build_panel.offset_right = -226
	_build_panel.offset_top = -420
	_build_panel.offset_bottom = -150
	_build_panel.visible = false
	add_child(_build_panel)
	_build_box = VBoxContainer.new()
	_build_box.add_theme_constant_override("separation", 8)
	_build_panel.add_child(_build_box)
	_build_campfire = _button("Campfire", 22)
	_build_lean_to = _button("Lean-to", 22)
	_build_storage = _button("Storage", 22)
	for pair in [[_build_campfire, "campfire"], [_build_lean_to, "lean_to"], [_build_storage, "storage"]]:
		var b: Button = pair[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(400, 72)
		b.pressed.connect(_emit_build_pick.bind(str(pair[1])))
		_build_box.add_child(b)
	_place_btn = _button("Place", 30)
	_cancel_btn = _button("Cancel", 24)
	for b in [_place_btn, _cancel_btn]:
		b.visible = false
		b.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		add_child(b)
	_place_btn.offset_left = -230
	_place_btn.offset_right = -20
	_place_btn.offset_top = -150
	_place_btn.offset_bottom = -50
	_cancel_btn.offset_left = 20
	_cancel_btn.offset_right = 190
	_cancel_btn.offset_top = -150
	_cancel_btn.offset_bottom = -50
	_place_btn.pressed.connect(_emit_place)
	_cancel_btn.pressed.connect(_emit_cancel)
	_pet_chip = _button("Pet", 20)
	_pet_chip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_pet_chip.offset_left = -400
	_pet_chip.offset_right = -226
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
	_name_edit.placeholder_text = "Tide-Puck"
	_name_edit.text = "Tide-Puck"
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


func _build_story_widgets() -> void:
	# Subtitle strip: speaker in gold, one or two lines, tap to skip.
	_sub_panel = Button.new()
	_sub_panel.name = "Subtitle"
	_sub_panel.flat = false
	_sub_panel.focus_mode = Control.FOCUS_NONE
	_sub_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub_panel.offset_left = -560
	_sub_panel.offset_right = 560
	_sub_panel.offset_top = -300
	_sub_panel.offset_bottom = -180
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.02, 0.04, 0.06, 0.62)
	flat.set_corner_radius_all(10)
	for st in ["normal", "hover", "pressed", "focus"]:
		_sub_panel.add_theme_stylebox_override(st, flat)
	_sub_panel.pressed.connect(func() -> void:
		if world and world.has_method("on_sub_skip"):
			world.on_sub_skip())
	_sub_panel.visible = false
	add_child(_sub_panel)
	_sub_speaker = _label(26)
	_sub_speaker.add_theme_color_override("font_color", Color(0.98, 0.8, 0.42))
	_sub_speaker.position = Vector2(24, 8)
	_sub_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_panel.add_child(_sub_speaker)
	_sub_text = _label(32)
	_sub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_text.max_lines_visible = 2
	_sub_text.position = Vector2(24, 40)
	_sub_text.size = Vector2(1000, 76)
	_sub_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_panel.add_child(_sub_text)
	var hint := _label(18)
	hint.text = "tap to skip"
	hint.modulate = Color(1, 1, 1, 0.45)
	hint.position = Vector2(990, 10)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_panel.add_child(hint)
	# One menu button (top right): pauses and shows the story journal.
	_menu_btn = _button("Journal", 24)
	_menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_menu_btn.offset_left = -170
	_menu_btn.offset_right = -20
	_menu_btn.offset_top = 16
	_menu_btn.offset_bottom = 68
	_menu_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_btn.pressed.connect(_toggle_journal)
	add_child(_menu_btn)
	_journal_panel = _panel()
	_journal_panel.set_anchors_preset(Control.PRESET_CENTER)
	_journal_panel.offset_left = -520
	_journal_panel.offset_right = 520
	_journal_panel.offset_top = -380
	_journal_panel.offset_bottom = 380
	_journal_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_journal_panel.visible = false
	add_child(_journal_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_journal_panel.add_child(scroll)
	_journal_box = VBoxContainer.new()
	_journal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_box.add_theme_constant_override("separation", 14)
	scroll.add_child(_journal_box)


func _toggle_journal() -> void:
	_journal_panel.visible = not _journal_panel.visible
	_journal_sig = ""
	_apply_story()
	get_tree().paused = _journal_panel.visible


func _apply_story() -> void:
	if _sub_panel == null:
		return
	var text := str(_state.get("sub_text", ""))
	_sub_panel.visible = text != "" and not _journal_panel.visible
	_sub_speaker.text = str(_state.get("sub_speaker", ""))
	_sub_text.text = text
	_menu_btn.visible = not bool(_state.get("skip", false))
	if not _journal_panel.visible:
		return
	var entries: Array = _state.get("journal", [])
	var sig := str(entries.size())
	if sig == _journal_sig:
		return
	_journal_sig = sig
	for child in _journal_box.get_children():
		child.queue_free()
	var head := _label(40)
	head.text = "Journal  -  paused"
	_journal_box.add_child(head)
	if entries.is_empty():
		var none := _label(26)
		none.text = "Nothing written yet."
		_journal_box.add_child(none)
	for entry in entries:
		var t := _label(30)
		t.text = str(entry.get("title", ""))
		t.add_theme_color_override("font_color", Color(0.98, 0.8, 0.42))
		_journal_box.add_child(t)
		var body := _label(24)
		body.text = str(entry.get("text", ""))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(960, 0)
		_journal_box.add_child(body)
	var resume := _button("Resume", 26)
	resume.process_mode = Node.PROCESS_MODE_ALWAYS
	resume.pressed.connect(_toggle_journal)
	_journal_box.add_child(resume)


func _apply_meters() -> void:
	var warmth := clampf(float(_state.get("warmth", 0.0)) / 100.0, 0.0, 1.0)
	var hunger := clampf(float(_state.get("hunger", 0.0)) / 100.0, 0.0, 1.0)
	var width := 174.0
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
		var n := int(counts.get(kind, 0))
		label.text = "%s %d" % [_short(kind), n]
		label.visible = n > 0 or kind in ALWAYS_COUNTS


func _apply_buttons() -> void:
	_action.text = ("     " if str(_state.get("tool_icon", "")) != "" else "") + str(_state.get("action", "Act"))
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
		_pet_chip.text = "%s  ♥%d" % [str(_state.get("pet_name", "Tide-Puck")), int(_state.get("pet_level", 1))]
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
		var bond := int(_state.get("pet_bond", 0))
		_mood.text = "Bond Lv %d  (%d/%d)\nFinds %d   Fetches %d\nMood %d   Hunger %d\nFeed: +12 bond" % [1 + bond / 20, bond % 20, 20, int(_state.get("pet_finds", 0)), int(_state.get("pet_fetches", 0)), int(_state.get("pet_mood", 0)), int(_state.get("pet_hunger", 0))]


func _apply_name() -> void:
	var open := bool(_state.get("name_open", false))
	if open and not _name_panel.visible:
		_name_edit.text = str(_state.get("name_default", "Tide-Puck"))
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
	var keep_t: Array = []
	for toast in _toasts:
		toast.age += delta
		if float(toast.age) < 1.6:
			keep_t.append(toast)
	_toasts = keep_t
	_bag_pulse = maxf(_bag_pulse - delta, 0.0)
	if _counts:
		_counts.pivot_offset = Vector2(0, _counts.size.y * 0.5)
		_counts.scale = Vector2.ONE * (1.0 + sin(clampf(1.0 - _bag_pulse / 0.35, 0.0, 1.0) * PI) * 0.12 * (1.0 if _bag_pulse > 0.0 else 0.0))
	if _draw:
		_draw.queue_redraw()
	if _tool_glyph:
		_tool_glyph.queue_redraw()


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
	var ty := 150.0
	for toast in _toasts:
		var k := float(toast.age)
		var alpha := clampf(1.6 - k, 0.0, 0.4) / 0.4
		var rise := minf(k, 0.25) / 0.25
		var tfont := _ui if _ui else ThemeDB.fallback_font
		var txt := str(toast.text)
		var tw := tfont.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		var at := Vector2(size.x * 0.5 - tw * 0.5 + 20, ty + 18.0 * (1.0 - rise))
		_draw.draw_rect(Rect2(at - Vector2(56, 34), Vector2(tw + 76, 46)), Color(0.03, 0.06, 0.08, 0.55 * alpha))
		_draw_icon(at + Vector2(-30, -11), str(toast.kind), 26)
		_draw.draw_string(tfont, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 0.95, 0.8, alpha))
		ty += 52.0
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
		"stone":
			col = Color(0.55, 0.55, 0.52)
		"fibre":
			col = Color(0.45, 0.62, 0.22)
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
		"stone":
			return "Stone"
		"fibre":
			return "Fibre"
		"fish":
			return "Fish"
		"cooked":
			return "Cooked"
	return kind


func _over_button(at: Vector2) -> bool:
	for child in get_children():
		if child is Control and (child as Control).is_visible_in_tree():
			var c := child as Control
			if (c is Button or c is PanelContainer) and c.get_global_rect().has_point(at):
				return true
	return false


func _pill(bg: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(14)
	box.border_width_left = 12
	box.border_color = edge
	box.content_margin_left = 18
	box.content_margin_right = 10
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


func _icon_color(kind: String) -> Color:
	match kind:
		"rope":
			return Color(0.78, 0.6, 0.32)
		"cloth":
			return Color(0.9, 0.3, 0.34)
		"wood":
			return Color(0.55, 0.33, 0.16)
		"food":
			return Color(0.95, 0.28, 0.2)
		"meat":
			return Color(0.78, 0.24, 0.26)
		"flint":
			return Color(0.55, 0.6, 0.66)
		"stone":
			return Color(0.66, 0.66, 0.62)
		"fibre":
			return Color(0.55, 0.78, 0.3)
		"fish":
			return Color(0.25, 0.72, 0.8)
		"cooked":
			return Color(0.92, 0.55, 0.18)
	return Color(0.86, 0.67, 0.32)


func _short(kind: String) -> String:
	match kind:
		"planks":
			return "Plank"
		"cooked":
			return "Meal"
	return _icon_word(kind)


func _count_anchor() -> Vector2:
	if _counts:
		return _counts.global_position + _counts.size * 0.5
	return Vector2(640, 210)


func _input(event: InputEvent) -> void:
	var rect := get_viewport().get_visible_rect().size
	var in_joy := false
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or event is InputEventMouseMotion:
		in_joy = event.position.x < rect.x * 0.42 and event.position.y > rect.y * 0.42 and not _over_button(event.position)
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


func _apply_build() -> void:
	var placing := bool(_state.get("placing", false))
	var hidden := bool(_state.get("fork", false)) or bool(_state.get("qte", false)) or bool(_state.get("name_open", false)) or bool(_state.get("skip", false))
	_build_btn.visible = not hidden and not placing
	_place_btn.visible = placing and not hidden
	_cancel_btn.visible = placing and not hidden
	_place_btn.modulate = Color(1, 1, 1, 1) if bool(_state.get("place_ok", false)) else Color(1, 0.55, 0.5, 0.8)
	_build_panel.visible = bool(_state.get("build_open", false)) and not placing and not hidden
	if bool(_state.get("build_hint", false)) and not _build_panel.visible:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
		_build_btn.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.85, 0.4), pulse)
	else:
		_build_btn.modulate = Color(1, 1, 1)
	var buttons := {"campfire": _build_campfire, "lean_to": _build_lean_to, "storage": _build_storage}
	for row in _state.get("build_rows", []):
		var b: Button = buttons.get(str(row.get("id", "")))
		if b == null:
			continue
		var text := "%s   %s" % [str(row.get("title", "")), str(row.get("cost", ""))]
		if bool(row.get("built", false)):
			text = "%s   built" % str(row.get("title", ""))
		b.text = text
		b.modulate = Color(1, 1, 1) if bool(row.get("ok", false)) else Color(0.7, 0.66, 0.6, 0.85)


func _emit_build_toggle() -> void:
	if world:
		world.on_build_toggle()


func _emit_build_pick(id: String) -> void:
	if world:
		world.on_build_pick(id)


func _emit_place() -> void:
	if world:
		world.on_build_place()


func _emit_cancel() -> void:
	if world:
		world.on_build_cancel()


## Context tool glyph on the Act button: axe (trees), pick (stone), open hand (debris).
func _draw_tool(canvas: Control, rect: Rect2, tool: String) -> void:
	var c := Vector2(rect.position.x + 40, rect.position.y + rect.size.y * 0.5)
	var wood := Color(0.62, 0.42, 0.22)
	var steel := Color(0.82, 0.84, 0.86)
	var edge := Color(0.05, 0.05, 0.05, 0.8)
	match tool:
		"axe":
			canvas.draw_line(c + Vector2(-14, 22), c + Vector2(10, -20), edge, 9.0)
			canvas.draw_line(c + Vector2(-14, 22), c + Vector2(10, -20), wood, 6.0)
			var head := PackedVector2Array([c + Vector2(4, -24), c + Vector2(24, -18), c + Vector2(22, 0), c + Vector2(8, -10)])
			canvas.draw_colored_polygon(head, steel)
			canvas.draw_polyline(head + PackedVector2Array([head[0]]), edge, 2.0)
		"pick":
			canvas.draw_line(c + Vector2(0, 24), c + Vector2(0, -16), edge, 9.0)
			canvas.draw_line(c + Vector2(0, 24), c + Vector2(0, -16), wood, 6.0)
			var arc := PackedVector2Array([c + Vector2(-24, -6), c + Vector2(-10, -20), c + Vector2(0, -22), c + Vector2(10, -20), c + Vector2(24, -6)])
			canvas.draw_polyline(arc, edge, 9.0)
			canvas.draw_polyline(arc, steel, 6.0)
		"hands":
			var skin := Color(0.92, 0.76, 0.6)
			canvas.draw_circle(c + Vector2(0, 6), 13, skin)
			for i in 4:
				var x := -10.5 + 7.0 * float(i)
				canvas.draw_line(c + Vector2(x, 2), c + Vector2(x, -16 + absf(x) * 0.3), skin, 6.0)
			canvas.draw_line(c + Vector2(-12, 10), c + Vector2(-22, 0), skin, 6.0)
