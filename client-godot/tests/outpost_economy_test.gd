extends SceneTree
## Headless: build a Lumber Mill, wait for production, collect. Also checks
## camp gating, save round-trip and the carried pet name.

const State := preload("res://gameplay/outpost/outpost_state.gd")
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	var s = State.new()
	check(s.load_data(), "data loads")
	s.welcome()
	var wood0 := int(s.inv["wood"])
	check(s.block_reason("forge") != "", "forge locked at camp L1: " + s.block_reason("forge"))
	check(s.objective().begins_with("Build the Lumber Mill"), "objective: " + s.objective())
	check(s.start("mill"), "mill started")
	check(int(s.inv["wood"]) == wood0 - 30, "mill cost paid")
	check(s.progress("mill") < 0.05, "scaffold starts low")
	for i in 31 * 30:
		s.tick(1.0 / 30.0)
	check(s.level_of("mill") == 1, "mill reaches L1 after its timer")
	for i in 60 * 30:
		s.tick(1.0 / 30.0)
	var ready: Dictionary = s.ready_amount("mill")
	check(int(ready.get("wood", 0)) >= 11, "mill produced ~12 wood/min: %s" % ready)
	var before := int(s.inv["wood"])
	var got: Dictionary = s.collect("mill")
	check(int(s.inv["wood"]) == before + int(got.get("wood", 0)) and int(got.get("wood", 0)) > 0, "collect adds wood %s" % got)
	check(s.ready_amount("mill").is_empty(), "stock emptied")
	check(s.block_reason("mill") != "" , "mill L2 gated by camp: " + s.block_reason("mill"))
	s.pet_name = "Brine"
	s.save()
	var s2 = State.new()
	s2.load_data()
	check(s2.load_save() and s2.level_of("mill") == 1 and s2.pet_name == "Brine", "save round-trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(s.save_path()))
	print("OUTPOST ECONOMY: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
