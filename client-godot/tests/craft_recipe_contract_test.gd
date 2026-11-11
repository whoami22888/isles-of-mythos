extends SceneTree
## Client recipe rows must match server/src/recipe.ts (item ids and integer counts).

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func run() -> void:
	var panel_script := load("res://gameplay/craft_panel.gd") as GDScript
	var panel: Node = panel_script.new()
	root.add_child(panel)
	await process_frame
	var expected := {
		"tool.wooden-club": [["resource.wood", 8]],
		"tool.stone-axe": [["resource.wood", 6], ["resource.stone", 4]],
		"tool.stone-pickaxe": [["resource.wood", 6], ["resource.stone", 5]],
		"structure.campfire": [["resource.wood", 8], ["resource.stone", 4]],
		"structure.wooden-wall": [["resource.wood", 10]],
		"consumable.herb-bandage": [["resource.herb", 3]],
	}
	var server_path := ProjectSettings.globalize_path("res://") + "../server/src/recipe.ts"
	var server := FileAccess.get_file_as_string(server_path)
	check(not server.is_empty(), "can read server recipe catalogue")
	for recipe_id in expected:
		check(panel.row_text(recipe_id) != "", "client lists %s" % recipe_id)
		check(recipe_id in server, "server catalogue contains %s" % recipe_id)
		for pair in expected[recipe_id]:
			var item: String = pair[0]
			var qty: int = pair[1]
			check(item in server, "server mentions %s for %s" % [item, recipe_id])
			check(("quantity: %d" % qty) in server or ("quantity:%d" % qty) in server, "server quantity for an ingredient is %d (recipe %s)" % [qty, recipe_id])
	# 14 wood must satisfy the 8-wood club when the item id is resource.wood (integers only).
	panel.set_inventory({"resource.wood": 14, "resource.stone": 34})
	check(panel.inventory_count("resource.wood") == 14, "inventory stores integer wood")
	check(panel.row_text("tool.wooden-club") == "Wooden Club: wood 14/8", "club row shows 14/8, got '%s'" % panel.row_text("tool.wooden-club"))
	# A wrong key must not be displayed as resource.wood (the phone bug hypothesis).
	panel.set_inventory({"wood": 14})
	check(panel.inventory_count("resource.wood") == 0, "unprefixed 'wood' is not silently treated as resource.wood")
	panel.queue_free()
	if failures == 0:
		print("Craft recipe contract test: PASS")
		quit(0)
	else:
		print("Craft recipe contract test: FAIL (%d)" % failures)
		quit(1)
