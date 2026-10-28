extends SceneTree

# Manual end-to-end probe against a running server (NOT run in CI: it needs a live backend).
# Usage: IOM_WS_URL=ws://127.0.0.1:3000/ws godot --headless --path client-godot --script res://tests/live/live_playtest_probe.gd
# Drives the real boot-flow helpers: register, login, wrong-password rejection, WebSocket auth,
# the world screen with simulated touch on the joystick, and the server's authoritative position.

const Auth = preload("res://scripts/auth_client.gd")
const Adapter = preload("res://scripts/websocket_adapter.gd")
const WorldScene = preload("res://scenes/world.tscn")

var _failures := 0
var _http: HTTPRequest
var _positions: Array = []

func check(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		_failures += 1

func _init() -> void:
	call_deferred("run")

func _post(path: String, body: Dictionary) -> Array:
	var base := Auth.api_base_from_ws(OS.get_environment("IOM_WS_URL"))
	_http.request(base + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	var done: Array = await _http.request_completed
	return done  # [result, code, headers, body]

func run() -> void:
	_http = HTTPRequest.new()
	root.add_child(_http)
	var username := "probe_%d" % (Time.get_unix_time_from_system() as int % 100000000)
	var password := "Correct-Horse-Battery-9"
	var email := "%s@example.com" % username

	var reg: Array = await _post("/auth/register", Auth.build_request("register", username, email, password)["body"])
	check(reg[1] == 201, "register returns 201 (got %s)" % reg[1])
	var register_token := Auth.token_from_body(reg[3])
	check(not register_token.is_empty(), "register returns an access token")

	var login: Array = await _post("/auth/login", Auth.build_request("login", username, "", password)["body"])
	check(login[1] == 200, "login returns 200 (got %s)" % login[1])
	var token := Auth.token_from_body(login[3])
	check(not token.is_empty(), "login returns an access token")

	var bad: Array = await _post("/auth/login", Auth.build_request("login", username, "", "wrong-password-123")["body"])
	check(bad[1] == 401, "wrong password rejected with 401 (got %s)" % bad[1])
	check(Auth.message_for_result("login", bad[0], bad[1]) == "Invalid username or password", "401 shows the plain message")

	var adapter: Node = Adapter.new()
	root.add_child(adapter)
	var flags := {"authed": false}  # lambdas capture primitives by value; use a shared holder
	adapter.message_received.connect(func(message: Dictionary) -> void:
		if message.get("type", "") == "auth_ok":
			flags["authed"] = true
		if message.get("type", "") == "player_state":
			var state: Dictionary = message.get("state", {})
			_positions.append(Vector2(float(state.get("x", 0.0)), float(state.get("y", 0.0))))
	)
	adapter.configure(OS.get_environment("IOM_WS_URL"), token)
	adapter.connect_to_server()
	if await _wait_for(func() -> bool: return flags["authed"], 15.0):
		check(true, "WebSocket auth_ok received with the login token")
	else:
		check(false, "WebSocket auth_ok received within 15s")
		_finish()
		return
	await _wait_for(func() -> bool: return not _positions.is_empty(), 5.0)
	check(not _positions.is_empty(), "server sent an initial player_state")
	var start: Vector2 = _positions.back()

	var world: IslesWorldScreen = WorldScene.instantiate()
	root.add_child(world)
	world.size = Vector2(1280.0, 720.0)
	world.setup(adapter)
	var stick: IslesTouchJoystick = world.get_node("Joystick")
	var centre := stick.size * 0.5
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = centre
	stick._gui_input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = centre + Vector2(stick.size.x * 0.4, 0.0)
	stick._gui_input(drag)
	await _wait_for(func() -> bool: return _positions.back().x > start.x + 0.05, 8.0)
	var moved_to: Vector2 = _positions.back()
	check(moved_to.x > start.x + 0.05, "joystick drag right moves the authoritative x (start %.3f -> %.3f)" % [start.x, moved_to.x])

	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	stick._gui_input(release)
	await process_frame
	var stopped_at: Vector2 = _positions.back()
	await _wait_for(func() -> bool: return false, 0.6)
	check(_positions.back().distance_to(stopped_at) < 0.01, "no further movement after release")

	adapter.queue_free()
	world.queue_free()
	_finish()

func _wait_for(condition: Callable, seconds: float) -> bool:
	var elapsed := 0.0
	while elapsed < seconds:
		if condition.call():
			return true
		await create_timer(0.05).timeout
		elapsed += 0.05
	return condition.call()

func _finish() -> void:
	print("LIVE PROBE: %s failures" % _failures)
	quit(1 if _failures else 0)
