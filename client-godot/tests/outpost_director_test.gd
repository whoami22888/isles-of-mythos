extends SceneTree
## Headless: event director determinism (fixed seed), eligibility, outcome
## application, chained events, and an action-triggered raid in the scene.

const State := preload("res://gameplay/outpost/outpost_state.gd")
const Events := preload("res://gameplay/outpost/outpost_events.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	call_deferred("run")


func _director(seed_v: int) -> Node:
	var st = State.new()
	st.load_data()
	st.camp_level = 2
	var ev = Events.new()
	ev.setup(st, seed_v)
	root.add_child(ev)
	ev.set_process(false)
	return ev


func _trace(ev) -> Array:
	var out: Array = []
	for i in 400:
		ev.tick(5.0)
		if not ev.active.is_empty():
			var id := str(ev.active["id"])
			var n: int = ev.active["choices"].size()
			var pick := 0
			for c in n:
				if ev.choice_block(ev.active["choices"][c]) == "":
					pick = c
					break
			var o: Dictionary = ev.choose(pick)
			if o.is_empty():
				ev.active = {}
			out.append(id + ":" + str(o.get("text", "")).left(12))
	return out


func run() -> void:
	Engine.max_fps = 30   # frame-count waits below assume ~30 fps deltas
	for f in ["user://washed_ashore.cfg", "user://outpost.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var a = _director(12345)
	check(a.events.size() >= 10, "scenarios loaded (%d from %s)" % [a.events.size(), ", ".join(a.files_loaded)])
	var ta := _trace(a)
	var b = _director(12345)
	var tb := _trace(b)
	check(ta.size() >= 5, "director fired %d events over 2000 s" % ta.size())
	check(ta == tb, "same seed -> identical event run")
	var c = _director(999)
	var tc := _trace(c)
	check(ta != tc, "different seed -> different run")
	check(a.day() >= 4, "clock advanced to day %d" % a.day())
	# Weather changed at least once in that time.
	print("  trace: ", ta.slice(0, 8))
	# Eligibility: rain-only event blocked in clear weather.
	var e = _director(7)
	e.set_weather("clear")
	var row: Dictionary = e.events["sample_rain_catch"]
	check(e.ineligible(row, e.context()) == "weather", "rain event blocked when clear")
	e.set_weather("rain")
	var why: String = e.ineligible(row, e.context())
	check(why == "" or why == "pacing" or why == "zone", "rain event eligible in rain (%s)" % why)
	# Requirements grey out choices.
	var ransom: Dictionary = e.events["raid_ransom"]
	e.st.inv["gold"] = 0
	check(e.choice_block(ransom["choices"][0]).begins_with("Needs"), "pay-ransom greyed without gold")
	e.st.inv["gold"] = 80
	check(e.choice_block(ransom["choices"][0]) == "", "pay-ransom allowed with gold")
	# Outcome application.
	var wood0: int = e.st.count("wood")
	var xp := [0]
	e.pet_xp_gained.connect(func(n): xp[0] += n)
	var spawned: Array = []
	e.spawn_requested.connect(func(w): spawned.append(w))
	e.apply({"items": {"wood": 7, "pearl": 1}, "morale": -10, "rep": {"utc": -15, "free": 4}, "pet_xp": 9, "unlock": "map_cove", "next_event": "raid_frontal_warned", "spawn": "boar"})
	check(e.st.count("wood") == wood0 + 7 and e.st.count("pearl") == 1, "items applied")
	check(e.morale() == 50 and e.rep("utc") == -15 and e.rep("free") == 4, "morale and rep applied")
	check(xp[0] == 9, "pet xp emitted")
	check(e.has_unlock("map_cove"), "unlock recorded")
	check(spawned == ["boar"], "spawn emitted")
	for k in 3:
		e.tick(5.0)
	check(not e.active.is_empty() and str(e.active["id"]) == "raid_frontal_warned", "chained next_event opened")
	# Saved seed restores the same RNG stream.
	var s1 = State.new()
	s1.load_data()
	var f1 = Events.new()
	f1.setup(s1, 4242)
	f1.rng.randf()
	f1.save_state()
	var expect: float = f1.rng.randf()
	var s2 = State.new()
	s2.load_data()
	s2.from_dict(s1.to_dict())
	s2.ext["director"]["rng_state"] = s1.ext["director"]["rng_state"]
	var f2 = Events.new()
	f2.setup(s2)
	check(is_equal_approx(f2.rng.randf(), expect) and int(f2.d["seed"]) == 4242, "seed + rng state survive save/load")
	f1.free()
	f2.free()
	# Scene: night with no watchtower -> director raid (action trigger), not a timer.
	var scene = load("res://gameplay/outpost/outpost.tscn").instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame
	var st = scene.state
	st.camp_level = 2
	scene.events.d["phase"] = "quiet"
	scene.raid._armed = true
	for i in 30:
		scene.raid._process(10.0)
	check(scene.raid.phase == "idle", "no fixed-timer raid after 300 s")
	var fired := ""
	for i in 40:
		scene.events.active = {}
		fired = scene.events.notify("night_no_watchtower")
		if fired != "":
			break
		scene.events.d["cooldowns"] = {}
	check(fired == "raid_night_sneak", "unwatched night -> night sneak raid card (%s)" % fired)
	scene.events.choose(0)
	check(scene.raid.phase == "warning" and scene.raid.raid_kind == "night_sneak", "choice launched the night raid (%s/%s)" % [scene.raid.phase, scene.raid.raid_kind])
	var w := 0
	while scene.raid.phase != "fight" and w < 30 * 20:
		await process_frame
		w += 1
	check(scene.raid.enemies_alive() == 3, "3 night raiders ashore (%d)" % scene.raid.enemies_alive())
	scene.queue_free()
	await process_frame
	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
