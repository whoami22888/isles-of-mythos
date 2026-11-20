extends SceneTree
## Headless: the director has no choice card; scenarios spawn a physical thing
## in the world and choices resolve through verbs (interact / give / strike /
## pet / ignore).

const Events := preload("res://gameplay/outpost/outpost_events.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	call_deferred("run")


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _find(ev, verb: String, extra: Callable = Callable()) -> String:
	for id in ev.events.keys():
		var row: Dictionary = ev.events[id]
		for c in row.get("choices", []):
			if Events.verb_of(str(c.get("label", ""))) == verb and (not extra.is_valid() or extra.call(row, c)):
				return str(id)
	return ""


func _stand_at_event(scene) -> void:
	var p: Vector3 = scene.events.world_pos()
	scene.place_player(p + Vector3(1.2, 0, 0.6), false)
	await frames(2)


func run() -> void:
	Engine.max_fps = 30
	for f in ["user://washed_ashore.cfg", "user://outpost.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	# Keyword map.
	check(Events.verb_of("Attack the boar") == "strike", "attack -> strike")
	check(Events.verb_of("Trade two fish") == "give", "trade -> give")
	check(Events.verb_of("Search the wreck") == "interact", "search -> interact")
	check(Events.verb_of("Leave it be") == "ignore", "leave -> ignore")
	check(Events.verb_of("Let the pup sniff it out") == "pet", "pup -> pet command")
	check(Events.verb_of("Walk down to the shore") == "interact", "default -> interact")
	var scene = load("res://gameplay/outpost/outpost.tscn").instantiate()
	root.add_child(scene)
	await frames(4)
	var ev = scene.events
	ev.paused = true
	scene.wildlife.auto_spawn = false
	check(scene.find_child("EventCard", true, false) == null, "no event card UI exists")
	# Interact: the barrels on the tide line.
	ev.present("sample_driftwood")
	check(ev.world.has("node") and is_instance_valid(ev.world["node"]), "event spawned a world prop (%s)" % ev.world.get("kind", ""))
	check(str(ev.world.get("kind", "")) == "barrels", "driftwood wreck -> barrels prop")
	check(scene.zone_of(ev.world_pos()) == "beach", "spawned in its zone (beach)")
	await _stand_at_event(scene)
	var txt: String = scene._action_text()
	check(txt != "" and txt == ev.world_action(), "context button shows the verb (%s)" % txt)
	var inv0: int = 0
	for k in scene.state.inv.keys():
		inv0 += int(scene.state.inv[k])
	scene.on_action()
	await frames(2)
	check(ev.active.is_empty(), "interact resolved the event")
	check(ev.last_outcome.has("text"), "outcome recorded (%s)" % str(ev.last_outcome.get("text", "")).left(40))
	await frames(15)
	check(not ev.world.has("node"), "prop cleared after the outcome")
	# Give: an NPC wanting items.
	var gid := _find(ev, "give", func(_r, c): return c.get("requires", null) is Dictionary and not (c["requires"] as Dictionary).is_empty() and not (c["requires"] as Dictionary).has("pet_level") and not (c["requires"] as Dictionary).has("rep"))
	check(gid != "", "found a give scenario (%s)" % gid)
	if gid != "":
		ev.present(gid)
		var ch: Dictionary = ev._choice("give")
		var req: Dictionary = ch.get("requires", {})
		var items: Dictionary = req.get("items", {}).duplicate()
		for k in req.keys():
			if not (k in ["items", "pet_level", "rep", "unlock", "camp_level", "building", "morale", "crew"]):
				items[k] = req[k]
		for k in items.keys():
			scene.state.add_item(str(k), int(items[k]) + 2)
		scene.state.camp_level = maxi(scene.state.camp_level, int(req.get("camp_level", 0)))
		await _stand_at_event(scene)
		var gt: String = ev.world_action()
		check(gt.begins_with("Give"), "context button offers the trade (%s)" % gt)
		var before: Dictionary = scene.state.inv.duplicate()
		ev.world_act()
		var paid := true
		for k in items.keys():
			if scene.state.count(str(k)) > int(before.get(k, 0)) and int(items[k]) > 0:
				paid = paid and false
		check(ev.active.is_empty(), "give resolved the event")
	# Ignore: walk away / timeout.
	var iid := _find(ev, "ignore")
	ev.present(iid)
	var n0: int = ev.d["history"].size()
	ev.world["t"] = 0.5
	ev.paused = false
	ev._roll_t = 9999.0
	ev.tick(1.0)
	ev.paused = true
	check(ev.active.is_empty() and ev.d["history"].size() == n0 + 1, "timeout took the ignore branch (%s)" % iid)
	# Strike.
	var sid := _find(ev, "strike", func(_r, c): return c.get("requires", null) == null or (c["requires"] is Dictionary and (c["requires"] as Dictionary).is_empty()))
	ev.present(sid)
	await _stand_at_event(scene)
	check(not ev.world_strike().is_empty() or ev.active.is_empty(), "strike resolved %s" % sid)
	# Pet command.
	var pid := _find(ev, "pet", func(_r, c): return c.get("requires", null) == null or (c["requires"] is Dictionary and (c["requires"] as Dictionary).is_empty()))
	if pid != "":
		scene.pet_sys.add_xp(120)
		ev.present(pid)
		await _stand_at_event(scene)
		var r: String = scene.pet_sys.command("fetch")
		check(ev.active.is_empty(), "pet command resolved %s (%s)" % [pid, r])
	scene.queue_free()
	await frames(2)
	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
