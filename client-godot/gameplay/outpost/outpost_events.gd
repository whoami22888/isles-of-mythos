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
const NON_SCENARIO := ["items.json", "wildlife.json", "pet_training.json", "stats.json"]
## The player stands in one of 3 map zones; scenario zones alias onto them.
const ZONE_ALIAS := {"beach": ["beach", "reef", "sea", "isle", "shore"], "camp": ["camp", "outpost"], "jungle": ["jungle", "cliff", "cave", "isle"]}
const PHASES := ["quiet", "rising", "spike", "breather"]
## Phase -> [min secs, max secs, roll interval, max intensity]
const PHASE_CFG := {"quiet": [70.0, 120.0, 38.0, 1], "rising": [90.0, 150.0, 24.0, 2],
	"spike": [40.0, 70.0, 14.0, 3], "breather": [50.0, 90.0, 55.0, 1]}
const DAY_SECONDS := 480.0
## Named system actions; unnamed action-trigger scenarios ignore these.
const SPECIAL_ACTIONS := ["night_no_watchtower", "nightfall", "loot_utc_relic", "kill_raider"]
const WEATHERS := ["clear", "rain", "storm", "fog", "heat"]
## Markov weights: from -> [clear, rain, storm, fog, heat]
const WEATHER_NEXT := {"clear": [5, 2, 0.5, 1.5, 1.5], "rain": [3, 2, 1.5, 0.5, 0.2], "storm": [2, 3, 0.5, 0.5, 0], "fog": [3, 1, 0.2, 1, 0.3], "heat": [3, 0.5, 0.8, 0.2, 2]}

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
## The live world event: {row, node, pos, verbs: {verb: choice idx}, t, near}
var world: Dictionary = {}
var world_timeout := 75.0
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
	_tick_world(delta)
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
		# Named action triggers match exactly; unnamed ones fire on any
		# ordinary player action (gathering, hunting, building).
		var want := str(tr.get("action", "")) if tr.get("action", null) != null else ""
		if ty != "action" or (want != "" and want != action) or (want == "" and action in SPECIAL_ACTIONS):
			return "not this action"
		if float(tr.get("chance", 1.0)) <= 0.0:
			return "chain only"
	elif ty == "action":
		return "waits for an action"
	elif float(tr.get("chance", 1.0)) <= 0.0:
		return "chain only"
	var zones: Array = row.get("zones", [])
	if not zones.is_empty() and not ("any" in zones):
		var ok_zone := false
		for zz in ZONE_ALIAS.get(str(ctx["zone"]), [str(ctx["zone"])]):
			if zz in zones:
				ok_zone = true
		if not ok_zone:
			return "zone"
	if int(ctx["day"]) < int(tr.get("min_day", 0)):
		return "too early"
	if int(ctx["camp_level"]) < int(tr.get("camp_level", 0)):
		return "camp level"
	var w = tr.get("weather", null)
	if w != null and str(w) != "" and str(w) != "any":
		var ws: Array = w if w is Array else [str(w)]
		var ok_w := false
		for wv in ws:
			if str(wv) == str(ctx["weather"]) or (str(wv) == "night" and bool(ctx["night"])) or (str(wv) == "day" and not bool(ctx["night"])):
				ok_w = true
		if not ok_w:
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
	_spawn_world()


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
	_world_outcome(row, outcome)
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

func build_ui(hud: CanvasLayer, _font: Font) -> void:
	_ui = Control.new()
	_ui.name = "EventsUI"
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_ui)
	_clock_lab = Label.new()
	_clock_lab.name = "Clock"
	_clock_lab.add_theme_font_size_override("font_size", 24)
	_clock_lab.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	_clock_lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_clock_lab.add_theme_constant_override("outline_size", 6)
	_clock_lab.position = Vector2(26, 152)
	_ui.add_child(_clock_lab)


# --- World events (no cards: choices are actions) --------------------------------

## Verb for a choice label (pet / ignore / strike / give, default interact).
static func verb_of(label: String) -> String:
	var l := " " + label.to_lower() + " "
	for k in ["dog", " pet", "pup", "sniff", "tide-puck", "puck"]:
		if k in l:
			return "pet"
	for k in ["leave", "hide", "ignore", "wait", "avoid", "retreat", "stay ", "back away", "let it", "let them", "walk away", "keep away", "do nothing", "lie low"]:
		if k in l:
			return "ignore"
	for k in ["attack", "fight", "kill", "strike", "shoot", "fire ", "ambush", "charge", "club", "spear", "hunt", "stab", "chase", "drive off", "throw"]:
		if k in l:
			return "strike"
	for k in ["trade", "give", "pay", "offer", "share", "barter", "hand over", "feed"]:
		if k in l:
			return "give"
	return "interact"


