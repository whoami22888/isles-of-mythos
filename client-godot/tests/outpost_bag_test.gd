extends SceneTree
## Headless: Bag lists every held item (not just the 3-chip tray), sorted
## resources first, with names from items.json and a colour chip each.

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	call_deferred("run")


func run() -> void:
	for f in ["user://washed_ashore.cfg", "user://outpost.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var scene = load("res://gameplay/outpost/outpost.tscn").instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame
	var st = scene.state
	for k in ["pearl", "map_fragment", "relic_shard", "hide", "rope", "fibre"]:
		st.add_item(k, 2)
	scene.bag.toggle()
	await process_frame
	var rows: Array = scene.bag.rows()
	var ids := rows.map(func(r): return r["id"])
	check(ids.has("pearl") and ids.has("relic_shard") and ids.has("rope"), "bag shows loot items (%d kinds)" % rows.size())
	check(ids[0] == "wood", "resources first (%s)" % ids[0])
	check(scene.bag._grid.get_child_count() == rows.size(), "one cell per item")
	check(scene.bag.item_name("relic_shard") == "Relic Shard", "names from items.json")
	check(scene.bag.chip_color("pearl") != scene.bag.chip_color("flint"), "distinct chips")
	scene.queue_free()
	await process_frame
	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
