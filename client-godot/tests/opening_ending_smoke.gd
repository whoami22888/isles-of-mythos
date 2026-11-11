extends SceneTree
## Both mast and hull endings write the path, reach washed_ashore, vary beach
## loot, and place Silas's cutlass.

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func wipe() -> void:
	for path in ["user://washed_ashore.cfg", "user://opening_battle.cfg"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func loot_amount(scene: Node, node_id: String, item_id: String) -> int:
	var node: Dictionary = scene._node_by_id(node_id)
	if node.is_empty():
		return 0
	var total := 0
	for stage in node.get("loot", []):
		if not (stage is Array):
			continue
		for entry in stage:
			if entry is Dictionary and str(entry.get("id", "")) == item_id:
				total += int(entry.get("amount", 0))
	return total

func run_branch(mast: bool) -> void:
	wipe()
	var packed = load("res://gameplay/opening_battle.tscn")
	check(packed != null, "opening battle scene loads")
	if packed == null:
		return
	var battle = packed.instantiate()
	root.add_child(battle)
	for _i in 6:
		await process_frame
	battle._chose_mast = mast
	var expected := "mast" if mast else "hull"
	check(battle.defeat_path() == expected, "battle reports %s, got %s" % [expected, battle.defeat_path()])
	battle._capture = false
	battle._finished = false
	battle._finish_opening()
	for _i in 8:
		await process_frame
	var ashore: Node = null
	for child in root.get_children():
		if child.has_method("apply_opening_outcome") and child.has_method("defeat_path"):
			ashore = child
			break
	check(ashore != null, "%s branch reaches washed_ashore" % expected)
	if ashore == null:
		if is_instance_valid(battle):
			battle.queue_free()
		return
	check(str(ashore.defeat_path()) == expected, "ashore stored %s, got %s" % [expected, ashore.defeat_path()])
	check(ashore.get_node_or_null("SilasCutlass") != null, "%s branch places Silas's cutlass" % expected)
	if mast:
		check(loot_amount(ashore, "hull", "planks") >= 6, "mast path has more planks, got %d" % loot_amount(ashore, "hull", "planks"))
		check(loot_amount(ashore, "rigging", "rope") >= 5, "mast path has more rope, got %d" % loot_amount(ashore, "rigging", "rope"))
		check(ashore.get_node_or_null("MastPlank0") != null, "mast path scatters extra planks")
		check(ashore.get_node_or_null("SinkCargo0") == null, "mast path does not add sink cargo")
	else:
		check(loot_amount(ashore, "cargo_cloth", "cloth") >= 4, "hull path has more cargo cloth, got %d" % loot_amount(ashore, "cargo_cloth", "cloth"))
		check(ashore.get_node_or_null("SinkCargo0") != null, "hull path scatters extra crates")
		check(ashore.get_node_or_null("MastPlank0") == null, "hull path does not add mast planks")
	var cfg := ConfigFile.new()
	check(cfg.load("user://opening_battle.cfg") == OK, "opening outcome was saved")
	check(str(cfg.get_value("opening", "defeat_path", "")) == expected, "save file records %s" % expected)
	ashore.queue_free()
	if is_instance_valid(battle):
		battle.queue_free()
	for _i in 4:
		await process_frame

func run() -> void:
	await run_branch(true)
	await run_branch(false)
	if failures == 0:
		print("Opening ending smoke: PASS")
		quit(0)
	else:
		print("Opening ending smoke: FAIL (%d)" % failures)
		quit(1)
