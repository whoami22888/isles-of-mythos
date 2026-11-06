extends SceneTree
## M-E2E-1 headless integration suite.
##
## Requires a running authoritative server, supplied by the environment:
##   IOM_E2E_HTTP_BASE  e.g. http://127.0.0.1:3000   (register / login routes)
##   IOM_E2E_WS_URL     e.g. ws://127.0.0.1:3000/ws  (authenticated socket)
##
## Exit codes: 0 = all checks passed, 1 = a check failed, 2 = NOT VERIFIED
## (endpoints absent). A missing server never counts as a pass.
##
## Production boots set application/config/internal_gameplay_handoff = true so
## login enters the gameplay world. This suite overrides that for the protocol
## checks unless --internal-gameplay-handoff is passed. The project default is
## asserted, not assumed.

const PROTOCOL_SCRIPT := preload("res://gameplay/vertical_slice_protocol.gd")
const WORLD_SCENE := "res://gameplay/vertical_slice.tscn"
const TIMEOUT_MSEC := 15000
const HANDOFF_SETTING := "application/config/internal_gameplay_handoff"

var failures := 0
var _http: HTTPRequest


func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("M-E2E-1: " + message)
		failures += 1


func _init() -> void:
	call_deferred("run")


# Polls until the predicate holds or the timeout elapses. Returns true on success.
func _wait_until(predicate: Callable, timeout_msec: int = TIMEOUT_MSEC) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		await process_frame
	return true


