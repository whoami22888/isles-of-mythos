extends SceneTree

# MYTHOS-NET-01: the client adapter must mirror the server's bounded-message
# contract, report (never silently drop) bad packets, and recover from lost
# sessions with capped backoff. Uses a real loopback WebSocket server.

const Adapter = preload("res://scripts/websocket_adapter.gd")
const AUTH_OK := '{"type":"auth_ok"}'

var _failures := 0
var _errors: Array = []
var _messages: Array = []
var _scheduled: Array = []
var _reconnected := 0
var _reconnect_failed := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

func _init() -> void:
	call_deferred("run")

func _wait_until(condition: Callable, timeout_ms: int, peers: Array = []) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		for peer in peers:
			if peer != null:
				peer.poll()
		await process_frame
	return true

func _open_peer(server: TCPServer) -> WebSocketPeer:
	var arrived := await _wait_until(func(): return server.is_connection_available(), 3000)
	if not arrived:
		return null
	var peer := WebSocketPeer.new()
	peer.outbound_buffer_size = 262144
	if peer.accept_stream(server.take_connection()) != OK:
		return null
	var opened := await _wait_until(func():
		peer.poll()
		return peer.get_ready_state() == WebSocketPeer.STATE_OPEN, 3000)
	return peer if opened else null

func _read_packet(peer: WebSocketPeer) -> Variant:
	var got := await _wait_until(func():
		peer.poll()
		return peer.get_available_packet_count() > 0, 3000)
	if not got:
		return null
	return JSON.parse_string(peer.get_packet().get_string_from_utf8())

