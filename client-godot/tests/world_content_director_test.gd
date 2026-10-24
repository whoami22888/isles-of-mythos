extends SceneTree
## Standalone test: Godot 4.7.2 --headless --path client-godot
##  --script res://tests/world_content_director_test.gd
## Ensures the future populated world never renders missing/fake assets.

func _initialize() -> void:
	call_deferred("_test")

func _test() -> void:
	var script = load("res://scripts/world_content_director.gd")
	assert(script != null, "World visual director must import")
	var director: Node3D = script.new()
	root.add_child(director)
	assert(director.load_catalog(), "Content catalogue must validate")
	assert(director.candidate_count() >= 60, "Archetype content slots are missing")
	assert(director.scenario_count() >= 11, "Encounter shot library is missing")
	assert(director.available_visual_count() == 0,
		"No unverified placeholders or pending candidates can become runtime scenes")
	var snapshots := [{"id": "ship-01", "archetype": "galleon", "position": [1.0, 0.0, 3.0]},
		{"id": "monster-01", "archetype": "kraken", "position": [2.0, 0.0, 5.0]}]
	assert(director.plan_snapshot(snapshots, Vector3.ZERO).size() == 0,
		"No creature or ship may render before quality/provenance admission")
	assert(director.apply_visual_snapshot(snapshots, Vector3.ZERO) == 0,
		"Snapshot presentation must not invent creatures or substitute basic geometry")
	director.clear_visuals()
	director.queue_free()
	print("PASS world visual director: safe catalogue and no fake asset substitution")
	quit(0)
