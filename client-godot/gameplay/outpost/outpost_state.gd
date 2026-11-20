extends RefCounted
## Chapter 2 outpost economy (Milestone 1). Pure logic, no nodes, so it runs
## headless in tests. All numbers come from data/outpost.json.
##
## Milestone 2 hooks: building_done / camp_levelled signals, palisade_hp(),
## crew_slots(), warning_seconds(). Raids and crew are not built yet.

signal building_started(id: String, level: int)
signal building_done(id: String, level: int)
signal camp_levelled(level: int)
signal collected(id: String, kind: String, amount: int)

const DATA_PATH := "res://gameplay/outpost/data/outpost.json"

var data: Dictionary = {}
var inv: Dictionary = {}
var pet_name := "Tide-Puck"
var camp_level := 1
## id -> {"level": int (built level, 0 = none), "building": bool,
##        "left": float, "stock": {kind: float}}
var buildings: Dictionary = {}
var camp_building := false
var camp_left := 0.0
var welcomed := false
## Milestone 2: building HP (id -> float), damaged buildings stop producing.
var hp: Dictionary = {}
var waves_done := 0
var crew_queue: Array = []   # [{"kind": String, "left": float}]
var crew_ready: Array = []   # kinds trained and waiting to be fielded
var relics := 0
## Milestone 3: Silas rescue progress (see outpost_rescue.gd).
var rescue_phase := ""
var raft_left := -1.0
var silas_joined := false
var journal: Array = []   # [{title, text}]


