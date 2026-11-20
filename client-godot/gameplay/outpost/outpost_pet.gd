extends Node3D
## Chapter 2 pet training: Tide-Puck levels 1-10 from bites, events, feeding
## and training sessions at the Training Post. Commands unlock by level:
## fetch (brings nearby drops), dig (buried items at marked spots), guard
## (holds the stash, chases thieves), track (points to animals / rare nodes),
## fish (at the shore), scout (reveals the next event's zone).
## Trust and mood rise with feeding/petting and fall with neglect, and set
## obedience (a chance to ignore a command). Tuning from pet_training.json.

const XP_TABLE := [0, 30, 80, 150, 250, 380, 540, 740, 980, 1260]
const UNLOCKS := {"fetch": 2, "dig": 3, "guard": 4, "track": 5, "fish": 6, "scout": 7}
const COMMANDS := ["fetch", "dig", "guard", "track", "fish", "scout"]
const DIG_LOOT := [["gold", 6, 14, 4.0], ["iron", 2, 5, 3.0], ["flint", 1, 3, 3.0], ["pearl", 1, 1, 1.0], ["map_fragment", 1, 1, 0.8], ["rum", 1, 1, 1.0]]

signal levelled(level: int)

var host: Node = null
var st
var p: Dictionary = {}   # persisted: level, xp, trust, mood, fed_t
var xp_table: Array = XP_TABLE
var unlocks: Dictionary = UNLOCKS
var rng := RandomNumberGenerator.new()
var mode := "follow"   # follow | fetch | dig | guard | fish
var drops: Array = []   # [{node, items, pos}]
var dig_spots: Array = []   # [{pos, node}]
var _pet_cd := 0.0
var _train_cd := 0.0
var _decay_t := 0.0
var _goal := Vector3.INF
var _busy_t := 0.0
var _panel: PanelContainer
var _panel_box: VBoxContainer
var _btn: Button


func setup(state, cfg = null) -> void:
	st = state
	p = st.ext.get("pet", {})
	if p.is_empty():
		p = {"level": 1, "xp": 0, "trust": 40, "mood": 70}
	st.ext["pet"] = p
	if cfg is Dictionary:
		xp_table = cfg.get("xp_table", XP_TABLE)
		var u = cfg.get("unlocks", cfg.get("commands", null))
		if u is Dictionary:
			unlocks = {}
			for k in u.keys():
				unlocks[k] = int(u[k]) if not (u[k] is Dictionary) else int(u[k].get("level", UNLOCKS.get(k, 10)))
	rng.seed = int(st.ext.get("director", {}).get("seed", 5)) + 911


func level() -> int:
	return int(p["level"])


func xp() -> int:
	return int(p["xp"])


func trust() -> int:
	return int(p["trust"])


func mood() -> int:
	return int(p["mood"])


func add_xp(n: int) -> void:
	p["xp"] = xp() + n
	while level() < xp_table.size() and xp() >= int(xp_table[level()]):
		p["level"] = level() + 1
		levelled.emit(level())
		var newc := ""
		for c in COMMANDS:
			if int(unlocks.get(c, 99)) == level():
				newc = c
		_toast("%s reached level %d%s" % [st.pet_name, level(), ("  ·  learned " + newc.capitalize()) if newc != "" else ""])


func unlocked(cmd: String) -> bool:
	return level() >= int(unlocks.get(cmd, 99))


func obedience() -> float:
	return clampf(0.3 + trust() / 100.0 * 0.55 + mood() / 100.0 * 0.15, 0.3, 0.98)


func _bump(trust_d: int, mood_d: int) -> void:
	p["trust"] = clampi(trust() + trust_d, 0, 100)
	p["mood"] = clampi(mood() + mood_d, 0, 100)


func feed() -> String:
	var food := ""
	for k in ["fish", "meat", "food"]:
		if st.count(k) >= (1 if k != "food" else 2):
			food = k
			break
	if food == "":
		return "No food"
	st.add_item(food, -(1 if food != "food" else 2))
	_bump(6 if food != "food" else 4, 18)
	add_xp(5)
	_toast("%s wolfs down the %s" % [st.pet_name, food])
	return ""


func pet_pet() -> String:
	if _pet_cd > 0.0:
		return "Let it be a moment"
	_pet_cd = 15.0
	_bump(3, 8)
	_toast("%s leans into your hand" % st.pet_name)
	return ""


