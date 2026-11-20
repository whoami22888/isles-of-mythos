extends Node
## Chapter 2 EVENT DIRECTOR. Loads every scenario file in data/scenarios/,
## keeps a seeded per-player RNG (seed + RNG state saved, so every player's
## run differs but a run is reproducible), a day/night clock and a weather
## state, and picks weighted eligible events by zone, day, camp level, weather,
## items, cooldowns, reputation and a pacing tension curve
## (quiet -> rising -> spike -> breather). Events open a card on the HUD:
## intro lines, choices (greyed with a reason when requirements fail), then a
## rolled outcome whose effects are applied (items, hp, morale, rep, spawn,
## pet_xp, unlock, chained next_event).
##
## Works headless with host == null (tests drive tick()/notify()/choose()).

signal event_opened(row: Dictionary)
signal event_resolved(id: String, choice: int, outcome: Dictionary)
signal spawn_requested(what: String)
signal pet_xp_gained(amount: int)
signal night_began(day: int)

const DIR := "res://gameplay/outpost/data/scenarios"
const NON_SCENARIO := ["items.json", "wildlife.json", "pet_training.json"]
const PHASES := ["quiet", "rising", "spike", "breather"]
## Phase -> [min secs, max secs, roll interval, max intensity]
const PHASE_CFG := {"quiet": [70.0, 120.0, 38.0, 1], "rising": [90.0, 150.0, 24.0, 2],
	"spike": [40.0, 70.0, 14.0, 3], "breather": [50.0, 90.0, 55.0, 1]}
const DAY_SECONDS := 480.0
const WEATHERS := ["clear", "rain", "storm", "fog"]
## Markov weights: from -> [clear, rain, storm, fog]
const WEATHER_NEXT := {"clear": [5, 2, 0.5, 1.5], "rain": [3, 2, 1.5, 0.5], "storm": [2, 3, 0.5, 0.5], "fog": [3, 1, 0.2, 1]}

var host: Node = null   # outpost.gd (optional)
var st                  # OutpostState
var events: Dictionary = {}   # id -> row
var files_loaded: Array = []
var extra_data: Dictionary = {}   # items / wildlife / pet_training json by stem
var rng := RandomNumberGenerator.new()
## Persisted director state (lives in st.ext["director"]).
var d: Dictionary = {}
var active: Dictionary = {}   # the open card's row
var last_outcome: Dictionary = {}
var zone_fn: Callable   # () -> String; host supplies the player's zone
var paused := false
var _roll_t := 0.0
var _ui: Control
var _card: PanelContainer
var _card_box: VBoxContainer
var _clock_lab: Label


func setup(state, seed_value: int = 0, dir: String = DIR) -> void:
	st = state
	load_dir(dir)
	var saved: Dictionary = st.ext.get("director", {})
	if saved.has("seed") and seed_value == 0:
		d = saved
		rng.seed = int(d["seed"])
		if d.has("rng_state"):
			rng.state = int(str(d["rng_state"]))
	else:
		var s := seed_value
		if s == 0:
			s = int(Time.get_unix_time_from_system() * 1000.0) ^ randi()
		d = {"seed": s, "clock": DAY_SECONDS * 0.3, "day": 1, "weather": "clear", "weather_left": 150.0,
			"phase": "quiet", "phase_left": 90.0, "cooldowns": {}, "morale": 60, "rep": {"utc": 0, "tideborn": 0, "free": 0},
			"notoriety": 0, "unlocks": [], "queue": [], "history": [], "seen": {}, "was_night": false, "flags": {}}
		rng.seed = s
	st.ext["director"] = d
	_roll_t = float(PHASE_CFG[phase()][2])   # no RNG draw: keeps a restored stream exact