func load_data(path: String = DATA_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("outpost: missing %s" % path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("outpost: bad json %s" % path)
		return false
	data = parsed
	for kind in data.get("resources", []):
		inv[str(kind)] = int(inv.get(str(kind), 0))
	for id in data.get("buildings", {}).keys():
		buildings[id] = {"level": 0, "building": false, "left": 0.0, "stock": {}}
	return true


## Carry the castaway's haul and pet name over from the washed-ashore save.
func carry_from_ashore() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(str(data.get("ashore_save", "user://washed_ashore.cfg"))) != OK:
		return
	var parsed = JSON.parse_string(str(cfg.get_value("ashore", "state", "{}")))
	if not (parsed is Dictionary):
		return
	var src: Dictionary = parsed.get("inv", {})
	for key in src.keys():
		inv[str(key)] = int(inv.get(str(key), 0)) + int(src[key])
	var pet: Dictionary = parsed.get("pet", {})
	if pet.has("name") and str(pet["name"]).strip_edges() != "":
		pet_name = str(pet["name"])


func welcome() -> void:
	if welcomed:
		return
	welcomed = true
	var stash: Dictionary = data.get("welcome_stash", {})
	for key in stash.keys():
		inv[str(key)] = int(inv.get(str(key), 0)) + int(stash[key])


func title(id: String) -> String:
	if id == "camp":
		return camp_title()
	return str(data.get("buildings", {}).get(id, {}).get("title", id))


func camp_title(level: int = -1) -> String:
	var rows: Array = data.get("camp", {}).get("levels", [])
	var lv := camp_level if level < 0 else level
	return str(rows[clampi(lv - 1, 0, rows.size() - 1)].get("title", "Camp"))


func max_camp() -> int:
	return (data.get("camp", {}).get("levels", []) as Array).size()


func level_of(id: String) -> int:
	return int(buildings.get(id, {}).get("level", 0))


func is_building(id: String) -> bool:
	if id == "camp":
		return camp_building
	return bool(buildings.get(id, {}).get("building", false))


func time_left(id: String) -> float:
	if id == "camp":
		return camp_left
	return float(buildings.get(id, {}).get("left", 0.0))


func level_row(id: String, level: int) -> Dictionary:
	if id == "camp":
		var crow: Array = data.get("camp", {}).get("levels", [])
		return crow[level - 1] if level >= 1 and level <= crow.size() else {}
	var rows: Array = data.get("buildings", {}).get(id, {}).get("levels", [])
	return rows[level - 1] if level >= 1 and level <= rows.size() else {}


func unlock_level(id: String) -> int:
	var rows: Array = data.get("camp", {}).get("levels", [])
	for row in rows:
		if id in row.get("unlocks", []):
			return int(row.get("level", 1))
	return 99


func is_unlocked(id: String) -> bool:
	return camp_level >= unlock_level(id)


## Next level the player could start (0 when maxed).
func next_level(id: String) -> int:
	if id == "camp":
		return camp_level + 1 if camp_level < max_camp() else 0
	var rows: Array = data.get("buildings", {}).get(id, {}).get("levels", [])
	var lv := level_of(id)
	return lv + 1 if lv < rows.size() else 0


func cost(id: String, level: int) -> Dictionary:
	return level_row(id, level).get("cost", {})


func affordable(c: Dictionary) -> bool:
	for key in c.keys():
		if int(inv.get(str(key), 0)) < int(c[key]):
			return false
	return true


## Why a building can't be started right now ("" when it can).
func block_reason(id: String) -> String:
	var nl := next_level(id)
	if nl == 0:
		return "Max level"
	if is_building(id):
		return "Building..."
	if id == "camp":
		var req: Dictionary = level_row("camp", nl).get("requires", {})
		for key in req.keys():
			if level_of(str(key)) < int(req[key]):
				return "Needs %s" % title(str(key))
	else:
		if not is_unlocked(id):
			return "Needs %s" % camp_title(unlock_level(id))
		# Upgrades can't outgrow the camp.
		if nl > camp_level:
			return "Needs %s" % camp_title(nl)
	if not affordable(cost(id, nl)):
		return "Need " + cost_text(missing(cost(id, nl)))
	return ""


func missing(c: Dictionary) -> Dictionary:
	var out := {}
	for key in c.keys():
		var short := int(c[key]) - int(inv.get(str(key), 0))
		if short > 0:
			out[key] = short
	return out


static func cost_text(c: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in c.keys():
		parts.append("%d %s" % [int(c[key]), str(key)])
	return ", ".join(parts) if parts.size() > 0 else "free"


func start(id: String) -> bool:
	if block_reason(id) != "":
		return false
	var nl := next_level(id)
	var c := cost(id, nl)
	for key in c.keys():
		inv[str(key)] = int(inv.get(str(key), 0)) - int(c[key])
	var secs := float(level_row(id, nl).get("seconds", 30))
	if id == "camp":
		camp_building = true
		camp_left = secs
	else:
		buildings[id]["building"] = true
		buildings[id]["left"] = secs
	building_started.emit(id, nl)
	return true


## Build progress 0..1 for the scaffold (1 when idle).
func progress(id: String) -> float:
	if not is_building(id):
		return 1.0
	var nl := next_level(id)
	var total := float(level_row(id, nl).get("seconds", 30))
	return clampf(1.0 - time_left(id) / maxf(total, 0.01), 0.0, 1.0)


func tick(delta: float) -> void:
	if camp_building:
		camp_left -= delta
		if camp_left <= 0.0:
			camp_building = false
			camp_left = 0.0
			camp_level += 1
			camp_levelled.emit(camp_level)
	tick_crew(delta)
	for id in buildings.keys():
		var b: Dictionary = buildings[id]
		if bool(b["building"]):
			b["left"] = float(b["left"]) - delta
			if float(b["left"]) <= 0.0:
				b["building"] = false
				b["left"] = 0.0
				b["level"] = int(b["level"]) + 1
				building_done.emit(id, int(b["level"]))
			continue
		_produce(id, b, delta)


func _produce(id: String, b: Dictionary, delta: float) -> void:
	var lv := int(b["level"])
	if lv <= 0 or is_damaged(id):
		return
	var row := level_row(id, lv)
	var makes: Dictionary = row.get("produces", {})
	if makes.is_empty():
		return
	var cap := float(row.get("cap", 50))
	var stock: Dictionary = b["stock"]
	var eats: Dictionary = row.get("consumes", {})
	for kind in makes.keys():
		var have := float(stock.get(kind, 0.0))
		if have >= cap:
			continue
		var add := float(makes[kind]) / 60.0 * delta
		# The forge burns stone from the stores as it smelts.
		var ok := true
		for raw in eats.keys():
			var need := float(eats[raw]) / 60.0 * delta
			if float(inv.get(str(raw), 0)) + float(b.get("debt_" + str(raw), 0.0)) < need:
				ok = false
		if not ok:
			continue
		for raw in eats.keys():
			var debt := float(b.get("debt_" + str(raw), 0.0)) - float(eats[raw]) / 60.0 * delta
			while debt <= -1.0:
				debt += 1.0
				inv[str(raw)] = int(inv.get(str(raw), 0)) - 1
			b["debt_" + str(raw)] = debt
		stock[kind] = minf(have + add, cap)


## Whole units waiting to be collected at a building.
func ready_amount(id: String) -> Dictionary:
	var out := {}
	var stock: Dictionary = buildings.get(id, {}).get("stock", {})
	for kind in stock.keys():
		var n := int(floor(float(stock[kind])))
		if n > 0:
			out[kind] = n
	return out


func collect(id: String) -> Dictionary:
	var got := ready_amount(id)
	var stock: Dictionary = buildings.get(id, {}).get("stock", {})
	for kind in got.keys():
		stock[kind] = float(stock[kind]) - int(got[kind])
		inv[str(kind)] = int(inv.get(str(kind), 0)) + int(got[kind])
		collected.emit(id, str(kind), int(got[kind]))
	return got


## The single next goal shown on the HUD.
func objective() -> String:
	var order := ["mill", "dock", "palisade", "forge", "watchtower", "barracks"]
	for id in order:
		if is_unlocked(id) and level_of(id) == 0:
			if is_building(id):
				return "%s rising  ·  %ds" % [title(id), int(ceil(time_left(id)))]
			var why := block_reason(id)
			return "Build the %s%s" % [title(id), "" if why == "" else "  ·  " + why]
	if camp_building:
		return "Raising the %s  ·  %ds" % [camp_title(camp_level + 1), int(ceil(camp_left))]
	if next_level("camp") > 0:
		var why2 := block_reason("camp")
		return "Upgrade the camp to %s%s" % [camp_title(camp_level + 1), "" if why2 == "" else "  ·  " + why2]
	return "The stockade stands. Watch the horizon for privateer sails."


# --- Milestone 2 hooks (read-only for now) ---------------------------------

func palisade_hp() -> int:
	var lv := level_of("palisade")
	return int(level_row("palisade", lv).get("hp", 0)) if lv > 0 else 0


func crew_slots() -> int:
	var lv := level_of("barracks")
	var extra := int(data.get("milestone3", {}).get("harpooner_slots", 2)) if silas_joined else 0
	return int(level_row("barracks", lv).get("crew_slots", 0)) + extra if lv > 0 else 0


func warning_seconds() -> float:
	var lv := level_of("watchtower")
	return float(level_row("watchtower", lv).get("warning_seconds", 0)) if lv > 0 else 0.0


# --- Milestone 2: HP, repair, crew ---------------------------------------

func m2() -> Dictionary:
	return data.get("milestone2", {})


func max_hp(id: String) -> float:
	if id == "palisade":
		return float(palisade_hp())
	var lv := camp_level if id == "camp" else level_of(id)
	if lv <= 0:
		return 0.0
	return float(m2().get("building_hp", {}).get(id, 200)) * (1.0 + 0.5 * (lv - 1))


func hp_of(id: String) -> float:
	return float(hp.get(id, max_hp(id)))


func damage(id: String, amount: float) -> void:
	hp[id] = maxf(hp_of(id) - amount, 0.0)


func is_damaged(id: String) -> bool:
	return max_hp(id) > 0.0 and hp_of(id) <= 0.0


func repair_cost(id: String) -> Dictionary:
	var lv := camp_level if id == "camp" else level_of(id)
	var frac := 1.0 - hp_of(id) / maxf(max_hp(id), 1.0)
	return {"wood": int(ceil(float(m2().get("repair_wood_per_level", 15)) * maxi(lv, 1) * frac))}


func needs_repair(id: String) -> bool:
	return max_hp(id) > 0.0 and hp_of(id) < max_hp(id) - 0.5


func repair(id: String) -> bool:
	if not needs_repair(id):
		return false
	var c := repair_cost(id)
	if not affordable(c):
		return false
	for key in c.keys():
		inv[str(key)] = int(inv.get(str(key), 0)) - int(c[key])
	hp.erase(id)
	return true


func train(kind: String) -> String:
	var row: Dictionary = m2().get("crew_train", {}).get(kind, {})
	if row.is_empty():
		return "Unknown crew"
	if str(row.get("requires", "")) == "silas" and not silas_joined:
		return "Rescue Silas first"
	if level_of("barracks") <= 0:
		return "Needs a Barracks"
	if crew_queue.size() + crew_ready.size() + fielded >= crew_slots():
		return "Barracks full (%d slots)" % crew_slots()
	var c: Dictionary = row.get("cost", {})
	if not affordable(c):
		return "Need " + cost_text(missing(c))
	for key in c.keys():
		inv[str(key)] = int(inv.get(str(key), 0)) - int(c[key])
	crew_queue.append({"kind": kind, "left": float(row.get("seconds", 20))})
	return ""


## Crew currently on the field (set by the raid director).
var fielded := 0


func tick_crew(delta: float) -> void:
	# Carry leftover time down the queue (long ticks finish several recruits).
	var budget := delta
	while not crew_queue.is_empty() and budget > 0.0:
		var head: Dictionary = crew_queue[0]
		var left := float(head["left"])
		if left > budget:
			head["left"] = left - budget
			return
		budget -= left
		crew_queue.pop_front()
		crew_ready.append(str(head["kind"]))


# --- Save -------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"inv": inv.duplicate(), "pet_name": pet_name, "camp_level": camp_level,
		"camp_building": camp_building, "camp_left": camp_left,
		"buildings": buildings.duplicate(true), "welcomed": welcomed,
		"hp": hp.duplicate(), "waves_done": waves_done, "crew_queue": crew_queue.duplicate(true),
		"crew_ready": crew_ready.duplicate(), "relics": relics,
		"rescue_phase": rescue_phase, "raft_left": raft_left, "silas_joined": silas_joined, "journal": journal.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	var src: Dictionary = d.get("inv", {})
	for key in src.keys():
		inv[str(key)] = int(src[key])
	pet_name = str(d.get("pet_name", pet_name))
	camp_level = int(d.get("camp_level", 1))
	camp_building = bool(d.get("camp_building", false))
	camp_left = float(d.get("camp_left", 0.0))
	welcomed = bool(d.get("welcomed", false))
	hp = (d.get("hp", {}) as Dictionary).duplicate()
	waves_done = int(d.get("waves_done", 0))
	crew_queue = (d.get("crew_queue", []) as Array).duplicate(true)
	crew_ready = (d.get("crew_ready", []) as Array).duplicate()
	relics = int(d.get("relics", 0))
	rescue_phase = str(d.get("rescue_phase", ""))
	raft_left = float(d.get("raft_left", -1.0))
	silas_joined = bool(d.get("silas_joined", false))
	journal = (d.get("journal", []) as Array).duplicate(true)
	var bs: Dictionary = d.get("buildings", {})
	for id in bs.keys():
		if buildings.has(id):
			var b: Dictionary = bs[id]
			buildings[id] = {"level": int(b.get("level", 0)), "building": bool(b.get("building", false)),
				"left": float(b.get("left", 0.0)), "stock": (b.get("stock", {}) as Dictionary).duplicate()}


func save_path() -> String:
	return str(data.get("save_path", "user://outpost.cfg"))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("outpost", "state", JSON.stringify(to_dict()))
	cfg.save(save_path())


func has_save() -> bool:
	return FileAccess.file_exists(save_path())


func load_save() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(save_path()) != OK:
		return false
	var parsed = JSON.parse_string(str(cfg.get_value("outpost", "state", "{}")))
	if not (parsed is Dictionary):
		return false
	from_dict(parsed)
	return true