func _post_json(path: String, body: Dictionary) -> Array:
	var base := OS.get_environment("IOM_E2E_HTTP_BASE").rstrip("/")
	_http = HTTPRequest.new()
	root.add_child(_http)
	var error := _http.request(base + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		_http.queue_free()
		return [0, {}]
	var completed: Array = await _http.request_completed
	_http.queue_free()
	var parsed = JSON.parse_string((completed[3] as PackedByteArray).get_string_from_utf8())
	return [int(completed[1]), parsed if parsed is Dictionary else {}]


func run() -> void:
	var ws_url := OS.get_environment("IOM_E2E_WS_URL")
	var http_base := OS.get_environment("IOM_E2E_HTTP_BASE")
	if ws_url.is_empty() or http_base.is_empty():
		push_error("M-E2E-1 NOT VERIFIED: IOM_E2E_HTTP_BASE and IOM_E2E_WS_URL must point at a running server.")
		quit(2)
		return

	var handoff_override := "--internal-gameplay-handoff" in OS.get_cmdline_user_args()
	if not handoff_override:
		check(bool(ProjectSettings.get_setting(HANDOFF_SETTING, true)),
			"Production default must enter gameplay after login")
	ProjectSettings.set_setting(HANDOFF_SETTING, handoff_override)

	await _check_rejected_token(ws_url)
	var session := await _check_register_and_authenticate(ws_url, http_base)
	if not session.is_empty():
		await _check_authoritative_move(session)
		await _check_reconnect_restores_state(session, ws_url)
		await _check_clean_teardown(session)
		if handoff_override:
			await _check_scaffold_handoff(ws_url, session["token"])

	ProjectSettings.set_setting(HANDOFF_SETTING, false)
	print("M-E2E-1 integration: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


# A forged token must be refused: the server closes with 1008 and the client must
# report a rejection, never auth_ok, and never schedule a reconnect. The server's
# INVALID_TOKEN text is not asserted: Godot's WebSocketPeer drops a data frame that
# arrives in the same read as the close, so the client cannot rely on that text.
func _check_rejected_token(ws_url: String) -> void:
	var client = PROTOCOL_SCRIPT.new()
	root.add_child(client)
	var seen := {"rejected": false, "auth_ok": false, "reconnects": 0, "failure": ""}
	check(client.has_signal("auth_failed"), "Adapter must expose auth_failed(reason) for close 1008")
	client.auth_failed.connect(func(reason: String) -> void:
		seen["failure"] = reason)
	client.status_changed.connect(func(status: String) -> void:
		if status.contains("rejected the session"):
			seen["rejected"] = true)
	client.message_received.connect(func(message: Dictionary) -> void:
		if message.get("type") == "auth_ok":
			seen["auth_ok"] = true)
	client.reconnect_scheduled.connect(func(_attempt: int, _delay: float) -> void:
		seen["reconnects"] += 1)
	client.configure(ws_url, "forged.token.value")
	client.connect_to_server()
	var refused := await _wait_until(func() -> bool: return seen["rejected"])
	check(refused, "Forged token must be reported as a server rejection (close 1008)")
	check(not seen["auth_ok"], "Forged token must never receive auth_ok")
	check(seen["failure"] == "INVALID_TOKEN", "Close 1008 with invalid_token must map to auth_failed(\"INVALID_TOKEN\") (got \"%s\")" % seen["failure"])
	await create_timer(0.5).timeout
	check(seen["reconnects"] == 0, "Server rejection must not schedule a reconnect")
	client.queue_free()
	await process_frame


# Registers a fresh account over HTTP, then authenticates the socket with the
# issued token. Returns the session dictionary, or an empty one on failure.
func _check_register_and_authenticate(ws_url: String, _http_base: String) -> Dictionary:
	var stamp := str(Time.get_ticks_usec() % 1000000000)
	var username := "e2e_%s" % stamp
	var register := await _post_json("/auth/register", {
		"username": username,
		"email": "%s@example.test" % username,
		"password": "E2e-Integration-Passw0rd",
	})
	check(register[0] == 201, "Registration must return 201 (got %d)" % register[0])
	var body: Dictionary = register[1]
	var token := str(body.get("accessToken", ""))
	var user_id := str(body.get("user", {}).get("id", ""))
	check(not token.is_empty() and not user_id.is_empty(), "Registration must return an access token and user id")
	if token.is_empty() or user_id.is_empty():
		return {}

	var client = PROTOCOL_SCRIPT.new()
	root.add_child(client)
	var received := {"auth": {}, "state": {}, "errors": []}
	client.message_received.connect(func(message: Dictionary) -> void:
		var kind = message.get("type")
		if kind == "auth_ok":
			received["auth"] = message
		elif kind == "player_state":
			received["state"] = message.get("state", {})
		elif kind == "error":
			received["errors"].append(message.get("code"))
	)
	client.configure(ws_url, token)
	client.connect_to_server()
	var ready := await _wait_until(func() -> bool:
		return not received["auth"].is_empty() and not received["state"].is_empty())
	check(ready, "Authenticated socket must receive auth_ok and an initial player_state")
	if not ready:
		client.disconnect_from_server()
		client.queue_free()
		return {}

	check(str(received["auth"].get("userId", "")) == user_id,
		"auth_ok must carry the registered user id, not a client-supplied value")
	var state: Dictionary = received["state"]
	check(typeof(state.get("x")) in [TYPE_FLOAT, TYPE_INT] and typeof(state.get("y")) in [TYPE_FLOAT, TYPE_INT],
		"Server player_state must carry numeric x and y")
	check(client.is_authenticated(), "Protocol must report authenticated after auth_ok")
	return {"client": client, "received": received, "token": token, "user_id": user_id, "username": username}


# The client only sends intent. The server must move the player and report the
# new position in player_state; the client must not invent the position.
func _check_authoritative_move(session: Dictionary) -> void:
	var client = session["client"]
	var received: Dictionary = session["received"]
	var start_x := float(received["state"].get("x", 0.0))
	received["state"] = {}
	var sent: bool = client.request_move(1.0, 0.0)
	check(sent, "Move intent must be accepted for sending while authenticated")
	var moved := await _wait_until(func() -> bool:
		return not received["state"].is_empty() and float(received["state"].get("x", start_x)) != start_x)
	check(moved, "Server must report a changed player position after a move intent")
	check(received["errors"].is_empty(), "Session must receive no server errors (got %s)" % str(received["errors"]))


# Real-client reconnect: gather a resource, lose the socket without a deliberate close,
# let the adapter's own recovery path reconnect with a REFRESHED token (a second /auth/login),
# then require the server-restored position and inventory to equal what was recorded before
# the drop. The server-side counterpart (abrupt terminate, same-requestId replay after
# reconnect) lives in server/src/reconnect.integration.test.ts: the client generates its own
# random request ids, so an identical-id replay cannot be driven from here.
func _check_reconnect_restores_state(session: Dictionary, ws_url: String) -> void:
	var client = session["client"]
	var received: Dictionary = session["received"]
	var user_id: String = session["user_id"]
	var seen := {"chunks": [], "acks": [], "rejected": [], "reconnected": false, "attempts": 0}
	client.world_chunk_received.connect(func(_id: String, chunk: Dictionary) -> void:
		seen["chunks"].append(chunk))
	client.command_acknowledged.connect(func(_id: String, message: Dictionary) -> void:
		if message.get("type") == "resource_gathered":
			seen["acks"].append(message))
	client.server_rejected.connect(func(code: String) -> void:
		seen["rejected"].append(code))
	client.reconnected.connect(func() -> void:
		seen["reconnected"] = true)
	client.reconnect_scheduled.connect(func(_attempt: int, _delay: float) -> void:
		seen["attempts"] += 1)

	# Discover gatherable nodes in the 3x3 chunks around the current position, one request at a time.
	var here_x := float(received["state"].get("x", 0.0))
	var here_y := float(received["state"].get("y", 0.0))
	var cx := int(floor(here_x / 32.0))
	var cy := int(floor(here_y / 32.0))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var before: int = seen["chunks"].size()
			var request_id: String = client.request_world_chunk(cx + dx, cy + dy)
			check(not request_id.is_empty(), "Chunk request must be sent while authenticated")
			await _wait_until(func() -> bool: return seen["chunks"].size() > before)
	var target := {}
	var best := INF
	for chunk in seen["chunks"]:
		for node in chunk.get("resources", []):
			var d := Vector2(float(node["x"]), float(node["y"])).distance_to(Vector2(here_x, here_y))
			if d < best:
				best = d
				target = node
	check(not target.is_empty(), "World chunks must expose a gatherable resource node")
	if target.is_empty():
		return

	# Walk (intent only) until inside the server's 2.5 tile gather range.
	var target_pos := Vector2(float(target["x"]), float(target["y"]))
	for _i in range(300):
		var pos := Vector2(float(received["state"].get("x", 0.0)), float(received["state"].get("y", 0.0)))
		if pos.distance_to(target_pos) <= 2.0:
			break
		var dir := (target_pos - pos).normalized()
		client.request_move(dir.x, dir.y)
		await create_timer(0.07).timeout
	var gather_id: String = client.request_gather(str(target["id"]))
	check(not gather_id.is_empty(), "Gather request must be sent while authenticated")
	var gathered := await _wait_until(func() -> bool: return seen["acks"].size() > 0)
	check(gathered, "Server must acknowledge the gather (rejections: %s)" % str(seen["rejected"]))
	if not gathered:
		return
	var ack_state: Dictionary = seen["acks"][0].get("state", {})
	var inventory_before: Dictionary = ack_state.get("inventory", {})
	var x_before := float(ack_state.get("x", 0.0))
	var y_before := float(ack_state.get("y", 0.0))
	check(not inventory_before.is_empty(), "Gather ACK must carry the authoritative inventory")

	# Lose the connection (not disconnect_from_server): the adapter must treat it as a lost session.
	received["state"] = {}
	received["auth"] = {}
	client._socket.close(4001, "e2e_drop")
	var login := await _post_json("/auth/login", {"identifier": session["username"], "password": "E2e-Integration-Passw0rd"})
	check(login[0] == 200, "Re-login for a refreshed token must return 200 (got %d)" % login[0])
	var fresh_token := str(login[1].get("accessToken", ""))
	check(not fresh_token.is_empty(), "Re-login must return an access token")
	client.configure(ws_url, fresh_token)
	var back := await _wait_until(func() -> bool:
		return seen["reconnected"] and not received["state"].is_empty() and client.is_authenticated(), 20000)
	check(back, "Adapter must reconnect and re-authenticate after the drop")
	check(seen["attempts"] >= 1, "Adapter must schedule its own reconnect after an unplanned drop")
	if not back:
		return
	check(str(received["auth"].get("userId", "")) == user_id, "Reconnected auth_ok must be for the same user")
	var restored: Dictionary = received["state"]
	check(is_equal_approx(float(restored.get("x", NAN)), x_before) and is_equal_approx(float(restored.get("y", NAN)), y_before),
		"Position must be restored from the server after reconnect (got %s,%s want %s,%s)" % [restored.get("x"), restored.get("y"), x_before, y_before])
	check(restored.get("inventory", {}) == inventory_before,
		"Inventory must be restored from the server after reconnect (got %s want %s)" % [str(restored.get("inventory")), str(inventory_before)])

	# The node is depleted: a fresh gather after reconnect must be rejected and must not grant again.
	var acks_before: int = seen["acks"].size()
	var rejected_before: int = seen["rejected"].size()
	client.request_gather(str(target["id"]))
	var refused := await _wait_until(func() -> bool: return seen["rejected"].size() > rejected_before or seen["acks"].size() > acks_before)
	check(refused and seen["acks"].size() == acks_before, "A second gather of the depleted node must be rejected, never granted")


# Deliberate disconnect must close the socket, clear authentication, and must
# not schedule a reconnect.
func _check_clean_teardown(session: Dictionary) -> void:
	var client = session["client"]
	var reconnects := {"scheduled": 0, "disconnected": false}
	client.reconnect_scheduled.connect(func(_attempt: int, _delay: float) -> void:
		reconnects["scheduled"] += 1)
	# "Disconnected" is emitted only from _handle_closed, once the socket has reached CLOSED.
	client.status_changed.connect(func(status: String) -> void:
		if status == "Disconnected":
			reconnects["disconnected"] = true)
	client.disconnect_from_server()
	var closed := await _wait_until(func() -> bool: return reconnects["disconnected"])
	check(closed, "Deliberate disconnect must complete the socket close (status Disconnected)")
	check(not client.is_authenticated(), "Deliberate disconnect must clear authentication")
	await create_timer(0.5).timeout
	check(reconnects["scheduled"] == 0, "Deliberate disconnect must not schedule a reconnect")
	client.queue_free()
	await process_frame


# Only when the override is passed: the scaffold world must authenticate with the
# in-memory session handed off from the test, without rendering the JWT.
func _check_scaffold_handoff(ws_url: String, token: String) -> void:
	var world = load(WORLD_SCENE).instantiate()
	world.begin_authenticated_session(ws_url, token)
	root.add_child(world)
	var authenticated := await _wait_until(func() -> bool: return world._client.is_authenticated())
	check(authenticated, "Scaffold handoff must authenticate the gameplay client")
	check(world._client._token == token, "Scaffold handoff must use only the handed-off session")
	world.queue_free()
	await process_frame