## verb -> choice index. When two choices share a verb (two ways to search a
## wreck), the seeded director picks which one this encounter is, so every
## branch stays reachable across runs without a menu.
func _verbs(row: Dictionary) -> Dictionary:
	var groups := {}
	var choices: Array = row.get("choices", [])
	for i in choices.size():
		var v := verb_of(str(choices[i].get("label", "")))
		if not groups.has(v):
			groups[v] = []
		groups[v].append(i)
	var out := {}
	for v in groups.keys():
		var g: Array = groups[v]
		out[v] = g[0] if g.size() == 1 else g[rng.randi() % g.size()]
	return out


## What physical thing marks this scenario in the world.
static func prop_kind(row: Dictionary) -> String:
	var t := (str(row.get("title", "")) + " " + " ".join(row.get("intro_lines", [])) + " " + str(row.get("category", ""))).to_lower()
	for pair in [["smoke", "smoke"], ["fire on", "smoke"], ["signal", "smoke"], ["track", "tracks"], ["print", "tracks"], ["footprint", "tracks"],
			["stranger", "npc"], ["survivor", "npc"], ["deserter", "npc"], ["officer", "npc"], ["scout", "npc"], ["sailor", "npc"], ["trader", "npc"], ["castaway", "npc"], ["man ", "npc"], ["woman", "npc"], ["boy", "npc"],
			["longboat", "boat"], ["boat", "boat"], ["canoe", "boat"], ["raft", "boat"], ["sail", "boat"],
			["barrel", "barrels"], ["cask", "barrels"], ["wreck", "wreck"], ["plank", "wreck"], ["driftwood", "wreck"], ["tide", "wreck"],
			["chest", "chest"], ["bottle", "bottle"], ["note", "bottle"], ["map", "chest"], ["relic", "chest"],
			["boar", "tracks"], ["monkey", "tracks"], ["gull", "tracks"], ["snake", "tracks"], ["crab", "tracks"], ["coffin", "chest"], ["locker", "chest"], ["cache", "chest"]]:
		if str(pair[0]) in t:
			return str(pair[1])
	return {"pirate": "npc", "faction": "npc", "wildlife": "tracks", "pet": "tracks", "sea": "wreck",
		"discovery": "chest", "mythos": "chest", "weather": "smoke"}.get(str(row.get("category", "")), "crate")


const ZONE_POINTS := {   # open ground clear of plots and gather nodes
	"beach": [Vector3(6.5, 0, 1.4), Vector3(11.2, 0, 1.0), Vector3(12.0, 0, 2.0), Vector3(7.2, 0, 2.2)],
	"camp": [Vector3(12.0, 0, 13.0), Vector3(7.0, 0, 12.8), Vector3(14.8, 0, 10.4), Vector3(11.8, 0, 6.6)],
	"jungle": [Vector3(1.5, 0, 8.5), Vector3(21.5, 0, 12.5), Vector3(20.5, 0, 17.5), Vector3(2.2, 0, 15.5)],
}


func _spawn_world() -> void:
	_clear_world()
	var row := active
	var z := "camp"
	if zone_fn.is_valid():
		z = str(zone_fn.call())
	var zs: Array = row.get("zones", [])
	if not _zone_ok(zs, z):
		for cand in ["beach", "camp", "jungle"]:
			if _zone_ok(zs, cand):
				z = cand
				break
	var pts: Array = ZONE_POINTS.get(z, ZONE_POINTS["camp"])
	var pp: Vector3 = host._player.global_position if host else Vector3.ZERO
	var best: Vector3 = pts[0]
	var best_s := 1e9
	for q in pts:
		var dd := (q as Vector3).distance_to(Vector3(pp.x, 0, pp.z))
		var sc := absf(dd - 6.0) + rng.randf() * 2.0   # a few strides away, never on top of you
		if sc < best_s:
			best_s = sc
			best = q
	world = {"row": row, "pos": best, "verbs": _verbs(row), "t": world_timeout, "near": false, "kind": prop_kind(row)}
	if host == null:
		return
	best.y = float(host.ground_y(best.x, best.z))
	world["pos"] = best
	var root := Node3D.new()
	root.name = "WorldEvent"
	host.add_child(root)
	root.global_position = best
	_build_prop(root, str(world["kind"]))
	var lab := Label3D.new()
	lab.text = str(row.get("title", ""))
	lab.font_size = 44
	lab.outline_size = 14
	lab.modulate = Color(1.0, 0.92, 0.75)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position = Vector3(0, 2.3, 0)
	lab.name = "Title"
	root.add_child(lab)
	world["node"] = root


