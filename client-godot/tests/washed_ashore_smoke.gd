extends SceneTree

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func wipe_save() -> void:
	if FileAccess.file_exists("user://washed_ashore.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://washed_ashore.cfg"))

func run() -> void:
	wipe_save()
	var boot := FileAccess.get_file_as_string("res://scripts/boot.gd")
	var launch := boot.split("func _launch_internal_gameplay")[1].split("func _opening_battle_done")[0]
	check("res://gameplay/ashore/washed_ashore.tscn" in launch, "Boot must hand off to the ashore scene")
	check("vertical_slice.tscn" not in launch, "Boot must not open the debug slice after login")
	var opening := FileAccess.get_file_as_string("res://gameplay/opening_battle.gd")
	var finish := opening.split("func _finish_opening")[1].split("func _on_skip")[0]
	check("res://gameplay/ashore/washed_ashore.tscn" in finish, "Opening battle must hand off to the ashore scene")
	check("vertical_slice.tscn" not in finish, "Opening battle must not load the debug slice")
	var packed = load("res://gameplay/ashore/washed_ashore.tscn")
	if packed == null:
		push_error("Ashore scene failed to load")
		quit(1)
		return
	var scene = packed.instantiate()
	if scene == null or not scene.has_method("begin_authenticated_session"):
		push_error("Ashore scene script failed to attach")
		if scene:
			scene.free()
		quit(1)
		return
	scene.begin_authenticated_session("ws://127.0.0.1:9/ws", "test-session", "refresh-secret")
	root.add_child(scene)
	await process_frame
	await process_frame
	check(scene.get_node_or_null("Interface/Panel") == null, "The debug panel must not exist")
	check(scene._client._url == "ws://127.0.0.1:9/ws", "Session origin is kept in memory")
	check(scene._client._token == "test-session", "Session token is kept in memory")
	check(scene._warmth < scene._hunger, "Cold starts more urgent than hunger")
	check(scene.offshore_warning() == "Too dangerous: sharks/storm", "Offshore lure carries the danger line")
	check(str(scene.get_node("LandmarkOffshore/Warning").text) == "Too dangerous: sharks/storm", "Offshore marker is visible in the world")
	for marker in ["LandmarkWreck", "LandmarkGrove", "LandmarkClearing", "LandmarkCamp", "LandmarkOffshore"]:
		check(scene.get_node_or_null(marker) != null, "Missing landmark " + marker)
	check(scene.get_node_or_null("LandmarkOffshore/Leviathan") != null, "Leviathan carcass stays offshore")
	check(scene.get_node_or_null("LandmarkOffshore/BrokenHull") != null, "Broken hull stays offshore")
	check(not scene.pet_can_fight(), "The pet cannot fight yet")
	check(scene.tame_window() >= 10.0 and scene.tame_window() <= 15.0, "Taming minigame lasts 10 to 15 seconds")
	var ids: Array = scene.research_ids()
	for required in ["foraging", "building", "fire", "cooking", "pet_training", "pet_defence", "fishing", "storage", "creature_riding"]:
		check(required in ids, "Research tree missing " + required)
	check(bool(scene._research_row("creature_riding").get("locked", false)), "Creature riding stays locked")
	check(bool(scene._research_row("pet_defence").get("locked", false)), "Pet defence stays locked")
	var glowed := false
	for mesh in scene.get_node("Nodes").find_children("*", "MeshInstance3D", true, false):
		var mat = mesh.material_override
		if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
			glowed = true
	check(not glowed, "Resource nodes must not use emissive glow")
	var tree_lock = scene.get_node_or_null("Nodes/tree_a/Lock")
	check(tree_lock != null and str(tree_lock.text) == "", "Trees are never tool-locked (the axe is a bonus)")
	var rock_lock = scene.get_node_or_null("Nodes/rock_a/Lock")
	check(rock_lock != null and str(rock_lock.text) == "", "Rocks are never tool-locked (the pick is a bonus)")
	for needed in ["wood", "stone", "fibre", "planks"]:
		check(scene._inv.has(needed), "Inventory tracks " + needed)
	check(scene.get_node_or_null("LandmarkClearing/Hut/Frame") != null, "Hut frame piece exists")
	check(scene.get_node_or_null("LandmarkClearing/Hut/Walls") != null, "Hut wall piece exists")
	check(scene.get_node_or_null("LandmarkClearing/Hut/Roof") != null, "Hut roof piece exists")
	scene.skip_cinematic()
	await process_frame
	check(scene.quest_line() == "Search the wreck  0/3", "Quest tracker says what to do with a counter, got '%s'" % scene.quest_line())
	check(scene.quest_line().length() <= 48, "Quest line stays one line")
	check(scene._heralds >= 1, "The pet or the pile heralds the next beat")
	var hull = scene._node_by_id("hull")
	scene._player.global_position = (hull["root"] as Node3D).global_position
	var before := int(scene._inv.get("planks", 0))
	scene.on_action()
	check(int(scene._inv.get("planks", 0)) == before, "First hull hit only cracks it (multi-hit gathering)")
	scene._gather_lock = 0.0
	scene.on_action()
	check(int(scene._inv.get("planks", 0)) > before, "Second hull hit breaks off planks")
	await build_and_pet_checks(scene)
	scene._fire_lit = false
	scene._dusk_active = true
	check(scene.creature_bold(), "No fire at dusk makes the creature bolder")
	scene._fire_lit = true
	check(not scene.creature_bold(), "A lit fire keeps dusk from turning bold")
	scene._fire_lit = false
	var hp_before: int = int(scene._creature_hp)
	scene._do_pet_alert()
	check(scene._hint == "Needs Pet Defence research and training", "Pet warns that defence is locked")
	check(scene._creature_hp == hp_before, "The alert does not damage the creature")
	scene._open_fork()
	check(scene._fork, "A weakened creature opens the choice")
	check(scene._try_begin_tame(), "Tame offers food")
	check(scene._tame_left >= 10.0 and scene._tame_left <= 15.0, "The feeding minigame uses the 12 second window")
	scene._fail_tame()
	check(not scene._fork and not scene._qte, "A failed tame returns to the fight")
	check(scene._creature_hp >= 4, "A failed tame lets the creature recover")
	check(scene._choice == "", "A failed tame does not record a choice")
	scene._open_fork()
	scene._try_begin_tame()
	scene._complete_tame(0.0)
	check(scene._choice == "tame", "A successful tame is saved as the choice")
	check(scene._rare, "A low roll is the rare colour")
	check(scene._gatherer, "The first tame gathers immediately")
	scene.skip_cinematic()
	check(scene._collect_ready, "The first idle bundle is ready to collect")
	scene._take_collect()
	check(scene._collect_taken, "One tap collects the bundle")
	check(scene._step == "night", "After the fight the storm night goes on until dawn")
	check(scene.quest_line().length() <= 48, "Night line stays one line")
	var sn = scene._storm_night
	var fuel_before: float = sn.fuel
	scene._inv["wood"] = 3
	scene._player.global_position = scene._pit_position() + Vector3(1.0, 0, 0)
	sn.fuel = 30.0
	check(sn.can_feed(), "A dying fire can be fed wood")
	scene.on_action()
	check(sn.fuel > 60.0 and int(scene._inv["wood"]) == 2, "Feeding the fire costs one wood and adds fuel")
	sn.fuel = 0.4
	sn.tick(1.0)
	check(not scene._fire_lit, "An unfed fire dies out")
	scene.on_action()
	check(scene._fire_lit, "Wood relights a dead fire")
	sn.age = sn.NIGHT_SECONDS + 1.0
	sn.tick(0.1)
	check(sn.dawn and scene._collect_ready, "Dawn arrives with a sea chest")
	scene._take_collect()
	check(scene._step == "climb", "The sea chest sends you up the ridge")
	check(scene.quest_line().length() <= 48, "Climb line stays one line")
	scene._player.global_position = scene._overlook.top()
	scene._tick_quest(0.1)
	check(scene._cinematic == "reveal", "Reaching the lookout plays the world reveal")
	scene.skip_cinematic()
	check(scene._step == "epilogue", "The reveal leads to the epilogue")
	check(scene.quest_line() == "Next: the survivor camp across the strait", "The next goal points across the strait")
	check(scene._end_open, "The end panel follows the tame path")
	var tame_lines := PackedStringArray(scene._end_lines())
	check(tame_lines.has("RARE!"), "Rare tame has a RARE moment")
	check(tame_lines.has("Creature Riding"), "Mount research stays a locked teaser")
	check(tame_lines.has("Too dangerous: sharks/storm"), "End panel points at the offshore lure")
	scene.queue_free()
	await process_frame
	wipe_save()
	var kill_scene = load("res://gameplay/ashore/washed_ashore.tscn").instantiate()
	kill_scene.begin_authenticated_session("ws://127.0.0.1:9/ws", "test-session")
	root.add_child(kill_scene)
	await process_frame
	kill_scene.skip_cinematic()
	kill_scene._open_fork()
	kill_scene.on_kill()
	check(kill_scene._cinematic == "kill", "Kill plays the finishing-blow cinematic")
	check(is_equal_approx(Engine.time_scale, 0.3), "The finishing blow is in slow motion")
	kill_scene.skip_cinematic()
	check(is_equal_approx(Engine.time_scale, 1.0), "Slow motion ends with the cinematic")
	check(kill_scene._choice == "kill", "Kill is stored in the local choice")
	check(not kill_scene._gatherer, "Killing does not grant a gatherer")
	check(int(kill_scene._inv.get("meat", 0)) >= 8, "The carcass yields a meat haul")
	check(kill_scene._hunger >= 99.0, "The carcass fills hunger")
	kill_scene.skip_cinematic()
	var kill_lines := PackedStringArray(kill_scene._end_lines())
	check(kill_lines.has("Next creature comes later."), "Kill path teases the next encounter")
	check(not kill_lines.has("RARE!"), "Kill path has no rare gatherer")
	kill_scene.queue_free()
	await process_frame
	wipe_save()
	print("Washed ashore smoke: %d failures" % failures)
	quit(1 if failures else 0)


