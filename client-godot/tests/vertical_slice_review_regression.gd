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
	# Codex P2 on d6accf5: the camera must follow the authoritative player, not stay on the origin.
	var cam: Camera3D = world.get_node("Camera")
	var cam_offset: Vector3 = cam.position - world._player
	check(cam_offset.is_equal_approx(Vector3(0, 27.1, 24)), "camera follows the authoritative player (offset from player), got %s" % [cam_offset])
	world._on_player_state({"x": 101.0, "y": -41.0})
	check((cam.position - world._player).is_equal_approx(Vector3(0, 27.1, 24)), "camera keeps following on every player_state")
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
	# A stale snapshot for another chunk must not replace the current view.
	world._on_world_chunk("c", {"x": 2, "y": -1, "resources": [{"id": "wood:1", "x": 1, "y": 1}]})
	world._on_world_chunk("c", {"x": 9, "y": 9, "resources": []})
	check(world._markers.has("wood:1"), "snapshot for a different chunk is ignored")
	# Mobile touch controller: pan survives subsequent server position updates.
	var initial_camera_position: Vector3 = cam.global_position
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = Vector2(700, 450)
	cam.call("_input", press)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(760, 450)
	drag.relative = Vector2(60, 0)
	cam.call("_input", drag)
	check(cam.global_position.distance_to(initial_camera_position) > 0.1, "single-finger gesture pans camera")
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = drag.position
	cam.call("_input", release)
	check(not cam.call("consume_tap", 0), "drag cannot count as gathering tap")
	var relative_before: Vector3 = cam.global_position - world._player
	world._on_player_state({"x": 97.0, "y": -35.0})
	check((cam.global_position - world._player).is_equal_approx(relative_before), "server updates preserve the camera's manual pan offset")

	# Pinch and twist are independent gestures; the player stays the anchor.
	press.position = Vector2(700, 450)
	cam.call("_input", press)
	var second := InputEventScreenTouch.new()
	second.index = 1
	second.pressed = true
	second.position = Vector2(800, 450)
	cam.call("_input", second)
	var height_before: float = cam.global_position.y
	drag.index = 1
	drag.position = Vector2(850, 450)
	drag.relative = Vector2(50, 0)
	cam.call("_input", drag)
	check(cam.global_position.y < height_before, "spreading fingers zooms camera in")
	var orbit_before: Vector3 = cam.global_position
	drag.position = Vector2(850, 500)
	drag.relative = Vector2(0, 50)
	cam.call("_input", drag)
	check(absf(cam.global_position.x - orbit_before.x) > 0.1 or absf(cam.global_position.z - orbit_before.z) > 0.1, "two-finger twist changes camera yaw")
	release.index = 1
	release.position = drag.position
	cam.call("_input", release)
	release.index = 0
	release.position = press.position
	cam.call("_input", release)
	check(not cam.call("consume_tap", 0), "multitouch release cannot trigger gathering")

	# Genuine stationary tap is registered once; touch over the GUI is ignored.
	press.index = 2
	press.position = Vector2(700, 450)
	cam.call("_input", press)
	release.index = 2
	release.position = press.position
	cam.call("_input", release)
	check(cam.call("consume_tap", 2), "single tap is accepted")
	check(not cam.call("consume_tap", 2), "single tap cannot be consumed twice")
	press.index = 3
	press.position = Vector2(30, 30)
	cam.call("_input", press)
	release.index = 3
	release.position = press.position
	cam.call("_input", release)
	check(not cam.call("consume_tap", 3), "touch on HUD cannot trigger a gather")
	var synthesized_mouse := InputEventMouseButton.new()
	synthesized_mouse.button_index = MOUSE_BUTTON_LEFT
	synthesized_mouse.pressed = true
	synthesized_mouse.device = InputEvent.DEVICE_ID_EMULATION
	world._unhandled_input(synthesized_mouse)
	check(not world._approaching, "emulated mouse press from touchscreen cannot gather")

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

	print("Vertical slice review regression: %s failures" % failures)
	quit(1 if failures else 0)
