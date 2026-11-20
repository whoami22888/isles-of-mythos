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
	scene._cam_yaw = deg_to_rad(25.0)
	scene.stand_at("camp")
	await shot("outpost_built")
	print("OUTPOST BOT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
