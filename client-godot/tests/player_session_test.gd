extends SceneTree

## Authenticated movement loop: deterministic cadence/contract checks plus a
## real loopback WebSocket round trip through the boot scene.

const Session = preload("res://scripts/player_session.gd")
const Joystick = preload("res://scripts/virtual_joystick.gd")
var _failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

func _init() -> void:
	call_deferred("run")

func run() -> void:
	_test_cadence_and_contract()
	_test_state_validation_and_smoothing()
	_test_joystick_release()
	await _test_boot_round_trip()
	print("Player session checks: %s failures" % _failures)
	quit(1 if _failures else 0)

func _test_cadence_and_contract() -> void:
	var sent: Array = []
	var session = Session.new()
	root.add_child(session)
	session.set_process(false)
	session.bind_sender(func(m: Dictionary) -> bool: sent.append(m); return true)
	session.set_move_intent(Vector2(1, 1))
	for i in 20:
		session.step(0.05)
	check(sent.is_empty(), "No movement may be sent before the server confirms player state")
	session.apply_message({"type": "player_state", "state": {"x": 10, "y": 5, "health": 100}})
	for i in 20:  # one second at 50 ms frames
		session.step(0.05)
	check(sent.size() == 20, "Moving input must be sent at exactly 20 Hz, got %s" % sent.size())
	for i in sent.size():
		var m: Dictionary = sent[i]
		check(m.type == "move" and m.sequence == i + 1, "Sequences must be strictly increasing from 1")
		check(absf(m.dx) <= 1.0 and absf(m.dy) <= 1.0, "dx/dy must respect the server bound")
		check(Vector2(m.dx, m.dy).length() <= 1.0001, "Diagonal input must not exceed unit speed")
	sent.clear()
	for i in 200:  # 240 Hz render frames must not raise packet rate
		session.step(1.0 / 240.0)
	check(sent.size() <= 18, "High frame rates must not exceed 20 Hz, got %s" % sent.size())
	sent.clear()
	session.set_move_intent(Vector2.ZERO)
	for i in 40:
		session.step(0.05)
	check(sent.size() == 1 and sent[0].dx == 0.0 and sent[0].dy == 0.0, "Release must send exactly one stop frame")
	sent.clear()
	session.step(5.0)
	session.set_move_intent(Vector2(0.05, 0))
	session.step(0.05)
	check(sent.is_empty(), "Deadzone input must not produce traffic")
	session.set_move_intent(Vector2(INF, 0))
	session.step(0.05)
	check(sent.is_empty(), "Non-finite input must be discarded")
	var failing = Session.new()
	root.add_child(failing)
	failing.bind_sender(func(_m: Dictionary) -> bool: return false)
	failing.apply_message({"type": "player_state", "state": {"x": 0, "y": 0}})
	failing.set_move_intent(Vector2.RIGHT)
	failing.step(0.05)
	check(failing.sequence() == 0, "Unsent frames must not consume sequence numbers")
	failing.queue_free()
	session.queue_free()

func _test_state_validation_and_smoothing() -> void:
	var session = Session.new()
	root.add_child(session)
	session.set_process(false)
	var errors: Array = []
	session.server_error.connect(func(c: String) -> void: errors.append(c))
	session.apply_message({"type": "player_state", "state": {"x": "bad", "y": 1}})
	check(not session.has_state(), "Malformed positions must be ignored")
	session.apply_message({"type": "player_state", "state": {"x": 1.0, "y": 1.0}})
	check(session.display_position() == Vector2(1, 1), "First state must place the player exactly")
	session.apply_message({"type": "player_state", "state": {"x": 2.0, "y": 1.0}})
	session.step(0.016)
	var d: Vector2 = session.display_position()
	check(d.x > 1.0 and d.x < 2.0, "Small corrections must be smoothed, got %s" % d)
	for i in 30:
		session.step(0.016)
	check(session.display_position().distance_to(Vector2(2, 1)) < 0.01, "Display must converge on authority")
	session.apply_message({"type": "player_state", "state": {"x": 50.0, "y": 1.0}})
	check(session.display_position() == Vector2(50, 1), "Large server corrections must snap")
	session.apply_message({"type": "error", "code": "PLAYER_STUNNED"})
	check(errors == ["PLAYER_STUNNED"], "Server errors must surface")
	session.queue_free()

func _test_joystick_release() -> void:
	var stick = Joystick.new()
	root.add_child(stick)
	stick.size = Vector2(220, 220)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = Vector2(220, 110)
	stick._gui_input(touch)
	check(stick.direction.is_equal_approx(Vector2.RIGHT), "Edge touch must be full right")
	var other := InputEventScreenDrag.new()
	other.index = 1
	other.position = Vector2(0, 0)
	stick._gui_input(other)
	check(stick.direction.is_equal_approx(Vector2.RIGHT), "A second finger must not hijack the stick")
	touch.pressed = false
	stick._gui_input(touch)
	check(stick.direction == Vector2.ZERO, "Release must stop movement")
	stick.queue_free()

func _test_boot_round_trip() -> void:
	var server := TCPServer.new()
	check(server.listen(0, "127.0.0.1") == OK, "Loopback server must start")
	var boot = load("res://scenes/boot.tscn").instantiate()
	root.add_child(boot)
	boot._endpoint.text = "ws://127.0.0.1:%s/ws" % server.get_local_port()
	boot._token.text = "session-token"
	boot._connect_from_form()
	var peer := WebSocketPeer.new()
	var accepted := false
	var phase := 0
	var moves: Array = []
	for frame in 2400:
		if not accepted and server.is_connection_available():
			peer.accept_stream(server.take_connection())
			accepted = true
		if accepted:
			peer.poll()
			while peer.get_available_packet_count() > 0:
				var m = JSON.parse_string(peer.get_packet().get_string_from_utf8())
				if m is Dictionary and m.get("type") == "auth" and phase == 0:
					check(m.token == "session-token", "Auth token must be forwarded")
					peer.send_text(JSON.stringify({"type": "auth_ok", "userId": "u1"}))
					peer.send_text(JSON.stringify({"type": "player_state", "state": {"x": 3, "y": 4, "health": 90, "gold": "12", "level": 2}}))
					phase = 1
				elif m is Dictionary and m.get("type") == "move":
					moves.append(m)
		if phase == 1 and boot._hud.visible:
			check(not boot._panel.visible, "Login panel must hide once authenticated state arrives")
			boot._touch_direction = Vector2(0, -1)
			phase = 2
		if moves.size() >= 3:
			break
		await process_frame
	check(phase == 2, "Gameplay HUD must open after auth_ok + player_state")
	check(moves.size() >= 3, "Joystick movement must reach the server, got %s" % moves.size())
	if moves.size() >= 2:
		check(moves[0].dy == -1.0 and moves[1].sequence == moves[0].sequence + 1, "Moves must carry joystick intent and ordered sequences")
	check(boot._hud_vitals.text.contains("Gold 12"), "HUD must show server-confirmed gold")
	peer.close()
	for frame in 600:
		peer.poll()
		if not boot._hud.visible:
			break
		await process_frame
	check(not boot._hud.visible and boot._panel.visible, "Disconnect must return to the login panel")
	server.stop()
	boot.queue_free()