func _zone_ok(zs: Array, z: String) -> bool:
	for zz in ZONE_ALIAS.get(z, [z]):
		if zz in zs:
			return true
	return "any" in zs or zs.is_empty()


func _build_prop(root: Node3D, kind: String) -> void:
	const A := preload("res://gameplay/opening/opening_art.gd")
	const W := preload("res://gameplay/outpost/outpost_wildlife.gd")
	match kind:
		"barrels":
			for i in 3:
				var b := A.spawn(A.BARRELS)
				root.add_child(b)
				A.fit_height(b, 0.8 - i * 0.12)
				b.position = Vector3(i * 0.7 - 0.7, 0, (i % 2) * 0.5)
				b.rotation_degrees = Vector3(0 if i != 2 else 80, i * 40, 0)
		"wreck":
			var p := A.spawn(A.PLANKS)
			root.add_child(p)
			A.fit_height(p, 0.35)
			var t := A.spawn(A.DRIFT_TRUNK)
			root.add_child(t)
			A.fit_height(t, 0.5)
			t.position = Vector3(0.9, 0, 0.4)
			t.rotation_degrees.y = 60
		"chest":
			var c := A.spawn(A.CHEST)
			root.add_child(c)
			A.fit_height(c, 0.55)
			c.rotation_degrees.y = 25
		"npc":
			var r := A.castaway(Color(0.3, 0.26, 0.22))
			root.add_child(r)
			A.fit_height(r, 1.74)
			A.play(r, "Idle")
			root.set_meta("npc", r)
		"boat":
			var h := A.spawn(A.HULL_STERN)
			root.add_child(h)
			A.fit_height(h, 1.1)
			var bx := A.world_aabb(h)
			if maxf(bx.size.x, bx.size.z) > 3.5:
				h.scale *= 3.5 / maxf(bx.size.x, bx.size.z)
		"smoke":
			var pit := MeshInstance3D.new()
			pit.mesh = W._cyl(0.45, 0.5)
			pit.scale = Vector3(1, 0.12, 1)
			pit.material_override = W._mat(Color(0.12, 0.1, 0.09))
			root.add_child(pit)
			var sm := CPUParticles3D.new()
			sm.amount = 26
			sm.lifetime = 5.0
			sm.direction = Vector3.UP
			sm.spread = 12.0
			sm.initial_velocity_min = 0.6
			sm.initial_velocity_max = 1.1
			sm.gravity = Vector3(0.25, 0.12, 0)
			sm.scale_amount_min = 0.6
			sm.scale_amount_max = 1.6
			var q := QuadMesh.new()
			q.size = Vector2(0.9, 0.9)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.42, 0.41, 0.4, 0.35)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			q.material = m
			sm.mesh = q
			sm.position.y = 0.2
			root.add_child(sm)
		"tracks":
			for i in 7:
				var mi := MeshInstance3D.new()
				mi.mesh = W._sphere()
				mi.scale = Vector3(0.14, 0.02, 0.2)
				mi.material_override = W._mat(Color(0.16, 0.12, 0.09))
				mi.position = Vector3((i % 2) * 0.22 - 0.11, 0.01, -1.5 + i * 0.5)
				root.add_child(mi)
		"bottle":
			var bt := MeshInstance3D.new()
			bt.mesh = W._cyl(0.035, 0.07)
			bt.scale = Vector3(1, 0.28, 1)
			bt.rotation_degrees.z = 80
			bt.position.y = 0.06
			var bm := W._mat(Color(0.22, 0.32, 0.24))
			bm.roughness = 0.35
			bt.material_override = bm
			root.add_child(bt)
		_:
			var cr := A.spawn(A.CRATE_A)
			root.add_child(cr)
			A.fit_height(cr, 0.6)
			cr.rotation_degrees.y = 20


