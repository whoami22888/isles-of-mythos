extends SceneTree
## Headless: tool tiers change hits + yield, durability breaks tools, gates
## (hardwood needs stone axe), crafting, skill raises crit chance, rare drops.

const State := preload("res://gameplay/outpost/outpost_state.gd")
const Tools := preload("res://gameplay/outpost/outpost_tools.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	call_deferred("run")


func _total(tl, row: Dictionary, n: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var sum := 0
	for i in n:
		var r: Dictionary = tl.roll(row, false, rng)
		for k in r["gain"].keys():
			if k == "wood":
				sum += int(r["gain"][k])
	return sum


func run() -> void:
	var st = State.new()
	st.load_data()
	var tl = Tools.new()
	tl.setup(st)
	var kinds: Dictionary = st.data["gather"]["kinds"]
	var tree: Dictionary = {"tool": "axe", "hits": 5, "yield": {"wood": 4}}
	check(tl.hits_needed(tree) == 8, "hands: 8 hits on a 5-hit tree (%d)" % tl.hits_needed(tree))
	var y_hands := _total(tl, tree, 50)
	check(tl.block(kinds["hardwood"]).begins_with("Needs a stone"), "hardwood needs a stone axe")
	check(tl.craft("stone_axe").begins_with("Need"), "stone axe needs flint")
	st.inv["wood"] = 100
	st.inv["stone"] = 100
	st.add_item("flint", 5)
	check(tl.craft("stone_axe") == "" and tl.tier("axe") == "stone", "stone axe crafted")
	check(tl.block(kinds["hardwood"]) == "", "hardwood workable with stone axe")
	check(tl.hits_needed(tree) == 5, "stone: 5 hits")
	tl.t["xp"] = 0
	var y_stone := _total(tl, tree, 50)
	check(tl.craft("iron_axe").begins_with("Needs a"), "iron axe needs a forge")
	st.buildings["forge"]["level"] = 1
	st.inv["iron"] = 50
	check(tl.craft("iron_axe") == "" and tl.tier("axe") == "iron", "iron axe crafted at the forge")
	check(tl.hits_needed(tree) == 3, "iron: 3 hits")
	tl.t["xp"] = 0
	var y_iron := _total(tl, tree, 50)
	check(y_hands < y_stone and y_stone < y_iron, "yield rises by tier: hands %d < stone %d < iron %d" % [y_hands, y_stone, y_iron])
	# Durability: iron axe breaks back to hands.
	tl.t["dur"]["axe"] = 2
	var rng := RandomNumberGenerator.new()
	tl.roll(tree, false, rng)
	var r: Dictionary = tl.roll(tree, false, rng)
	check(r["broke"] == "Iron axe" and tl.tier("axe") == "hands", "worn iron axe breaks (%s)" % r["broke"])
	# Skill.
	tl.t["xp"] = 0
	var c1: float = tl.crit_chance()
	tl.t["xp"] = 1200
	check(tl.skill_level() == 11 and tl.crit_chance() > c1 + 0.1, "skill L%d crit %.2f > %.2f" % [tl.skill_level(), tl.crit_chance(), c1])
	var crits := 0
	var pearls := 0
	rng.seed = 9
	for i in 2000:
		var rr: Dictionary = tl.roll(kinds["tide_pool"], false, rng)
		crits += 1 if rr["crit"] else 0
		pearls += int(rr["rare"].get("pearl", 0))
	check(crits > 200 and pearls > 50, "crits %d, pearls %d over 2000 tide-pool hits" % [crits, pearls])
	# Scene: node variety spawned and a hit lands with the tool system.
	var scene = load("res://gameplay/outpost/outpost.tscn").instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame
	var seen := {}
	for n in scene.gather.nodes:
		seen[n["kind"]] = true
	check(seen.size() >= 10, "%d node kinds in the outpost: %s" % [seen.size(), ", ".join(seen.keys())])
	var fi := -1
	for i in scene.gather.nodes.size():
		if scene.gather.nodes[i]["kind"] == "flint":
			fi = i
	var got: Dictionary = scene.gather.strike(fi)
	check(got.has("flint"), "striking flint yields flint %s" % str(got))
	scene.queue_free()
	await process_frame
	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
