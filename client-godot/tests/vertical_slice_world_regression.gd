extends SceneTree

const Scene = preload("res://gameplay/vertical_slice.tscn")

func _init() -> void:
	var world = Scene.instantiate()
	root.add_child(world)
	await process_frame
	world._on_world_chunk("chunk-1", {"resources": [{"id": "wood:1", "x": 1, "y": 2}]})
	await process_frame
	var first_marker = world._markers["wood:1"]
	var first_count: int = world._markers.size()
	world._on_world_chunk("chunk-2", {"resources": [{"id": "wood:1", "x": 3, "y": 4}]})
	await process_frame
	_assert(world._markers.size() == first_count, "repeated resource ID does not grow marker map")
	_assert(world._markers["wood:1"] == first_marker, "repeated resource ID reuses marker")
	world._on_world_chunk("chunk-3", {"resources": []})
	await process_frame
	_assert(world._markers.is_empty(), "authoritative deletion frees depleted markers")
	world.queue_free()
	await process_frame
	quit(0)

func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("world regression failed: " + label)
		quit(1)
