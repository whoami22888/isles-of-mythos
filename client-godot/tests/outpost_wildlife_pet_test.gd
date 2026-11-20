extends SceneTree
## Headless: wildlife spawns by zone (max 8), a boar charge hurts the player,
## a monkey steals from the stash, kills drop loot; pet XP levels and unlocks
## commands; obedience; training post.

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	call_deferred("run")


func step(scene, n: int) -> void:
	for i in n:
		await process_frame


func run() -> void:
	Engine.max_fps = 30   # frame-count waits below assume ~30 fps deltas
	for f in ["user://washed_ashore.cfg", "user://outpost.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var scene = load("res://gameplay/outpost/outpost.tscn").instantiate()
	root.add_child(scene)
	await step(scene, 3)
	var wl = scene.wildlife
	wl.auto_spawn = false
	scene.events.paused = true
	# Zone spawning.
	var crab: Dictionary = wl.spawn_kind("crab")
	check(not crab.is_empty() and scene.zone_of(crab["node"].global_position) == "beach", "crab spawns on the beach")
	var snake: Dictionary = wl.spawn_kind("snake")
	check(not snake.is_empty() and scene.zone_of(snake["node"].global_position) == "jungle", "snake spawns in the jungle")
	for i in 10:
		wl.spawn_kind("goat")
	check(wl.alive().size() == 8, "capped at 8 animals (%d)" % wl.alive().size())
	for a in wl.alive():
		wl._despawn(a)
	await step(scene, 2)
	# Boar charge.
	scene.place_player(Vector3(12, 0, 12))
	var hp0: float = scene.player_hp
	var boar: Dictionary = wl.spawn_kind("boar", Vector3(12, 0, 16.5))
	var seen_charge := false
	for i in 30 * 6:
		await process_frame
		if boar["state"] == "charge":
			seen_charge = true
		if scene.player_hp < hp0:
			break
	check(seen_charge, "boar winds up and charges")
	check(scene.player_hp < hp0, "boar charge damages the player (%d -> %d)" % [int(hp0), int(scene.player_hp)])
	# Kill it: drops land as a sack, picked up on walking over.
	var meat0: int = scene.state.count("hide")
	var drops: Dictionary = {}
	for i in 10:
		drops = wl.hurt(boar, 30.0, scene._player.global_position)
		if not drops.is_empty():
			break
	check(drops.get("hide", 0) >= 1 and drops.size() >= 2, "boar drops hide + food %s" % str(drops))
	check(scene.pet_sys.drops.size() == 1, "drop sack on the ground")
	scene.place_player(scene.pet_sys.drops[0]["pos"], false)
	await step(scene, 2)
	check(scene.state.count("hide") == meat0 + int(drops.get("hide", 0)), "walked over the sack: hide collected")
	# Monkey thief.
	scene.state.inv["food"] = 50
	scene.place_player(Vector3(25, 0, 20), false)
	var mk: Dictionary = wl.spawn_kind("monkey", scene.site_pos("camp") + Vector3(-4, 0, 3))
	for i in 30 * 8:
		await process_frame
		if mk["carry"] != "":
			break
	check(mk["carry"] != "" and scene.state.count(mk["carry"]) < (50 if mk["carry"] == "food" else 9999), "monkey stole %s from the stash" % mk["carry"])
	# Pet XP & unlocks.
	var pet = scene.pet_sys
	check(pet.level() == 1 and not pet.unlocked("fetch"), "pup starts L1, fetch locked")
	check(pet.command("fetch").begins_with("Unlocks"), "locked command refused")
	pet.add_xp(int(pet.xp_table[1]))
	check(pet.level() == 2 and pet.unlocked("fetch") and not pet.unlocked("dig"), "%d XP -> L2, fetch unlocked" % int(pet.xp_table[1]))
	scene.events.apply({"pet_xp": int(pet.xp_table[3]) - pet.xp()})
	check(pet.level() == 4 and pet.unlocked("guard"), "event XP -> L4 guard (L%d)" % pet.level())
	pet.add_xp(50000)
	check(pet.level() == 10 and pet.unlocked("scout"), "caps at L10, scout unlocked")
	# Obedience follows trust/mood.
	pet.p["trust"] = 0
	pet.p["mood"] = 0
	var low: float = pet.obedience()
	pet.p["trust"] = 100
	pet.p["mood"] = 100
	check(low < 0.4 and pet.obedience() > 0.9, "obedience %.2f (neglected) vs %.2f (loved)" % [low, pet.obedience()])
	scene.state.inv["food"] = 20
	var t0: int = pet.trust()
	pet.p["trust"] = 50
	check(pet.feed() == "" and pet.trust() > 50, "feeding raises trust")
	check(pet.train() == "Build a Training Post", "training needs the post")
	scene.state.buildings["training_post"]["level"] = 1
	scene.stand_at("training_post")
	var x0: int = pet.xp()
	var why_t: String = pet.train()
	check(why_t == "" and pet.xp() >= x0 + 25, "training session +25 XP (%s)" % why_t)
	# Dig at a marked spot.
	await step(scene, 2)
	check(pet.dig_spots.size() == 3, "3 marked dig spots")
	scene._pet.global_position = pet.dig_spots[0]["pos"]
	var r := "ignored"
	for i in 5:
		r = pet.command("dig")
		if r != "ignored":
			break
	check(r == "" and pet.mode == "dig", "dig command runs")
	for i in 30 * 4:
		await process_frame
	check(pet.dig_spots.size() == 2, "spot dug")
	scene.queue_free()
	await process_frame
	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
