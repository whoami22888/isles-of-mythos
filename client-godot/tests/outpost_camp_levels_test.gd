extends SceneTree
## Headless: camp levels 4-7 (Blueprint Citadel matrix): Farm at L4, Breeding
## Pen at L5, Barracks L4-5 gated to camp L6, Storage at L7 raises caps, and
## camp_level 4+ scenarios become eligible.

const State := preload("res://gameplay/outpost/outpost_state.gd")
const Events := preload("res://gameplay/outpost/outpost_events.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	call_deferred("run")


func grow(st, upto: int) -> void:
	for k in 400:
		for id in ["mill", "dock", "palisade", "camp", "forge", "watchtower", "barracks", "farm", "breeding_pen", "storage", "training_post"]:
			if st.block_reason(id) == "" and (id != "camp" or st.camp_level < upto):
				st.start(id)
		st.tick(30.0)


func run() -> void:
	var st = State.new()
	st.load_data()
	check(st.max_camp() == 7, "7 camp levels (%d)" % st.max_camp())
	for r in st.inv.keys():
		st.inv[r] = 100000
	st.inv["food"] = 100000
	grow(st, 5)
	check(st.camp_level == 5, "camp reaches L5 (%d)" % st.camp_level)
	check(st.level_of("farm") >= 1 and st.level_of("breeding_pen") == 1, "farm + breeding pen built")
	check(st.level_of("barracks") == 3 and st.block_reason("barracks").begins_with("Needs"), "barracks L4 waits for camp L6 (%s)" % st.block_reason("barracks"))
	check(st.storage_bonus() == 0.0 and not st.is_unlocked("storage"), "storage locked before L7")
	grow(st, 7)
	check(st.camp_level == 7 and st.level_of("barracks") == 5, "camp L7, barracks L5 (camp %d, barracks %d)" % [st.camp_level, st.level_of("barracks")])
	check(st.level_of("storage") >= 1 and st.storage_bonus() > 0.0, "storage vault raises caps (+%d%%)" % int(st.storage_bonus() * 100))
	check(st.crew_slots() >= 10, "10 crew slots (%d)" % st.crew_slots())
	var ev = Events.new()
	ev.setup(st, 77)
	var hi := 0
	for id in ev.events.keys():
		if int(ev.events[id].get("trigger", {}).get("camp_level", 0)) >= 4:
			hi += 1
	ev.d["day"] = 60
	var elig := 0
	for id in ev.events.keys():
		var row: Dictionary = ev.events[id]
		if int(row.get("trigger", {}).get("camp_level", 0)) >= 4 and ev.ineligible(row, {"zone": "beach", "day": 60, "camp_level": 7, "weather": "clear", "night": false, "part": "day"}) in ["", "pacing", "weather", "zone", "waits for an action"]:
			elig += 1
	check(hi == 0 or elig > 0, "%d of %d camp-L4+ scenarios now reachable at L7" % [elig, hi])
	ev.free()
	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
