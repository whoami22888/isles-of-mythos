extends RefCounted

const TacticalManager = preload("res://scenes/tactical_manager.gd")


static func run(tree: SceneTree, check: Callable) -> void:
	# Pure grid math: 2.0 m steps, symmetric half-away rounding.
	check.call(TacticalManager.GRID_STEP == 2.0, "Tactical grid step must be exactly 2.0 m")
	check.call(TacticalManager.world_to_cell(Vector3(0.9, 0.0, -0.9)) == Vector2i(0, 0), "Points within 1 m of origin snap to cell (0, 0)")
	check.call(TacticalManager.world_to_cell(Vector3(1.0, 0.0, -1.0)) == Vector2i(1, -1), "Exact half steps round away from zero")
	check.call(TacticalManager.world_to_cell(Vector3(3.1, 5.0, 4.9)) == Vector2i(2, 2), "3.1/4.9 m snap to cell (2, 2)")
	var snapped := TacticalManager.snap_to_grid(Vector3(3.1, 1.25, -7.2))
	check.call(snapped.is_equal_approx(Vector3(4.0, 1.25, -8.0)), "snap_to_grid aligns XZ to 2.0 m and keeps Y")
	check.call(fmod(absf(snapped.x), 2.0) == 0.0 and fmod(absf(snapped.z), 2.0) == 0.0, "Snapped coordinates are multiples of 2.0 m")
	check.call(TacticalManager.cell_to_world(Vector2i(-3, 5), 0.5).is_equal_approx(Vector3(-6.0, 0.5, 10.0)), "cell_to_world returns the cell centre")

	var manager = TacticalManager.new()
	tree.root.add_child(manager)
	var requested: Array[Dictionary] = []
	var rejected: Array[String] = []
	manager.placement_requested.connect(func(kind: String, cell: Vector2i, pos: Vector3) -> void:
		requested.append({"kind": kind, "cell": cell, "pos": pos})
	)
	manager.placement_rejected.connect(func(reason: String, _cell: Vector2i) -> void:
		rejected.append(reason)
	)

	check.call(manager.request_placement_at_world(Vector3(2.0, 0.0, 2.0)) == TacticalManager.REJECT_INACTIVE, "Placement outside tactical mode is rejected")
	check.call(requested.is_empty(), "No intent is emitted while tactical mode is off")

	manager.set_tactical_mode(true)
	check.call(manager.active, "Tactical mode can be enabled")

	# Raycast from straight above onto the fallback plane (no physics collider in the smoke scene).
	var hit: Dictionary = manager.raycast_terrain_from(Vector3(3.3, 50.0, -2.7), Vector3.DOWN)
	check.call(bool(hit["hit"]), "Downward ray hits the island terrain plane")
	check.call((hit["position"] as Vector3).is_equal_approx(Vector3(3.3, 0.0, -2.7)), "Ray hit lands on y = terrain_plane_height")
	check.call(not bool(manager.raycast_terrain_from(Vector3(0.0, 50.0, 0.0), Vector3.UP)["hit"]), "Rays pointing away from the terrain miss")

	check.call(manager.request_placement_at_world(hit["position"], TacticalManager.KIND_CANNON_TOWER) == "", "A free cell accepts a cannon tower intent")
	check.call(requested.size() == 1, "Exactly one placement intent is emitted")
	check.call(requested[0]["cell"] == Vector2i(2, -1), "The tower snaps to the 2.0 m grid cell under the ray hit")
	check.call((requested[0]["pos"] as Vector3).is_equal_approx(Vector3(4.0, 0.0, -2.0)), "The intent carries the snapped world position")
	check.call(not manager.is_cell_occupied(Vector2i(2, -1)), "An intent alone must not mark the cell as built")
	check.call(manager.is_cell_pending(Vector2i(2, -1)), "The requested cell is held as pending")

	check.call(manager.request_placement_at_world(Vector3(4.4, 0.0, -1.6), TacticalManager.KIND_BALLISTA) == TacticalManager.REJECT_PENDING, "A second placement on a pending cell is refused")
	manager.apply_authoritative_structures([{"kind": TacticalManager.KIND_CANNON_TOWER, "cell": [2, -1]}, {"kind": TacticalManager.KIND_MYTHOS_TRAP, "x": -6.2, "z": 9.9}])
	check.call(manager.is_cell_occupied(Vector2i(2, -1)) and not manager.is_cell_pending(Vector2i(2, -1)), "The server snapshot confirms the pending tower")
	check.call(manager.is_cell_occupied(Vector2i(-3, 5)), "Server structures given in metres are mapped onto grid cells")
	check.call(manager.request_placement_at_world(Vector3(4.0, 0.0, -2.0), TacticalManager.KIND_BALLISTA) == TacticalManager.REJECT_OCCUPIED, "Duplicate placement on an occupied cell is refused")
	check.call(manager.request_placement_at_world(Vector3(-5.9, 0.0, 10.1), TacticalManager.KIND_CANNON_TOWER) == TacticalManager.REJECT_OCCUPIED, "A Mythos trap cell also blocks duplicates")
	check.call(manager.request_placement_at_world(Vector3(0.0, 0.0, 0.0), "siege_engine") == TacticalManager.REJECT_UNKNOWN_KIND, "Unknown structure kinds are refused")
	check.call(manager.request_placement_at_world(Vector3(1000.0, 0.0, 0.0)) == TacticalManager.REJECT_OUT_OF_BOUNDS, "Cells beyond the island radius are refused")
	check.call(requested.size() == 1, "Rejected placements never emit intents")
	check.call(rejected.size() >= 6, "Every refusal emits placement_rejected")

	manager.clear_pending(Vector2i(9, 9))
	check.call(manager.request_placement_at_world(Vector3(6.0, 0.0, 6.0), TacticalManager.KIND_BALLISTA) == "", "A ballista can be placed on another free cell")
	manager.clear_pending(Vector2i(3, 3))
	check.call(not manager.is_cell_pending(Vector2i(3, 3)), "clear_pending releases a refused placement")

	var cam := Camera3D.new()
	tree.root.add_child(cam)
	cam.position = Vector3(0.0, 40.0, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var screen_hit: Dictionary = manager.raycast_terrain(cam, Vector2(cam.get_viewport().get_visible_rect().size) * 0.5)
	check.call(bool(screen_hit["hit"]), "Screen-centre touch ray from a top-down camera hits the terrain plane")
	check.call((screen_hit["position"] as Vector3).distance_to(Vector3.ZERO) < 0.5, "Screen-centre ray lands under the camera")

	manager.set_tactical_mode(false)
	check.call(not manager.active, "Tactical mode can be disabled")
	cam.queue_free()
	manager.queue_free()
