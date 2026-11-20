extends SceneTree
## Outpost play-test bot: enters the outpost scene (as the epilogue hand-off
## does), builds a Lumber Mill through the HUD action, waits for production,
## collects, checks the fly-to-HUD, and reports. Clears saves first.
## IOM_BOT_SHOTS=/abs/dir writes stills (needs a renderer).

var scene: Node
var t := 0.0
var fails := 0

func say(s: String) -> void:
	print("[%6.1fs] %s" % [t, s])

func check(ok: bool, what: String) -> void:
	say(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame
		t += 1.0 / 30.0

func _init() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	var dir := OS.get_environment("IOM_BOT_SHOTS")
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await frames(3)
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	say("shot " + name)

## True when a raider's wind-up on the player is about to land.
func _incoming() -> bool:
	for u in scene.raid.units:
		if u["team"] == "enemy" and float(u["dead"]) < 0.0 and u["target"] is String and u["target"] == "player" and float(u["wind"]) > 0.0 and float(u["wind"]) < 0.3:
			return true
	return false

func run() -> void:
	for f in ["user://washed_ashore.cfg", "user://outpost.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	# Fake an ashore save so the carry-over path is exercised.
	var cfg := ConfigFile.new()
	cfg.set_value("ashore", "state", JSON.stringify({"step": "epilogue", "inv": {"wood": 7, "stone": 3, "fish": 2}, "pet": {"name": "Brine"}}))
	cfg.save("user://washed_ashore.cfg")
	scene = load("res://gameplay/outpost/outpost.tscn").instantiate()
	root.add_child(scene)
	await frames(5)
	var st = scene.state
	check(st.pet_name == "Brine", "pet name carried over")
	check(int(st.inv.get("wood", 0)) == 87 and int(st.inv.get("fish", 0)) == 2, "inventory carried + welcome stash %s" % st.inv)
	say("objective: " + st.objective())
	for id in scene._sites.keys():
		var p: Vector3 = scene._sites[id]["plot"]
		say("site %s at %s (water %.2f)" % [id, p, scene._water_y])
		check(p.y > scene._water_y + 0.1, "site %s on dry land" % id)
	scene.stand_at("mill")
	await frames(3)
	check(scene._focus == "mill", "player at mill plot, action '%s'" % scene._action_text())
	await shot("outpost_plots")
	scene._hud._action.emit_signal("pressed")
	await frames(2)
	check(st.is_building("mill"), "mill started via HUD action")
	await frames(15 * 30)
	await shot("outpost_mill_scaffold")
	var waited := 0
	while not (st.level_of("mill") == 1) and waited < 40 * 30:
		await frames(1)
		waited += 1
	check(st.level_of("mill") == 1, "mill built at t=%.1f" % t)
	scene.stand_at("dock")
	await frames(2)
	scene.on_action()
	scene.stand_at("palisade")
	await frames(2)
	scene.on_action()
	check(st.is_building("dock") and st.is_building("palisade"), "dock + palisade started")
	await frames(62 * 30)
	var ready: Dictionary = st.ready_amount("mill")
	check(int(ready.get("wood", 0)) >= 10, "mill stock %s" % ready)
	scene.stand_at("mill")
	await frames(2)
	check(scene._action_text() == "Collect", "action shows Collect")
	var before := int(st.inv["wood"])
	scene.on_action()
	await frames(1)
	check(scene._hud.flying() > 0, "loot flying to HUD")
	await frames(20)
	check(int(st.inv["wood"]) > before and scene._hud.flying() == 0, "wood collected %d -> %d" % [before, int(st.inv["wood"])])
	check(st.level_of("dock") == 1 and st.level_of("palisade") == 1, "dock + palisade built")
	say("objective: " + st.objective())
	# Strike a tree until it falls.
	var tree_i := -1
	for i in scene.gather.nodes.size():
		if scene.gather.kind_of(i) == "tree":
			tree_i = i
	var tp: Vector3 = scene.gather.nodes[tree_i]["pos"]
	scene._player.global_position = Vector3(tp.x, scene.ground_y(tp.x, tp.z + 1.8), tp.z + 1.8)
	await frames(2)
	check(scene._action_text() == "Chop", "action shows Chop near a tree ('%s')" % scene._action_text())
	var w0 := int(st.inv["wood"])
	for k in 4:
		scene.on_action()
		await frames(12)
	check(int(st.inv["wood"]) == w0 + 4 * 3 + 4, "tree felled for 16 wood (%d -> %d)" % [w0, int(st.inv["wood"])])
	check(float(scene.gather.nodes[tree_i]["left"]) > 0.0, "tree down, respawning")
	var rock_i := -1
	for i in scene.gather.nodes.size():
		if scene.gather.kind_of(i) == "rock":
			rock_i = i
			break
	var rp: Vector3 = scene.gather.nodes[rock_i]["pos"]
	scene._player.global_position = Vector3(rp.x, scene.ground_y(rp.x, rp.z - 1.6), rp.z - 1.6)
	await frames(2)
	var s0 := int(st.inv["stone"])
	scene.on_action()
	await frames(12)
	check(int(st.inv["stone"]) == s0 + 2, "rock struck for stone")
	# Milestone 2: survive raid wave 1 using the HUD action (Strike).
	# IOM_BOT_WAVE=3 / IOM_BOT_NODODGE=1 are balance probes (not CI gates).
	var probe_wave := int(OS.get_environment("IOM_BOT_WAVE")) if OS.get_environment("IOM_BOT_WAVE") != "" else 1
	var no_dodge := OS.get_environment("IOM_BOT_NODODGE") != ""
	scene.raid.wave = probe_wave - 1
	scene.raid.start_warning()
	var w := 0
	while scene.raid.phase != "fight" and w < 90 * 30:
		await frames(1)
		w += 1
	if probe_wave == 1:
		check(scene.raid.enemies_alive() == 4, "wave 1 landed (%d raiders) after %.0fs warning" % [scene.raid.enemies_alive(), w / 30.0])
	var deaths := 0
	var dodges := 0
	var hp_low := 999.0
	var was_alive := true
	var g := 0
	while scene.raid.enemies_alive() > 0 and g < 120 * 30:
		var u: Dictionary = scene.raid.nearest_enemy(scene._player.global_position, 999.0)
		if not u.is_empty():
			var at: Vector3 = u["node"].global_position
			var me: Vector3 = scene._player.global_position
			if me.distance_to(at) > 1.8:
				var np := me.move_toward(at, 4.6 / 30.0)
				np.y = scene.ground_y(np.x, np.z)
				scene._player.global_position = np
			elif not no_dodge and _incoming() and scene._dodge_t <= 0.0:
				# Read the telegraph: roll sideways out of the closing ring.
				scene.on_dodge()
				dodges += 1
			elif scene._action_text() == "Strike":
				scene._hud._action.emit_signal("pressed")
		if was_alive and not scene.player_alive():
			deaths += 1
			say("PROBE first death at %.1fs into the fight" % (g / 30.0)) if deaths == 1 else null
		was_alive = scene.player_alive()
		hp_low = minf(hp_low, scene.player_hp)
		if g == 45:
			await shot("raid_fight")
		await frames(1)
		g += 1
	check(scene.raid.enemies_alive() == 0, "wave 1 repelled in %.1fs, player HP %d (low %d), deaths %d, dodges %d, pet bites %d" % [g / 30.0, int(scene.player_hp), int(hp_low), deaths, dodges, scene.pet_bites])
	check(deaths == 0, "player survived wave 1")
	await frames(3)
	check(int(st.inv.get("gold", 0)) >= 5, "raid loot: gold %d iron %d" % [int(st.inv.get("gold", 0)), int(st.inv.get("iron", 0))])
	scene._cam_yaw = deg_to_rad(25.0)
	scene.stand_at("camp")
	await shot("outpost_built")
	print("OUTPOST BOT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