func build_and_pet_checks(scene) -> void:
	# Gather goal advances on counts.
	scene._pet_freed = true
	scene._pet.visible = true
	scene._enter("gather")
	check(scene.quest_line().begins_with("Gather"), "Gather goal shows counts")
	scene._inv["wood"] = 14
	scene._inv["stone"] = 12
	scene._inv["fibre"] = 9
	scene._inv["planks"] = 9
	scene._inv["rope"] = 9
	scene._tick_quest(0.1)
	check(scene._step == "fire", "Enough wood and stone moves on to the campfire")
	# Build menu -> ghost -> place.
	scene.on_build_pick("campfire")
	check(scene._placing == "campfire" and scene._ghost != null, "Picking a recipe shows a placement ghost")
	var site: Vector3 = scene._build_spot()
	scene._ghost_pin = site
	scene._tick_ghost()
	check(scene._ghost_ok, "Ghost turns green on flat sand (%s)" % scene._ghost_why)
	var wood_before := int(scene._inv["wood"])
	scene.on_build_place()
	check(scene._fire_lit, "Placing the campfire lights it")
	check(int(scene._inv["wood"]) == wood_before - 4, "Campfire costs wood")
	check(scene._step == "cook", "Fire leads to catching and cooking fish")
	scene._inv["fish"] = 2
	scene._player.global_position = scene._pit_position() + Vector3(1.0, 0, 0)
	scene._cook()
	scene._cook()
	check(scene._fish_cooked == 2 and int(scene._inv.get("cooked", 0)) >= 2, "Two fish cooked at the fire")
	var bond_before := int(scene._pet_stats.get("bond", 0))
	scene._pet.global_position = scene._player.global_position + Vector3(0.8, 0, 0)
	scene.on_action()
	check(int(scene._pet_stats.get("bond", 0)) >= bond_before + 20, "Feeding Tide-Puck a cooked fish builds the bond")
	check(scene._bond_level() >= 2, "Bond Lv 2 unlocks Fetch")
	check(scene._step == "shelter" and scene._storm_left > 100.0, "Feeding leads to the lean-to with a storm timer")
	scene.on_build_pick("lean_to")
	scene._ghost_pin = scene._build_spot()
	scene._tick_ghost()
	scene.on_build_place()
	check(scene._building, "The lean-to goes up in stages")
	for i in 16:
		scene._tick_build(0.5)
	check(scene._shelter and scene._hut_stage == 3, "The lean-to finishes")
	check(scene._step == "storm" and scene._storm_night.is_night(), "Shelter before the storm leads to the storm night")
	# Wet ghost is rejected.
	check(scene._site_problem("campfire", Vector3(-6, scene._water_y - 0.5, -10)) != "", "Cannot build in the sea")
	# Cliffs: walking at the summit does not climb it.
	var p: Node3D = scene._player
	p.position = Vector3(-1.0, 0, 6.5)
	p.position.y = scene._ground_y(-1.0, 6.5)
	var start_y := p.position.y
	for i in 120:
		scene._slide(Vector3(-0.3, 0, 1).normalized(), 1.0 / 30.0, true)
	check(p.position.y < start_y + 1.5, "Cliff slopes over 40 degrees are walls (rose %.1f m)" % (p.position.y - start_y))
	# The pet sniffs out a dig spot and the player can dig it.
	scene._step = "gather"
	scene._pet_mode = "follow"
	p.position = Vector3(-10, 0, 4.5)
	p.position.y = scene._ground_y(-10, 4.5)
	scene._start_sniff()
	var dig: Dictionary = scene._nearest_dig()
	check(not dig.is_empty() and scene._pet_mode == "sniff", "The pet heads for a dig spot")
	if not dig.is_empty():
		var finds := int(scene._pet_finds)
		scene._gather_lock = 0.0
		scene._act_on_node(dig)
		check(int(scene._pet_finds) == finds + 1, "Digging the pointed spot counts as a pet find")
	var bond := int(scene._pet_stats["bond"])
	scene._pet_pet_cd = 0.0
	scene.on_pet()
	check(int(scene._pet_stats["bond"]) > bond, "Petting raises the bond")
	# Back to a fresh state for the dusk checks below.
	scene._dusk_active = false
	scene._step = "scavenge"