func load_dir(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	var names: Array = []
	for f in da.get_files():
		var fn := str(f).trim_suffix(".remap")
		if fn.ends_with(".json"):
			names.append(fn)
	names.sort()   # deterministic order regardless of filesystem
	for fn in names:
		var file := FileAccess.open(dir + "/" + fn, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		if fn in NON_SCENARIO:
			extra_data[fn.trim_suffix(".json")] = parsed
			continue
		var rows: Array = []
		if parsed is Array:
			rows = parsed
		elif parsed is Dictionary:
			rows = parsed.get("scenarios", parsed.get("events", []))
		for row in rows:
			if row is Dictionary and row.has("id") and row.has("choices"):
				events[str(row["id"])] = row
		files_loaded.append(fn)


func save_state() -> void:
	d["rng_state"] = str(rng.state)
	st.ext["director"] = d


# --- Clock & weather ----------------------------------------------------------

func time_of_day() -> float:
	return fmod(float(d["clock"]), DAY_SECONDS) / DAY_SECONDS


func is_night() -> bool:
	var t := time_of_day()
	return t >= 0.78 or t < 0.2


func part_of_day() -> String:
	var t := time_of_day()
	if t < 0.2 or t >= 0.85:
		return "night"
	if t < 0.3:
		return "dawn"
	if t < 0.7:
		return "day"
	return "dusk"


func day() -> int:
	return int(d["day"])


func weather() -> String:
	return str(d["weather"])


## 0 at midnight, 1 at noon (for the sun).
func daylight() -> float:
	return clampf(0.5 - 0.5 * cos(time_of_day() * TAU), 0.0, 1.0)


func set_weather(w: String) -> void:
	d["weather"] = w
	d["weather_left"] = rng.randf_range(120.0, 260.0)


func _tick_clock(delta: float) -> void:
	var before := int(float(d["clock"]) / DAY_SECONDS)
	d["clock"] = float(d["clock"]) + delta
	var after := int(float(d["clock"]) / DAY_SECONDS)
	if after > before:
		d["day"] = int(d["day"]) + 1
	var night := is_night()
	if night and not bool(d.get("was_night", false)):
		night_began.emit(day())
		if st.level_of("watchtower") == 0:
			notify("night_no_watchtower")
		notify("nightfall")
	d["was_night"] = night
	d["weather_left"] = float(d["weather_left"]) - delta
	if float(d["weather_left"]) <= 0.0:
		var ws: Array = WEATHER_NEXT.get(weather(), WEATHER_NEXT["clear"])
		set_weather(WEATHERS[_weighted_index(ws)])


func _weighted_index(ws: Array) -> int:
	var total := 0.0
	for w in ws:
		total += float(w)
	var r := rng.randf() * total
	for i in ws.size():
		r -= float(ws[i])
		if r <= 0.0:
			return i
	return ws.size() - 1


# --- Tension curve ------------------------------------------------------------

func phase() -> String:
	return str(d["phase"])


func _interval() -> float:
	var c: Array = PHASE_CFG[phase()]
	return float(c[2]) * rng.randf_range(0.75, 1.3)


func _next_phase() -> void:
	var i := PHASES.find(phase())
	d["phase"] = PHASES[(i + 1) % PHASES.size()]
	var c: Array = PHASE_CFG[phase()]
	d["phase_left"] = rng.randf_range(float(c[0]), float(c[1]))


static func intensity(row: Dictionary) -> int:
	if row.has("intensity"):
		return int(row["intensity"])
	var cat := str(row.get("category", "")).to_lower()
	for k in ["raid", "pirate", "combat", "attack", "battle"]:
		if k in cat:
			return 3
	for k in ["wildlife", "hazard", "weather", "threat", "storm", "disease", "danger"]:
		if k in cat:
			return 2
	return 1


# --- Main loop ----------------------------------------------------------------

func tick(delta: float) -> void:
	if paused:
		return
	_tick_clock(delta)
	d["phase_left"] = float(d["phase_left"]) - delta
	if float(d["phase_left"]) <= 0.0:
		_next_phase()
	var q: Array = d["queue"]
	for item in q:
		item["t"] = float(item["t"]) - delta
	if not active.is_empty():
		return
	for k in q.size():
		if float(q[k]["t"]) <= 0.0:
			var id := str(q[k]["id"])
			q.remove_at(k)
			if events.has(id):
				present(id)
				return
			break
	_roll_t -= delta
	if _roll_t <= 0.0:
		_roll_t = _interval()
		var id2 := pick()
		if id2 != "":
			present(id2)


func _process(delta: float) -> void:
	if st == null:
		return
	var busy: bool = host != null and host.raid != null and host.raid.active()
	if not busy:
		tick(delta)
	else:
		_tick_clock(delta)
	if _clock_lab:
		_clock_lab.text = "Day %d · %s · %s" % [day(), part_of_day().capitalize(), weather().capitalize()]


func context() -> Dictionary:
	var z := "camp"
	if zone_fn.is_valid():
		z = str(zone_fn.call())
	return {"zone": z, "day": day(), "camp_level": st.camp_level, "weather": weather(), "night": is_night(), "part": part_of_day()}


## Why `row` can't fire now ("" = eligible). `action` set for action triggers.
func ineligible(row: Dictionary, ctx: Dictionary, action: String = "") -> String:
	var tr: Dictionary = row.get("trigger", {})
	var ty := str(tr.get("type", "random"))
	if action != "":
		if ty != "action" or str(tr.get("action", "")) != action:
			return "not this action"
	elif ty == "action":
		return "waits for an action"
	var zones: Array = row.get("zones", [])
	if not zones.is_empty() and not ("any" in zones) and not (str(ctx["zone"]) in zones):
		return "zone"
	if int(ctx["day"]) < int(tr.get("min_day", 0)):
		return "too early"
	if int(ctx["camp_level"]) < int(tr.get("camp_level", 0)):
		return "camp level"
	var w = tr.get("weather", null)
	if w != null and str(w) != "" and str(w) != "any":
		var ws: Array = w if w is Array else [str(w)]
		if not (str(ctx["weather"]) in ws):
			return "weather"
	var item = tr.get("needs_item", null)
	if item != null and str(item) != "" and st.count(str(item)) <= 0:
		return "needs item"
	if ty == "time":
		var when := str(tr.get("time", tr.get("when", "")))
		if when == "night" and not bool(ctx["night"]):
			return "not night"
		if when in ["day", "dawn", "dusk"] and str(ctx["part"]) != when:
			return "not " + when
	if tr.has("night") and bool(tr["night"]) != bool(ctx["night"]):
		return "time of day"
	var cd: Dictionary = d["cooldowns"]
	if float(cd.get(str(row["id"]), -1.0)) > float(d["clock"]):
		return "cooldown"
	if bool(row.get("once", false)) and (d["seen"] as Dictionary).has(str(row["id"])):
		return "once"
	var rep: Dictionary = d["rep"]
	var rmin: Dictionary = tr.get("rep_min", {})
	for k in rmin.keys():
		if int(rep.get(k, 0)) < int(rmin[k]):
			return "rep"
	var rmax: Dictionary = tr.get("rep_max", {})
	for k in rmax.keys():
		if int(rep.get(k, 0)) > int(rmax[k]):
			return "rep"
	if int(d["notoriety"]) < int(tr.get("min_notoriety", 0)):
		return "notoriety"
	var un = tr.get("needs_unlock", null)
	if un != null and not (str(un) in d["unlocks"]):
		return "locked"
	if action == "" and intensity(row) > int(PHASE_CFG[phase()][3]):
		return "pacing"
	return ""


func eligible(ctx: Dictionary = {}, action: String = "") -> Array:
	if ctx.is_empty():
		ctx = context()
	var out: Array = []
	var ids: Array = events.keys()
	ids.sort()
	for id in ids:
		if ineligible(events[id], ctx, action) == "":
			out.append(id)
	return out


## Weighted pick among eligible events ("" when none or the chance roll fails).
func pick(ctx: Dictionary = {}, action: String = "") -> String:
	var ids := eligible(ctx, action)
	if ids.is_empty():
		return ""
	var ws: Array = []
	for id in ids:
		var row: Dictionary = events[id]
		var w := float(row.get("weight", 1.0))
		if phase() == "spike":
			w *= 4.0 if intensity(row) >= 3 else 1.0
		if (d["seen"] as Dictionary).has(id):
			w *= 0.5   # favour fresh events
		ws.append(w)
	var id: String = ids[_weighted_index(ws)]
	var chance := float(events[id].get("trigger", {}).get("chance", 1.0))
	if rng.randf() > chance:
		return ""
	return id


## A player action happened (looted a relic, killed a raider, ...).
func notify(action: String) -> String:
	if action == "loot_utc_relic":
		d["notoriety"] = int(d["notoriety"]) + 15
	elif action == "kill_raider":
		d["notoriety"] = int(d["notoriety"]) + 2
	if not active.is_empty():
		return ""
	var id := pick({}, action)
	if id != "":
		present(id)
	return id


func queue_event(id: String, delay: float = 6.0) -> void:
	(d["queue"] as Array).append({"id": id, "t": delay})


## Peek at the zone the next likely event belongs to (pet scout).
func scout() -> String:
	var ids := eligible()
	if ids.is_empty():
		return ""
	var zs: Array = events[ids[0]].get("zones", [])
	return str(zs[0]) if not zs.is_empty() else "camp"


# --- Cards ----------------------------------------------------------------------

func present(id: String) -> void:
	active = events[id]
	(d["seen"] as Dictionary)[id] = int((d["seen"] as Dictionary).get(id, 0)) + 1
	(d["cooldowns"] as Dictionary)[id] = float(d["clock"]) + float(active.get("cooldown_s", 300))
	event_opened.emit(active)
	_show_card()


## "" when the player may pick this choice, else the reason.
func choice_block(ch: Dictionary) -> String:
	var req = ch.get("requires", null)
	if req == null or (req is Dictionary and req.is_empty()) or (req is String and req == ""):
		return ""
	if req is String:
		return "" if (str(req) in d["unlocks"] or st.count(str(req)) > 0) else "Needs " + str(req).replace("_", " ")
	var r: Dictionary = req
	var items: Dictionary = (r.get("items", {}) as Dictionary).duplicate()
	for k in r.keys():
		if not (k in ["items", "pet_level", "rep", "unlock", "camp_level", "building", "morale", "crew"]):
			items[k] = r[k]   # shorthand {wood: 5}
	var miss: Array = []
	for k in items.keys():
		if st.count(str(k)) < int(items[k]):
			miss.append("%d %s" % [int(items[k]), str(k).replace("_", " ")])
	if not miss.is_empty():
		return "Needs " + ", ".join(miss)
	if r.has("pet_level"):
		var plv := int(st.ext.get("pet", {}).get("level", 1))
		if plv < int(r["pet_level"]):
			return "Pet level %d" % int(r["pet_level"])
	if r.has("camp_level") and st.camp_level < int(r["camp_level"]):
		return "Camp level %d" % int(r["camp_level"])
	if r.has("building") and st.level_of(str(r["building"])) == 0:
		return "Needs a " + st.title(str(r["building"]))
	if r.has("unlock") and not (str(r["unlock"]) in d["unlocks"]):
		return "Locked"
	if r.has("morale") and int(d["morale"]) < int(r["morale"]):
		return "Morale too low"
	if r.has("crew") and st.crew_slots() == 0:
		return "Needs crew"
	var rq: Dictionary = r.get("rep", {})
	for k in rq.keys():
		if int(d["rep"].get(k, 0)) < int(rq[k]):
			return "%s standing too low" % str(k).capitalize()
	return ""


## Resolve choice `idx` on the open card. Returns the outcome (with "text").
func choose(idx: int) -> Dictionary:
	if active.is_empty():
		return {}
	var choices: Array = active.get("choices", [])
	if idx < 0 or idx >= choices.size():
		return {}
	var ch: Dictionary = choices[idx]
	if choice_block(ch) != "":
		return {}
	var outs: Array = ch.get("outcomes", [])
	var outcome: Dictionary = {}
	if not outs.is_empty():
		var ws: Array = []
		for o in outs:
			ws.append(maxf(float(o.get("chance", 1.0)), 0.0001))
		outcome = outs[_weighted_index(ws)]
	var row := active
	active = {}
	apply(outcome.get("effects", {}))
	var hist: Array = d["history"]
	hist.append({"id": str(row["id"]), "c": idx, "day": day()})
	if hist.size() > 60:
		hist.pop_front()
	last_outcome = outcome
	if st and str(row.get("history_note", "")) != "" and st.journal.size() < 400:
		st.journal.append({"title": str(row.get("title", "")), "text": str(outcome.get("text", ""))})
	event_resolved.emit(str(row["id"]), idx, outcome)
	save_state()
	_show_outcome(row, outcome)
	return outcome


func apply(fx: Dictionary) -> void:
	var items: Dictionary = fx.get("items", {})
	for k in items.keys():
		st.add_item(str(k), int(items[k]))
	if int(items.get("relic", 0)) > 0:
		call_deferred("notify", "loot_utc_relic")
	if fx.has("hp") and host != null:
		var hpv := float(fx["hp"])
		if hpv < 0.0:
			host.hurt_player(-hpv, host._player.global_position)
		else:
			host.player_hp = minf(host.player_hp + hpv, host.player_max)
	if fx.has("morale"):
		d["morale"] = clampi(int(d["morale"]) + int(fx["morale"]), 0, 100)
	var rep: Dictionary = fx.get("rep", {})
	for k in rep.keys():
		d["rep"][k] = clampi(int(d["rep"].get(k, 0)) + int(rep[k]), -100, 100)
	if fx.has("notoriety"):
		d["notoriety"] = maxi(int(d["notoriety"]) + int(fx["notoriety"]), 0)
	var sp = fx.get("spawn", null)
	if sp != null:
		for what in (sp if sp is Array else [sp]):
			if str(what) != "":
				spawn_requested.emit(str(what))
	if int(fx.get("pet_xp", 0)) != 0:
		pet_xp_gained.emit(int(fx["pet_xp"]))
	var un = fx.get("unlock", null)
	if un != null:
		for u in (un if un is Array else [un]):
			if str(u) != "" and not (str(u) in d["unlocks"]):
				(d["unlocks"] as Array).append(str(u))
	var nx = fx.get("next_event", null)
	if nx != null and str(nx) != "":
		queue_event(str(nx), float(fx.get("next_delay", 8.0)))
	if fx.has("weather"):
		set_weather(str(fx["weather"]))


func morale() -> int:
	return int(d["morale"])


func rep(faction: String) -> int:
	return int(d["rep"].get(faction, 0))


func has_unlock(u: String) -> bool:
	return u in d["unlocks"]


# --- UI -------------------------------------------------------------------------

func build_ui(hud: CanvasLayer, font: Font) -> void:
	_ui = Control.new()
	_ui.name = "EventsUI"
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_ui)
	_clock_lab = Label.new()
	_clock_lab.add_theme_font_size_override("font_size", 24)
	_clock_lab.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	_clock_lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_clock_lab.add_theme_constant_override("outline_size", 6)
	_clock_lab.position = Vector2(26, 112)
	_ui.add_child(_clock_lab)
	_card = PanelContainer.new()
	_card.name = "EventCard"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.06, 0.92)
	sb.border_color = Color(0.62, 0.48, 0.28)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(22)
	_card.add_theme_stylebox_override("panel", sb)
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left = -430
	_card.offset_right = 430
	_card.offset_top = -260
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.visible = false
	_ui.add_child(_card)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 12)
	_card.add_child(_card_box)
	if font:
		_card.add_theme_font_override("font", font)
	if "extra" in hud:
		hud.extra.append(_card)