func train() -> String:
	if st.level_of("training_post") == 0:
		return "Build a Training Post"
	if _train_cd > 0.0:
		return "Rest %ds" % int(ceil(_train_cd))
	if st.count("food") < 2 and st.count("fish") < 1 and st.count("meat") < 1:
		return "Needs treats (food)"
	if host and host.has_method("site_pos") and Vector2(host._player.global_position.x - host.site_pos("training_post").x, host._player.global_position.z - host.site_pos("training_post").z).length() > 6.0:
		return "Go to the Training Post"
	if st.count("fish") > 0:
		st.add_item("fish", -1)
	elif st.count("meat") > 0:
		st.add_item("meat", -1)
	else:
		st.add_item("food", -2)
	_train_cd = 30.0
	_bump(2, -4)
	add_xp(25)
	_toast("Training session: +25 XP")
	return ""


## Issue a command. "" when it runs; otherwise the reason (incl. "ignored").
func command(cmd: String) -> String:
	if not unlocked(cmd):
		return "Unlocks at level %d" % int(unlocks.get(cmd, 99))
	if rng.randf() > obedience():
		_toast("%s ignores you%s" % [st.pet_name, " and sulks" if mood() < 30 else ", nose in the sand"])
		return "ignored"
	add_xp(2)
	match cmd:
		"fetch":
			if drops.is_empty():
				return "Nothing to fetch"
			mode = "fetch"
		"dig":
			var spot := nearest_dig(_pet_pos(), 6.0)
			if spot < 0:
				return "No dig spot nearby"
			mode = "dig"
			_goal = dig_spots[spot]["pos"]
		"guard":
			mode = "follow" if mode == "guard" else "guard"
			if host and host.get("wildlife") != null:
				host.wildlife.guard_pos = _stash() if mode == "guard" else Vector3.INF
			_toast("%s %s" % [st.pet_name, "guards the stash" if mode == "guard" else "comes back to heel"])
		"track":
			_toast(track_text())
		"fish":
			if host and host.zone_at_player() != "beach":
				return "Needs the shore"
			mode = "fish"
			_busy_t = 3.0
		"scout":
			var z := ""
			if host and host.get("events") != null:
				z = host.events.scout()
			_toast(("%s sniffs the wind toward the %s. Something's coming there." % [st.pet_name, z]) if z != "" else "%s finds nothing on the wind" % st.pet_name)
	return ""


func track_text() -> String:
	if host == null:
		return ""
	var at := _pet_pos()
	var best := Vector3.INF
	var what := ""
	if host.get("wildlife") != null:
		for a in host.wildlife.alive():
			var q: Vector3 = (a["node"] as Node3D).global_position
			if best == Vector3.INF or q.distance_to(at) < best.distance_to(at):
				best = q
				what = "a " + str(a["kind"])
	if host.get("gather") != null:
		for n in host.gather.nodes:
			if str(n["kind"]) in ["iron_seam", "tide_pool", "flint"] and float(n["left"]) <= 0.0:
				var q2: Vector3 = n["pos"]
				if best == Vector3.INF or q2.distance_to(at) < best.distance_to(at) - 4.0:
					best = q2
					what = str(n["kind"]).replace("_", " ")
	if best == Vector3.INF:
		return "%s finds no scent" % st.pet_name
	var d := best - at
	var dirs := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var ang := fposmod(rad_to_deg(atan2(d.x, d.z)) + 22.5, 360.0)
	return "%s points %s: %s, %dm" % [st.pet_name, dirs[int(ang / 45.0) % 8], what, int(d.length())]


## Bites during raids also train the pup.
func on_bite() -> void:
	add_xp(3)


# --- World ----------------------------------------------------------------------

func _pet_pos() -> Vector3:
	return host._pet.global_position if host else Vector3.ZERO


func _stash() -> Vector3:
	return host.site_pos("camp") + Vector3(-1.0, 0, 2.6) if host else Vector3.ZERO


func _toast(t: String) -> void:
	if host and host.has_method("_toast"):
		host._toast(t)


func controls_pet() -> bool:
	return mode != "follow"


