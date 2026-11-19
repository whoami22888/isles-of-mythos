extends SceneTree

## Regression tests for the four PR #193 review findings (all client-side
## intent/presentation; the server remains the only authority).
const Scene = preload("res://gameplay/vertical_slice.tscn")

class StubClient extends Node:
	var authed := true
	var chunk_requests: Array = []
	var moves: Array = []
	var gathers: Array = []
	var connects := 0
	func configure(_u: String, _t: String) -> void: pass
	func connect_to_server() -> void: connects += 1
	func is_authenticated() -> bool: return authed
	func request_world_chunk(x: int, y: int) -> String:
		chunk_requests.append(Vector2i(x, y))
		return "chunk-%d" % chunk_requests.size()
	func request_move(dx: float, dy: float) -> bool:
		moves.append(Vector2(dx, dy))
		return true
	func request_gather(id: String) -> String:
		gathers.append(id)
		return "gather-%d" % gathers.size()

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		push_error("review regression failed: " + label)
		failures += 1

func _make() -> Array:
	var world = Scene.instantiate()
	world.begin_authenticated_session("ws://127.0.0.1:9/ws", "test-session")
	root.add_child(world)
	await process_frame
	var stub := StubClient.new()
	world.add_child(stub)
	world._client = stub
	return [world, stub]