func _text(t: String, size: int, col: Color = Color(0.95, 0.92, 0.85)) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 800
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	_card_box.add_child(l)
	return l


func _clear_card() -> void:
	for c in _card_box.get_children():
		c.queue_free()
		_card_box.remove_child(c)


func _show_card() -> void:
	if _card == null:
		return
	_clear_card()
	_text(str(active.get("title", "")), 38, Color(1.0, 0.85, 0.55))
	var lines: Array = active.get("intro_lines", [])
	for i in mini(lines.size(), 3):
		_text(str(lines[i]), 27)
	var choices: Array = active.get("choices", [])
	for i in choices.size():
		var ch: Dictionary = choices[i]
		var why := choice_block(ch)
		var b := Button.new()
		b.text = str(ch.get("label", "...")) + ("   (%s)" % why if why != "" else "")
		b.disabled = why != ""
		b.custom_minimum_size = Vector2(800, 66)
		b.add_theme_font_size_override("font_size", 27)
		b.pressed.connect(choose.bind(i))
		_card_box.add_child(b)
	_card.visible = true
	_card.reset_size()


func _show_outcome(row: Dictionary, outcome: Dictionary) -> void:
	if _card == null:
		return
	_clear_card()
	_text(str(row.get("title", "")), 34, Color(1.0, 0.85, 0.55))
	_text(str(outcome.get("text", "")), 27)
	var fx: Dictionary = outcome.get("effects", {})
	var bits: Array = []
	var items: Dictionary = fx.get("items", {})
	for k in items.keys():
		bits.append("%+d %s" % [int(items[k]), str(k).replace("_", " ")])
	if fx.has("hp"):
		bits.append("%+d HP" % int(fx["hp"]))
	if fx.has("morale"):
		bits.append("%+d morale" % int(fx["morale"]))
	var rp: Dictionary = fx.get("rep", {})
	for k in rp.keys():
		bits.append("%+d %s" % [int(rp[k]), str(k).capitalize()])
	if int(fx.get("pet_xp", 0)) != 0:
		bits.append("+%d pet XP" % int(fx["pet_xp"]))
	if not bits.is_empty():
		_text("  ·  ".join(bits), 24, Color(0.75, 0.9, 0.7))
	var b := Button.new()
	b.text = "Continue"
	b.custom_minimum_size = Vector2(800, 62)
	b.add_theme_font_size_override("font_size", 27)
	b.pressed.connect(func(): _card.visible = false)
	_card_box.add_child(b)
	_card.reset_size()


func card_open() -> bool:
	return _card != null and _card.visible
