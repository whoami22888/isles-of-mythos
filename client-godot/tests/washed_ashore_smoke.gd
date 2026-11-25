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
	check(tree_lock != null and str(tree_lock.text) == "Needs an axe", "Trees show the axe lock")
	var rock_lock = scene.get_node_or_null("Nodes/rock_a/Lock")
	check(rock_lock != null and str(rock_lock.text) == "Needs a pick", "Rocks show the pick lock")
	check(scene.get_node_or_null("LandmarkClearing/Hut/Frame") != null, "Hut frame piece exists")
	check(scene.get_node_or_null("LandmarkClearing/Hut/Walls") != null, "Hut wall piece exists")
	check(scene.get_node_or_null("LandmarkClearing/Hut/Roof") != null, "Hut roof piece exists")
	scene.skip_cinematic()
	await process_frame
	check(scene.quest_line() == "Wreck.", "Quest tracker is a single short line")
	check(scene.quest_line().length() < 24, "Quest line stays short")
	check(scene._heralds >= 1, "The pet or the pile heralds the next beat")
	var hull = scene._node_by_id("hull")
	scene._player.global_position = (hull["root"] as Node3D).global_position
	var before := int(scene._inv.get("planks", 0))
	scene.on_action()
	check(int(scene._inv.get("planks", 0)) > before, "Hull sections drop planks")
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
	check(scene.quest_line() == "Offshore.", "The next goal points offshore")
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