func run() -> void:
	var adapter := Adapter.new()
	root.add_child(adapter)
	for signal_name in ["protocol_error", "reconnect_scheduled", "reconnected", "reconnect_failed"]:
		check(adapter.has_signal(signal_name), "Adapter must expose signal " + signal_name)
	check(adapter.has_method("disconnect_from_server"), "Adapter must expose disconnect_from_server")
	if _failures > 0:
		print("MYTHOS-NET-01 adapter hardening: %s failures (API missing)" % _failures)
		quit(1)
		return
	adapter.reconnect_base_delay = 0.05
	adapter.max_reconnect_delay = 0.12
	adapter.max_reconnect_attempts = 3
	adapter.max_packets_per_frame = 8
	adapter.protocol_error.connect(func(reason: String): _errors.append(reason))
	adapter.message_received.connect(func(message: Dictionary): _messages.append(message))
	adapter.reconnect_scheduled.connect(func(attempt: int, delay: float): _scheduled.append([attempt, delay]))
	adapter.reconnected.connect(func(): _reconnected += 1)
	adapter.reconnect_failed.connect(func(): _reconnect_failed += 1)

	var server := TCPServer.new()
	check(server.listen(0, "127.0.0.1") == OK, "Loopback server must start")
	var url := "ws://127.0.0.1:%s/ws" % server.get_local_port()
	adapter.configure(url, "tok")

	# --- Session 1: bounds and explicit errors -------------------------------
	adapter.connect_to_server()
	var peer := await _open_peer(server)
	check(peer != null, "Session 1 must open")
	if peer == null:
		quit(1)
		return
	var auth = await _read_packet(peer)
	check(auth == {"type": "auth", "token": "tok"}, "Auth frame must match server contract")
	peer.send_text(AUTH_OK)
	await _wait_until(func(): return _messages.size() == 1, 3000, [peer])
	check(_messages.size() == 1 and _messages[0].get("type") == "auth_ok", "auth_ok must reach the consumer")
	check(_errors.is_empty(), "No protocol errors expected so far")

	peer.send_text("x".repeat(140000))
	peer.send_text("[1,2,3]")
	peer.send_text("not json at all")
	peer.send_text('{"type":"still_ok"}')
	await _wait_until(func(): return _errors.size() >= 3 and _messages.size() >= 2, 3000, [peer])
	check(_errors.size() == 3, "Oversize, non-object and invalid JSON must each raise protocol_error (got %s)" % _errors.size())
	check("packet_too_large" in _errors, "Oversize packet must be reported as packet_too_large")
	check(_errors.count("packet_not_json_object") == 2, "Non-object and invalid JSON must be reported as packet_not_json_object")
	check(_messages.size() == 2 and _messages[1].get("type") == "still_ok", "A valid packet after bad ones must still be delivered")

	# Per-frame drain cap: 200 queued packets, at most 8 delivered per frame.
	adapter.set_process(false)
	for i in range(200):
		peer.send_text('{"type":"tick","n":%s}' % i)
	var base_count := _messages.size()
	var max_delta := 0
	var guard := 0
	while _messages.size() - base_count < 200 and guard < 5000:
		peer.poll()
		var before := _messages.size()
		adapter._process(0.0)
		max_delta = maxi(max_delta, _messages.size() - before)
		guard += 1
		await process_frame
	check(_messages.size() - base_count == 200, "All 200 queued packets must eventually be delivered (got %s)" % (_messages.size() - base_count))
	check(max_delta <= 8, "Drain must be capped per frame (max delta %s)" % max_delta)
	check(max_delta > 0, "Drain cap test must deliver packets")
	adapter.set_process(true)

	# --- Lost session: reconnect with backoff, re-auth, signal ---------------
	peer.close(1001, "server_shutdown")
	await _wait_until(func(): return _scheduled.size() >= 1, 3000, [peer])
	check(_scheduled.size() == 1 and _scheduled[0][0] == 1, "First drop must schedule reconnect attempt 1")
	check(absf(_scheduled[0][1] - 0.05) < 0.001, "First backoff must equal base delay")
	var peer2 := await _open_peer(server)
	check(peer2 != null, "Adapter must reconnect after a lost authenticated session")
	if peer2 == null:
		quit(1)
		return
	var auth2 = await _read_packet(peer2)
	check(auth2 == {"type": "auth", "token": "tok"}, "Reconnect must re-authenticate with the configured token")
	peer2.send_text(AUTH_OK)
	await _wait_until(func(): return _reconnected == 1, 3000, [peer2])
	check(_reconnected == 1, "reconnected must be emitted once after re-auth")

	# --- Rejected credentials (1008) must NOT trigger reconnect --------------
	var scheduled_before := _scheduled.size()
	peer2.close(1008, "invalid_token")
	await _wait_until(func(): return false, 400, [peer2])
	check(_scheduled.size() == scheduled_before, "Close code 1008 must not schedule reconnect")
	check(not server.is_connection_available(), "No new connection after 1008")

	# --- Deliberate disconnect must NOT reconnect ----------------------------
	adapter.connect_to_server()
	var peer3 := await _open_peer(server)
	check(peer3 != null, "Explicit connect after 1008 must work")
	if peer3 == null:
		quit(1)
		return
	await _read_packet(peer3)
	peer3.send_text(AUTH_OK)
	await _wait_until(func(): return _messages.size() > base_count + 200 + 1, 3000, [peer3])
	adapter.disconnect_from_server()
	await _wait_until(func(): return false, 400, [peer3])
	check(not server.is_connection_available(), "Deliberate disconnect must not reconnect")
	check(_scheduled.size() == scheduled_before, "Deliberate disconnect must not schedule reconnect")

	# --- Exhaustion: capped backoff then reconnect_failed --------------------
	adapter.connect_to_server()
	var peer4 := await _open_peer(server)
	check(peer4 != null, "Session 4 must open")
	if peer4 == null:
		quit(1)
		return
	await _read_packet(peer4)
	peer4.send_text(AUTH_OK)
	var msgs_before := _messages.size()
	await _wait_until(func(): return _messages.size() > msgs_before, 3000, [peer4])
	_scheduled.clear()
	server.stop()
	peer4.close(1001, "server_shutdown")
	await _wait_until(func(): return _reconnect_failed >= 1, 6000, [peer4])
	check(_reconnect_failed == 1, "reconnect_failed must fire exactly once after attempts are exhausted")
	check(_scheduled.size() == 3, "Exactly max_reconnect_attempts must be scheduled (got %s)" % _scheduled.size())
	if _scheduled.size() == 3:
		check(absf(_scheduled[0][1] - 0.05) < 0.001 and absf(_scheduled[1][1] - 0.10) < 0.001, "Backoff must double")
		check(absf(_scheduled[2][1] - 0.12) < 0.001, "Backoff must be capped at max_reconnect_delay")

	adapter.queue_free()
	print("MYTHOS-NET-01 adapter hardening: %s failures" % _failures)
	quit(1 if _failures else 0)