func drop_at(at: Vector3, items: Dictionary) -> void:
	if items.is_empty():
		return
	var n := Node3D.new()
	n.name = "Drop"
	add_child(n)
	at.y = float(host.ground_y(at.x, at.z)) if host else at.y
	n.global_position = at
	const W := preload("res://gameplay/outpost/outpost_wildlife.gd")
	W._part(n, W._sphere(), Vector3(0, 0.14, 0), Vector3(0.34, 0.28, 0.3), Color(0.5, 0.42, 0.3))
	W._part(n, W._cyl(0.03, 0.05), Vector3(0, 0.3, 0), Vector3(1, 0.1, 1), Color(0.35, 0.28, 0.2))
	drops.append({"node": n, "items": items, "pos": at})


func _pickup(i: int, by_pet: bool) -> void:
	var dr: Dictionary = drops[i]
	drops.remove_at(i)
	for k in dr["items"].keys():
		st.add_item(str(k), int(dr["items"][k]))
	if host:
		host.fly_from_world(dr["pos"] + Vector3.UP, dr["items"])
		_toast(("%s brings back " % st.pet_name if by_pet else "Picked up ") + st.cost_text(dr["items"]))
	if is_instance_valid(dr["node"]):
		dr["node"].queue_free()
	if by_pet:
		add_xp(2)


func nearest_dig(at: Vector3, r: float) -> int:
	var best := -1
	for i in dig_spots.size():
		var dd := (dig_spots[i]["pos"] as Vector3).distance_to(at)
		if dd < r:
			r = dd
			best = i
	return best


func _place_dig_spots() -> void:
	const W := preload("res://gameplay/outpost/outpost_wildlife.gd")
	var cands := [Vector3(3.5, 0, 3.0), Vector3(13, 0, 2.6), Vector3(20, 0, 3.4), Vector3(5, 0, 6.5), Vector3(13, 0, 16), Vector3(17, 0, 4.5)]
	while dig_spots.size() < 3:
		var c: Vector3 = cands[rng.randi() % cands.size()]
		var dup := false
		for s in dig_spots:
			if (s["pos"] as Vector3).distance_to(c) < 1.0:
				dup = true
		if dup:
			continue
		c.y = float(host.ground_y(c.x, c.z)) if host else 0.0
		var n := Node3D.new()
		n.name = "DigSpot"
		add_child(n)
		n.global_position = c
		W._part(n, W._sphere(), Vector3(0, 0.02, 0), Vector3(0.9, 0.08, 0.7), Color(0.46, 0.38, 0.27))
		W._part(n, W._sphere(), Vector3(0.25, 0.05, 0.1), Vector3(0.18, 0.06, 0.14), Color(0.4, 0.33, 0.24))
		dig_spots.append({"pos": c, "node": n})


func dig_roll() -> Dictionary:
	var total := 0.0
	for r in DIG_LOOT:
		total += float(r[3])
	var x := rng.randf() * total
	for r in DIG_LOOT:
		x -= float(r[3])
		if x <= 0.0:
			return {str(r[0]): rng.randi_range(int(r[1]), int(r[2]))}
	return {"gold": 5}


func _ready() -> void:
	if host:
		call_deferred("_place_dig_spots")


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	_pet_cd = maxf(_pet_cd - delta, 0.0)
	_train_cd = maxf(_train_cd - delta, 0.0)
	_decay_t += delta
	if _decay_t >= 20.0:
		_decay_t = 0.0
		_bump(-1 if mood() < 25 else 0, -1)
	if host == null:
		return
	var pp: Vector3 = host._player.global_position
	for i in range(drops.size() - 1, -1, -1):
		if (drops[i]["pos"] as Vector3).distance_to(pp) < 1.4:
			_pickup(i, false)
	if _panel and _panel.visible:
		_refresh_panel()