func _clear_world() -> void:
	if world.has("node") and is_instance_valid(world["node"]):
		var n: Node3D = world["node"]
		var tw := n.create_tween()
		tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.35)
		tw.tween_callback(n.queue_free)
	world = {}


func world_pos() -> Vector3:
	return world.get("pos", Vector3.INF)


func _near(r: float) -> bool:
	if world.is_empty() or host == null:
		return false
	var p: Vector3 = world["pos"]
	var q: Vector3 = host._player.global_position
	return Vector2(p.x - q.x, p.z - q.z).length() < r


func _choice(verb: String) -> Dictionary:
	if not world.has("verbs") or not (world["verbs"] as Dictionary).has(verb):
		return {}
	return active.get("choices", [])[int(world["verbs"][verb])]


static func _need_text(ch: Dictionary) -> String:
	var req = ch.get("requires", {})
	if not (req is Dictionary):
		return ""
	var items: Dictionary = (req as Dictionary).get("items", {}).duplicate()
	for k in req.keys():
		if not (k in ["items", "pet_level", "rep", "unlock", "camp_level", "building", "morale", "crew"]):
			items[k] = req[k]
	var bits: Array = []
	for k in items.keys():
		bits.append("%d %s" % [int(items[k]), str(k).replace("_", " ")])
	return ", ".join(bits)


static func _short(label: String) -> String:
	var t := label.strip_edges()
	return t if t.length() <= 26 else t.left(24).strip_edges() + "…"


## Context-button text near the world event ("" when not in reach).
func world_action() -> String:
	if active.is_empty() or world.is_empty() or not _near(2.8):
		return ""
	var give := _choice("give")
	if not give.is_empty() and choice_block(give) == "":
		var need := _need_text(give)
		return ("Give " + need) if need != "" else _short(str(give.get("label", "Give")))
	var it := _choice("interact")
	if not it.is_empty():
		return _short(str(it.get("label", "Search")))
	if not _choice("strike").is_empty():
		return "Attack"
	if not give.is_empty():
		return "Need " + _need_text(give)
	return ""


## The context button pressed beside the world event.
func world_act() -> Dictionary:
	if world_action() == "":
		return {}
	for v in ["give", "interact", "strike"]:
		var ch := _choice(v)
		if not ch.is_empty() and choice_block(ch) == "":
			return choose(int(world["verbs"][v]))
	if host:
		host._toast(world_action())
	return {}


## A tap / strike on the event's prop or NPC (the strike verb).
func world_strike() -> Dictionary:
	if active.is_empty() or not _near(3.4):
		return {}
	var ch := _choice("strike")
	if ch.is_empty() or choice_block(ch) != "":
		return {}
	return choose(int(world["verbs"]["strike"]))


## A pet command issued with the event within sniffing range.
func world_pet() -> Dictionary:
	if active.is_empty() or not _near(14.0):
		return {}
	var ch := _choice("pet")
	if ch.is_empty() or choice_block(ch) != "":
		return {}
	return choose(int(world["verbs"]["pet"]))


func has_world_verb(verb: String) -> bool:
	return not _choice(verb).is_empty()


func _tick_world(delta: float) -> void:
	if active.is_empty() or world.is_empty():
		return
	world["t"] = float(world["t"]) - delta
	if _near(9.0):
		if not bool(world["near"]):
			world["near"] = true
			var lines: Array = active.get("intro_lines", [])
			if host and not lines.is_empty():
				host._toast(str(lines[0]))
	var walked_off: bool = bool(world["near"]) and not _near(24.0)
	if float(world["t"]) <= 0.0 or walked_off:
		var ig := _choice("ignore")
		if not ig.is_empty():
			choose(int(world["verbs"]["ignore"]))
		else:
			active = {}
			_clear_world()


func _world_outcome(_row: Dictionary, outcome: Dictionary) -> void:
	var at: Vector3 = world.get("pos", Vector3.ZERO)
	_clear_world()
	if host == null:
		return
	var txt := str(outcome.get("text", ""))
	if txt.length() > 90:
		txt = txt.left(88) + "…"
	if txt != "":
		host._toast(txt)
	var gain := {}
	var items: Dictionary = outcome.get("effects", {}).get("items", {})
	for k in items.keys():
		if int(items[k]) > 0:
			gain[k] = int(items[k])
	if not gain.is_empty():
		host.fly_from_world(at + Vector3.UP, gain)


func card_open() -> bool:
	return false
