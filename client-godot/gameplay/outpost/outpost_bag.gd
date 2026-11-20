extends Node
## Bag panel: every item the castaway holds (resources, tools, loot, rare
## finds), each with a material-coloured chip, name, count and a one-line
## description from data/scenarios/items.json. The HUD tray stays at 3 items.

const ITEMS_PATH := "res://gameplay/outpost/data/scenarios/items.json"
## Muted, material-true chip colours by item id (fallback by keyword).
const COLORS := {
	"wood": Color(0.52, 0.36, 0.2), "hardwood": Color(0.36, 0.22, 0.12), "bamboo": Color(0.6, 0.6, 0.32),
	"stone": Color(0.55, 0.54, 0.5), "flint": Color(0.22, 0.23, 0.26), "iron": Color(0.42, 0.44, 0.47),
	"gold": Color(0.78, 0.62, 0.22), "food": Color(0.66, 0.42, 0.22), "meat": Color(0.6, 0.24, 0.2),
	"crab_meat": Color(0.75, 0.38, 0.28), "fish": Color(0.5, 0.6, 0.66), "berries": Color(0.5, 0.1, 0.16),
	"coconut": Color(0.42, 0.3, 0.18), "fibre": Color(0.66, 0.56, 0.36), "rope": Color(0.6, 0.5, 0.32),
	"hide": Color(0.46, 0.34, 0.24), "feather": Color(0.85, 0.85, 0.82), "shell": Color(0.88, 0.8, 0.7),
	"pearl": Color(0.92, 0.9, 0.86), "map_fragment": Color(0.78, 0.7, 0.5), "relic_shard": Color(0.3, 0.5, 0.55),
	"relic": Color(0.3, 0.5, 0.55), "rum": Color(0.5, 0.26, 0.12), "water": Color(0.35, 0.55, 0.7),
	"fresh_water": Color(0.35, 0.55, 0.7), "sailcloth": Color(0.85, 0.82, 0.74), "scrap": Color(0.45, 0.38, 0.3),
	"powder": Color(0.18, 0.17, 0.17), "tar": Color(0.1, 0.09, 0.08), "herbs": Color(0.32, 0.46, 0.24),
}

var host: Node
var items_meta: Dictionary = {}
var _btn: Button
var _panel: PanelContainer
var _grid: GridContainer
var _title: Label
var _key := ""


func setup(h: Node) -> void:
	host = h
	var f := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			items_meta = parsed


static func chip_color(id: String) -> Color:
	if COLORS.has(id):
		return COLORS[id]
	for k in COLORS.keys():
		if str(k) in id:
			return COLORS[k]
	var h := float(abs(hash(id)) % 360) / 360.0
	return Color.from_hsv(h, 0.25, 0.55)


func item_name(id: String) -> String:
	return str(items_meta.get(id, {}).get("name", id.replace("_", " ").capitalize()))


## [{id, n}] sorted: resources first, then by name. Zero counts hidden.
func rows() -> Array:
	var inv: Dictionary = host.state.inv
	var res: Array = host.state.data.get("resources", [])
	var out: Array = []
	for k in inv.keys():
		if int(inv[k]) > 0:
			out.append({"id": str(k), "n": int(inv[k])})
	out.sort_custom(func(a, b):
		var ra: int = res.find(a["id"])
		var rb: int = res.find(b["id"])
		if (ra >= 0) != (rb >= 0):
			return ra >= 0
		if ra >= 0:
			return ra < rb
		return item_name(a["id"]) < item_name(b["id"]))
	return out


func build_ui(hud: CanvasLayer, font: Font) -> void:
	_btn = Button.new()
	_btn.text = "Bag"
	_btn.add_theme_font_size_override("font_size", 28)
	_btn.anchor_left = 1.0
	_btn.anchor_right = 1.0
	_btn.offset_left = -290
	_btn.offset_right = -164
	_btn.offset_top = 150
	_btn.offset_bottom = 210
	_btn.pressed.connect(toggle)
	hud.add_child(_btn)
	_panel = PanelContainer.new()
	_panel.name = "BagPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.06, 0.92)
	sb.border_color = Color(0.55, 0.45, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -520
	_panel.offset_right = 520
	_panel.offset_top = 120
	_panel.visible = false
	hud.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.6))
	if font:
		_title.add_theme_font_override("font", font)
	v.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1000, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 60)
	close.add_theme_font_size_override("font_size", 26)
	close.pressed.connect(toggle)
	v.add_child(close)
	if "extra" in hud:
		hud.extra.append(_btn)
		hud.extra.append(_panel)


func toggle() -> void:
	_panel.visible = not _panel.visible
	_key = ""
	if _panel.visible:
		refresh()


func is_open() -> bool:
	return _panel != null and _panel.visible


func refresh() -> void:
	var rs := rows()
	var key := str(rs)
	if key == _key:
		return
	_key = key
	for c in _grid.get_children():
		c.queue_free()
		_grid.remove_child(c)
	var tl = host.gather.tools if host.get("gather") != null else null
	_title.text = "Bag  ·  %d kinds%s" % [rs.size(), ("  ·  Axe: %s  ·  Pick: %s  ·  Gathering %d" % [tl.tier("axe"), tl.tier("pick"), tl.skill_level()]) if tl else ""]
	for r in rs:
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(320, 64)
		cell.add_theme_constant_override("separation", 12)
		var chip := PanelContainer.new()
		var cs := StyleBoxFlat.new()
		cs.bg_color = chip_color(r["id"])
		cs.border_color = Color(0, 0, 0, 0.5)
		cs.set_border_width_all(2)
		cs.set_corner_radius_all(6)
		chip.add_theme_stylebox_override("panel", cs)
		chip.custom_minimum_size = Vector2(44, 44)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ini := Label.new()
		ini.text = item_name(r["id"]).left(1)
		ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ini.add_theme_font_size_override("font_size", 24)
		ini.add_theme_color_override("font_color", Color(1, 1, 1, 0.9) if cs.bg_color.get_luminance() < 0.6 else Color(0.1, 0.08, 0.06))
		chip.add_child(ini)
		cell.add_child(chip)
		var lab := Label.new()
		lab.text = "%s  %d" % [item_name(r["id"]), r["n"]]
		lab.tooltip_text = str(items_meta.get(r["id"], {}).get("description", ""))
		lab.add_theme_font_size_override("font_size", 26)
		lab.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
		cell.add_child(lab)
		_grid.add_child(cell)


func _process(_d: float) -> void:
	if is_open():
		refresh()