func run() -> void:
	# Finding 2: request the chunk that contains the authoritative player.
	var made = await _make()
	var world = made[0]
	var stub: StubClient = made[1]
	world._on_authenticated("u1")
	check(stub.chunk_requests.is_empty(), "no hard-coded origin chunk before the server reports a position")
	world._on_player_state({"x": 100.5, "y": -40.0})
	check(stub.chunk_requests == [Vector2i(3, -2)], "chunk derived from authoritative position (32-unit chunks), got %s" % [stub.chunk_requests])
	# Prompt 007 must be the active gameplay camera, not an isolated test-only node.
	var cam := world.get_node("Camera") as CameraZoomController
	check(cam != null, "gameplay scene attaches CameraZoomController")
	var coastal := world.get_node_or_null("CoastalWorld") as Node3D
	check(coastal != null, "gameplay scene mounts the coastal world")
	if coastal != null:
		var collision_body := coastal.get_node_or_null("CameraTerrainCollision") as StaticBody3D
		check(collision_body != null, "live coastal terrain has dedicated camera collision")
		if collision_body != null:
			check(collision_body.collision_layer == CameraZoomController.CAMERA_TERRAIN_COLLISION_LAYER, "coastal collision uses the dedicated camera layer")
			check(collision_body.collision_mask == 0, "camera terrain collision does not collide with gameplay bodies")
			var collision_shape := collision_body.get_node_or_null("CameraTerrainHeightmapShape") as CollisionShape3D
			check(collision_shape != null, "coastal camera collision has a CollisionShape3D")
			if collision_shape != null:
				var shape_resource: Shape3D = collision_shape.shape
				check(shape_resource != null, "coastal camera collision has a shape resource")
				if shape_resource != null:
					var shape_class := shape_resource.get_class()
					check(shape_class == "HeightMapShape3D", "coastal camera collision uses HeightMapShape3D (found " + shape_class + ")")
			await physics_frame
			await physics_frame
			var ray_from := coastal.to_global(Vector3(0.0, 100.0, 0.0))
			var ray_to := coastal.to_global(Vector3(0.0, -100.0, 0.0))
			var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to, CameraZoomController.CAMERA_TERRAIN_COLLISION_LAYER)
			var terrain_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
			check(not terrain_hit.is_empty(), "camera-layer raycast hits the live coastal terrain")
			if not terrain_hit.is_empty():
				var expected_local_y := float(coastal.call("_terrain_height", 0.0, 0.0))
				var expected_global_y := coastal.to_global(Vector3(0.0, expected_local_y, 0.0)).y
				var terrain_hit_position: Vector3 = terrain_hit["position"]
				check(absf(terrain_hit_position.y - expected_global_y) < 0.1, "camera collision matches the analytic coastal height")
	cam.terrain_collision_mask = 0
	world._follow_camera()
	check(cam.top_level, "camera transform is independent of the parent scene")
	var expected_focus: Vector3 = Vector3(world._player.x, world._player.y - world.PLAYER_HALF_HEIGHT, world._player.z) + world._camera_focus_offset
	check(cam.focus_point.is_equal_approx(expected_focus), "camera focus follows the authoritative player")
	check(absf(cam.global_position.distance_to(cam.focus_point) - cam.get_rendered_distance()) < 0.05, "camera orbit uses the controller's rendered distance")
	world._on_player_state({"x": 101.0, "y": -41.0})
	expected_focus = Vector3(world._player.x, world._player.y - world.PLAYER_HALF_HEIGHT, world._player.z) + world._camera_focus_offset
	check(cam.focus_point.is_equal_approx(expected_focus), "camera keeps following every authoritative player_state")

	# TouchControls owns the input event; the controller receives one routed gesture,
	# preventing the same right-side touch from orbiting and panning twice.
	var yaw_before_drag: float = cam.rotation.y
	var focus_before_drag: Vector3 = cam.focus_point
	world._touch.call("_on_press", 20, Vector2(900.0, 200.0), true)
	world._touch.call("_on_drag", 20, Vector2(910.0, 220.0))
	check(absf(wrapf(cam.rotation.y - (yaw_before_drag - 10.0 * world.CAMERA_ORBIT_RADIANS_PER_PIXEL), -PI, PI)) < 0.001, "single-finger drag rotates the active camera exactly once")
	check(not cam.focus_point.is_equal_approx(focus_before_drag), "vertical single-finger drag pans the active camera")
	world._touch.call("_on_press", 20, Vector2(910.0, 220.0), false)

	# A two-finger gesture changes zoom and pans by its midpoint; it is never a world tap.
	cam._set_zoom(0.5)
	var zoom_before_pinch: float = cam._zoom_fraction
	var focus_before_pinch: Vector3 = cam.focus_point
	var tap_count := [0]
	world._touch.connect("tapped", func(_position: Vector2) -> void: tap_count[0] += 1)
	world._touch.call("_on_press", 30, Vector2(900.0, 200.0), true)
	world._touch.call("_on_press", 31, Vector2(1100.0, 200.0), true)
	world._touch.call("_on_drag", 31, Vector2(1120.0, 220.0))
	check(cam._zoom_fraction < zoom_before_pinch, "two-finger spread zooms toward the action view")
	check(not cam.focus_point.is_equal_approx(focus_before_pinch), "two-finger midpoint movement pans the camera")
	world._touch.call("_on_press", 31, Vector2(1120.0, 220.0), false)
	world._touch.call("_on_press", 30, Vector2(900.0, 200.0), false)
	check(tap_count[0] == 0, "multi-touch camera gesture must not emit a world tap")
	var saved_pan_offset: Vector3 = world._camera_focus_offset
	world._on_player_state({"x": 102.0, "y": -42.0})
	expected_focus = Vector3(world._player.x, world._player.y - world.PLAYER_HALF_HEIGHT, world._player.z) + saved_pan_offset
	check(cam.focus_point.is_equal_approx(expected_focus), "camera pan offset persists while following new authoritative positions")

	# Losing focus mid-pinch must release both camera fingers and suppress stale taps.
	world._touch.call("_on_press", 40, Vector2(900.0, 200.0), true)
	world._touch.call("_on_press", 41, Vector2(1100.0, 200.0), true)
	check(world._touch.call("is_camera_active"), "camera touch state is active during a two-finger gesture")
	check(cam._routed_pinch_active, "second camera finger starts the routed pinch baseline")
	world._touch.call("reset")
	check(not cam._routed_pinch_active, "focus reset ends the routed pinch baseline")
	check(not world._touch.call("is_camera_active"), "focus reset clears all camera touches")
	check(not world._touch.get("_camera_multi_touch"), "focus reset clears multi-touch tap suppression state")

	cam._set_zoom(0.75)
	check(world._camera_mode_overlay.visible, "top-down transition shows the strategic overlay")
	cam._set_zoom(0.0)
	check(not world._camera_mode_overlay.visible, "returning to action mode hides the strategic overlay")
	world._on_player_state({"x": 101.0, "y": -41.0})
	check(stub.chunk_requests.size() == 1, "same chunk is not re-requested on every state")
	world._on_player_state({"x": 96.0, "y": -33.0})
	check(stub.chunk_requests.size() == 1, "chunk boundary: (96,-33) is still chunk (3,-2)")
	world._on_player_state({"x": 95.9, "y": -32.0})
	check(stub.chunk_requests.size() == 2 and stub.chunk_requests[1] == Vector2i(2, -1), "crossing a chunk boundary requests the new chunk, got %s" % [stub.chunk_requests])
	# Reconnect resets chunk knowledge.
	world._on_authenticated("u1")
	world._on_player_state({"x": 95.9, "y": -32.0})
	check(stub.chunk_requests.size() == 3, "re-authentication re-requests the player's chunk")

	# Routed pinch deltas must be measured from the gesture-start zoom, not
	# accumulated against a value already clamped at either zoom boundary.
	cam._set_zoom(0.0)
	world._touch.call("_on_press", 50, Vector2(900.0, 200.0), true)
	world._touch.call("_on_press", 51, Vector2(1000.0, 200.0), true)
	world._touch.call("_on_drag", 51, Vector2(1040.0, 200.0))
	world._touch.call("_on_drag", 50, Vector2(940.0, 200.0))
	check(absf(cam._zoom_fraction) < 0.001, "routed parallel pinch returns to its start zoom at the near limit")
	world._touch.call("_on_press", 51, Vector2(1040.0, 200.0), false)
	world._touch.call("_on_press", 50, Vector2(940.0, 200.0), false)
	check(not cam._routed_pinch_active, "routed pinch ends when a finger is released")

	cam._set_zoom(1.0)
	world._touch.call("_on_press", 52, Vector2(900.0, 200.0), true)
	world._touch.call("_on_press", 53, Vector2(1000.0, 200.0), true)
	world._touch.call("_on_drag", 53, Vector2(960.0, 200.0))
	world._touch.call("_on_drag", 52, Vector2(860.0, 200.0))
	check(absf(cam._zoom_fraction - 1.0) < 0.001, "routed parallel pinch returns to its start zoom at the far limit")
	world._touch.call("_on_press", 53, Vector2(960.0, 200.0), false)
	world._touch.call("_on_press", 52, Vector2(860.0, 200.0), false)

	# A stale snapshot for another chunk must not replace the current view.
	world._on_world_chunk("c", {"x": 2, "y": -1, "resources": [{"id": "wood:1", "x": 1, "y": 1}]})
	world._on_world_chunk("c", {"x": 9, "y": 9, "resources": []})
	check(world._markers.has("wood:1"), "snapshot for a different chunk is ignored")
	world.queue_free()
	await process_frame

	# Finding 1: a newly registered player at (0,0) must be able to reach a
	# resource ~9 units away using only the existing `move` intent.
	made = await _make()
	world = made[0]
	stub = made[1]
	world._on_player_state({"x": 0.0, "y": 0.0})
	world._on_world_chunk("c", {"x": 0, "y": 0, "resources": [{"id": "wood:9:1", "x": 9, "y": 1}]})
	world._gather_nearest()
	check(stub.gathers.is_empty(), "out-of-range gather is not sent (server would reject with RESOURCE_OUT_OF_RANGE)")
	world._approach_step()
	check(stub.moves.size() == 1 and stub.moves[0].x > 0.9 and stub.moves[0].y > 0.0, "approach sends a normalised move intent toward the resource, got %s" % [stub.moves])
	for i in 20:
		world._approach_step()
	# Server confirms a position within gather range.
	world._on_player_state({"x": 7.5, "y": 1.0})
	world._approach_step()
	check(stub.gathers == ["wood:9:1"], "gather intent sent once in range, got %s" % [stub.gathers])
	var before: int = stub.moves.size()
	world._approach_step()
	check(stub.moves.size() == before, "no further movement once in range")
	# Disconnect cancels the approach.
	world._on_player_state({"x": 0.0, "y": 0.0})
	world._gather_nearest()
	stub.authed = false
	world._approach_step()
	check(not world._approaching, "approach cancelled when the session is not authenticated")
	world.queue_free()
	await process_frame

	# Finding 3: depleted resources reappear after authoritative refresh.
	made = await _make()
	world = made[0]
	stub = made[1]
	world._on_player_state({"x": 5.0, "y": 5.0})
	var base: int = stub.chunk_requests.size()
	world._on_world_chunk("c", {"x": 0, "y": 0, "resources": [{"id": "wood:1", "x": 5, "y": 5}]})
	world._on_ack("g", {"type": "resource_gathered", "resourceId": "wood:1", "respawnsAt": "2026-10-28T00:01:00.000Z", "state": {}})
	check(not world._markers.has("wood:1"), "gathered marker removed locally")
	world._chunk_in_flight = ""
	world._process(world.CHUNK_REFRESH_SECONDS + 0.1)
	check(stub.chunk_requests.size() == base + 1 and stub.chunk_requests[-1] == Vector2i(0, 0), "bounded periodic refresh requests the current chunk")
	world._process(0.1)
	check(stub.chunk_requests.size() == base + 1, "refresh is rate bounded")
	world._on_world_chunk("c", {"x": 0, "y": 0, "resources": [{"id": "wood:1", "x": 5, "y": 5}]})
	check(world._markers.has("wood:1"), "respawned resource visible again after refresh")
	# A refresh already in flight is not duplicated.
	world._chunk_in_flight = "pending"
	var n: int = stub.chunk_requests.size()
	world._process(world.CHUNK_REFRESH_SECONDS + 0.1)
	check(stub.chunk_requests.size() == n, "no second refresh while one is in flight")
	# An unknown outcome releases the in-flight slot.
	world._on_outcome_unknown("pending")
	check(world._chunk_in_flight.is_empty(), "unknown outcome frees the in-flight chunk request")
	world.queue_free()
	await process_frame

	# Finding 4: reconnect remains available after the authenticated handoff.
	made = await _make()
	world = made[0]
	stub = made[1]
	var button: Button = world.get_node("Interface/Panel/Margin/Content/Connect")
	check(button.visible, "reconnect control stays visible after handoff")
	check(button.text.to_lower().contains("reconnect"), "control is labelled as reconnect")
	check(not world.get_node("Interface/Panel/Margin/Content/Token").visible, "JWT field stays hidden")
	check(world.get_node("Interface/Panel/Margin/Content/Token").text.is_empty(), "JWT is not rendered")
	button.pressed.emit()
	check(stub.connects == 1, "reconnect control reuses the in-memory session to reconnect")
	world.queue_free()
	await process_frame

	# A ground tap away from resources walks. A tap on a resource still gathers.
	made = await _make()
	world = made[0]
	stub = made[1]
	world._on_player_state({"x": 0.0, "y": 0.0})
	world._on_world_chunk("c", {"x": 0, "y": 0, "resources": [{"id": "wood:tap", "x": 8, "y": 0}]})
	check(world._intent_for_ground(3.0, 4.0) == "move", "empty ground is a free move")
	world._approach_step()
	check(stub.moves.size() == 1 and stub.gathers.is_empty(), "free move sends a move intent and does not gather")
	check(world._intent_for_ground(8.0, 0.0) == "gather", "a tap on a resource gathers")
	check(world._approaching, "an out-of-range resource tap walks to it first")
	world.queue_free()
	await process_frame

	# Run Prompt 007 in an isolated SceneTree process. This test file is the
	# existing IOM-00 regression entry point and is not owned by another active PR.
	var camera_test_output: Array[String] = []
	var camera_test_exit := OS.execute(
		OS.get_executable_path(),
		PackedStringArray([
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--script",
			"res://tests/camera_zoom_controller_regression.gd"
		]),
		camera_test_output,
		true
	)
	check(
		camera_test_exit == 0,
		"PROMPT_007 camera regression failed (exit %d): %s"
		% [camera_test_exit, "\n".join(camera_test_output)]
	)

	# A deliberately failing child proves that a failed assertion cannot leave
	# the SceneTree alive and block the parent OS.execute call.
	var failure_probe_output: Array[String] = []
	var failure_probe_exit := OS.execute(
		OS.get_executable_path(),
		PackedStringArray([
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--script",
			"res://tests/camera_zoom_controller_regression.gd",
			"--",
			"--force-failure"
		]),
		failure_probe_output,
		true
	)
	check(failure_probe_exit != 0, "camera child failure probe must return a nonzero exit code")
	check(
		"\n".join(failure_probe_output).contains("intentional failure probe"),
		"camera child failure probe must propagate its diagnostic"
	)
	print("Vertical slice review regression: %s failures" % failures)
	quit(1 if failures else 0)