## outpost.gd calls this instead of the normal follow while controls_pet().
func drive(delta: float) -> void:
	var pet: Node3D = host._pet
	match mode:
		"fetch":
			if drops.is_empty():
				mode = "follow"
				return
			var d0: Dictionary = drops[0]
			if _move(pet, d0["pos"], delta):
				_pickup(0, true)
		"dig":
			if _move(pet, _goal, delta):
				var i := nearest_dig(_goal, 1.0)
				if i >= 0:
					var got := dig_roll()
					var spot: Dictionary = dig_spots[i]
					dig_spots.remove_at(i)
					if is_instance_valid(spot["node"]):
						spot["node"].queue_free()
					drop_at(_goal + Vector3(0.6, 0, 0), got)
					_toast("%s digs up something!" % st.pet_name)
					add_xp(6)
					get_tree().create_timer(90.0).timeout.connect(_place_dig_spots)
				mode = "fetch"
		"guard":
			_move(pet, _stash() + Vector3(0.8, 0, 0), delta)
		"fish":
			_busy_t -= delta
			if _busy_t <= 0.0:
				mode = "follow"
				var n := 0
				if rng.randf() < 0.35 + level() * 0.04:
					n = rng.randi_range(1, 2 + level() / 4)
				if n > 0:
					st.add_item("fish", n)
					if rng.randf() < 0.03:
						st.add_item("pearl", 1)
						_toast("%s brings up %d fish and a pearl!" % [st.pet_name, n])
					else:
						_toast("%s brings up %d fish" % [st.pet_name, n])
					add_xp(4)
				else:
					_toast("%s comes back wet and empty-mouthed" % st.pet_name)


func _move(pet: Node3D, goal: Vector3, delta: float) -> bool:
	var to := goal - pet.global_position
	to.y = 0
	if to.length() < 0.6:
		return true
	var q := pet.global_position + to.normalized() * minf(4.5 * delta, to.length())
	q.y = float(host.ground_y(q.x, q.z))
	pet.look_at(Vector3(goal.x, q.y, goal.z), Vector3.UP)
	pet.global_position = q
	return false


# --- Panel ------------------------------------------------------------------------

func build_ui(hud: CanvasLayer, font: Font) -> void:
	_btn = Button.new()
	_btn.text = "Pup"
	_btn.add_theme_font_size_override("font_size", 28)
	_btn.anchor_left = 1.0
	_btn.anchor_right = 1.0
	_btn.offset_left = -150
	_btn.offset_right = -24
	_btn.offset_top = 150
	_btn.offset_bottom = 210
	_btn.pressed.connect(toggle_panel)
	hud.add_child(_btn)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.06, 0.9)
	sb.border_color = Color(0.55, 0.45, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -470
	_panel.offset_right = -24
	_panel.offset_top = 220
	_panel.visible = false
	hud.add_child(_panel)
	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 8)
	_panel.add_child(_panel_box)
	if "extra" in hud:
		hud.extra.append(_btn)
		hud.extra.append(_panel)


func toggle_panel() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_refresh_panel(true)


var _panel_key := ""


func _refresh_panel(force: bool = false) -> void:
	var key := "%d/%d/%d/%d/%s/%d" % [level(), xp(), trust(), mood(), mode, int(_train_cd)]
	if key == _panel_key and not force:
		return
	_panel_key = key
	for c in _panel_box.get_children():
		c.queue_free()
		_panel_box.remove_child(c)
	var nxt := int(xp_table[level()]) if level() < xp_table.size() else xp()
	_lab("%s  ·  Level %d" % [st.pet_name, level()], 30)
	_lab("XP %d / %d   Trust %d   Mood %d   Obeys %d%%" % [xp(), nxt, trust(), mood(), int(obedience() * 100)], 22)
	var row := HBoxContainer.new()
	_panel_box.add_child(row)
	for pair in [["Feed", feed], ["Pet", pet_pet], ["Train", train]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(130, 58)
		b.add_theme_font_size_override("font_size", 24)
		var f: Callable = pair[1]
		b.pressed.connect(func():
			var why: String = f.call()
			if why != "":
				_toast(why)
			_refresh_panel(true))
		row.add_child(b)
	var grid := GridContainer.new()
	grid.columns = 2
	_panel_box.add_child(grid)
	for cmd in COMMANDS:
		var b2 := Button.new()
		var ok := unlocked(cmd)
		b2.text = cmd.capitalize() + ("" if ok else "  (Lv %d)" % int(unlocks.get(cmd, 99)))
		if cmd == "guard" and mode == "guard":
			b2.text = "Stop guarding"
		b2.disabled = not ok
		b2.custom_minimum_size = Vector2(205, 58)
		b2.add_theme_font_size_override("font_size", 24)
		b2.pressed.connect(func():
			var why2 := command(cmd)
			if why2 != "" and why2 != "ignored":
				_toast(why2)
			_refresh_panel(true))
		grid.add_child(b2)


func _lab(t: String, size: int) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	_panel_box.add_child(l)
