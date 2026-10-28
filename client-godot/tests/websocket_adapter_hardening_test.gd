extends SceneTree

# MYTHOS-NET-01: the client adapter must stay inside the server's bounded-message
# contract, report (never silently drop) bad packets without letting a hostile
# peer flood the diagnostics, and recover from lost sessions with capped backoff
# and a protocol-correct resync. Uses a real loopback WebSocket server.
#
# Scope limits (deliberate): the loopback server is NOT the Fastify server. The
# 200-packet burst proves the client's own per-frame drain bound only; the real
# server's 120 msgs/s per-socket throttle and 64 KiB maxPayload are enforced and
# tested server-side. Resync uses only existing server messages: the server pushes
# auth_ok/player_state/creature_party/base_state after every `auth`, and
# `subscribe_chunks` (1-9 chunks, |x|,|y| <= 1,000,000) is the chunk-state request.

const Adapter = preload("res://scripts/websocket_adapter.gd")
const AUTH_OK := '{"type":"auth_ok"}'
const FRAME_LIMIT := 65536

var _failures := 0
var _errors: Array = []
var _messages: Array = []
var _scheduled: Array = []
var _resyncs: Array = []
var _reconnected := 0
var _reconnect_failed := 0

func _frame_of_size(total_bytes: int) -> String:
	# {"type":"pad","d":"<padding>"} padded to exactly total_bytes bytes.
	var prefix := '{"type":"pad","d":"'
	var suffix := '"}'
	return prefix + "x".repeat(total_bytes - prefix.length() - suffix.length()) + suffix

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
	check(adapter.has_signal("resync_requested"), "Adapter must expose signal resync_requested")
	check(adapter.has_method("subscribe_chunks"), "Adapter must expose subscribe_chunks")
	check(adapter.has_method("reset_error_window"), "Adapter must expose reset_error_window")
	check("invalid_packet_count" in adapter and "suppressed_error_count" in adapter, "Adapter must expose diagnostic counters")
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
	adapter.resync_requested.connect(func(chunk_count: int): _resyncs.append(chunk_count))

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

	# Inbound frame bound equals the server's 64 KiB frame limit. Measured
	# headroom: the worst of 6,561 generated world chunks serialises to 4,626 bytes.
	check(adapter.MAX_PACKET_BYTES == FRAME_LIMIT, "MAX_PACKET_BYTES must be 65536 (got %s)" % adapter.MAX_PACKET_BYTES)
	var messages_before_boundary := _messages.size()
	var errors_before_boundary := _errors.size()
	peer.send_text(_frame_of_size(FRAME_LIMIT))
	await _wait_until(func(): return _messages.size() > messages_before_boundary, 3000, [peer])
	check(_messages.size() == messages_before_boundary + 1 and _messages[-1].get("type") == "pad", "A frame of exactly 65536 bytes must be delivered")
	peer.send_text(_frame_of_size(FRAME_LIMIT + 1))
	await _wait_until(func(): return _errors.size() > errors_before_boundary, 3000, [peer])
	check(_errors.size() == errors_before_boundary + 1 and _errors[-1] == "packet_too_large", "A frame of 65537 bytes must be rejected as packet_too_large")

	# max_packets_per_frame is clamped: zero/negative must never stall delivery.
	adapter.max_packets_per_frame = 0
	check(adapter.max_packets_per_frame >= 1, "max_packets_per_frame must clamp zero up to >= 1 (got %s)" % adapter.max_packets_per_frame)
	adapter.max_packets_per_frame = -5
	check(adapter.max_packets_per_frame >= 1, "max_packets_per_frame must clamp negatives up to >= 1 (got %s)" % adapter.max_packets_per_frame)
	adapter.max_packets_per_frame = 100000
	check(adapter.max_packets_per_frame <= adapter.MAX_PACKETS_PER_FRAME_LIMIT, "max_packets_per_frame must clamp to the hard limit (got %s)" % adapter.max_packets_per_frame)
	adapter.max_packets_per_frame = 8

	# Diagnostics are bounded: a hostile burst of invalid frames raises a capped
	# number of protocol_error signals plus one summary; counters stay exact.
	adapter.error_window_msec = 60000
	adapter.reset_error_window()
	var burst_errors_before := _errors.size()
	var invalid_before: int = adapter.invalid_packet_count
	var suppressed_before: int = adapter.suppressed_error_count
	for i in range(200):
		peer.send_text("nope")
	await _wait_until(func(): return adapter.invalid_packet_count - invalid_before >= 200, 5000, [peer])
	check(adapter.invalid_packet_count - invalid_before == 200, "Every invalid packet must be counted (got %s)" % (adapter.invalid_packet_count - invalid_before))
	var burst_errors := _errors.size() - burst_errors_before
	check(burst_errors == adapter.MAX_ERROR_SIGNALS_PER_WINDOW + 1, "Burst must raise %s signals plus one summary (got %s)" % [adapter.MAX_ERROR_SIGNALS_PER_WINDOW, burst_errors])
	check(_errors.count("errors_suppressed") == 1, "Exactly one errors_suppressed summary per window")
	check(adapter.suppressed_error_count - suppressed_before == 200 - adapter.MAX_ERROR_SIGNALS_PER_WINDOW, "Suppressed counter must be exact (got %s)" % (adapter.suppressed_error_count - suppressed_before))
	peer.send_text('{"type":"after_burst"}')
	await _wait_until(func(): return _messages[-1].get("type") == "after_burst", 3000, [peer])
	check(_messages[-1].get("type") == "after_burst", "Valid delivery must continue after a hostile burst")

	# subscribe_chunks: validated against the server's parser bounds; invalid input
	# sends nothing and never replaces a tracked set.
	check(not adapter.subscribe_chunks([]), "Empty chunk list must be rejected")
	var ten: Array = []
	for i in range(10):
		ten.append({"x": i, "y": 0})
	check(not adapter.subscribe_chunks(ten), "More than 9 chunks must be rejected")
	check(not adapter.subscribe_chunks([{"x": 1.5, "y": 0}]), "Non-integer coordinate must be rejected")
	check(not adapter.subscribe_chunks([{"x": 1000001, "y": 0}]), "Coordinate beyond 1,000,000 must be rejected")
	check(not adapter.subscribe_chunks(["bad"]), "Non-dictionary entry must be rejected")
	check(not adapter.subscribe_chunks([{"x": 1}]), "Entry missing y must be rejected")
	check(adapter.subscribe_chunks([{"x": 0, "y": 0}, {"x": 1, "y": -1}]), "A valid chunk set must be accepted")
	var sub = await _read_packet(peer)
	check(sub is Dictionary and sub.get("type") == "subscribe_chunks", "First packet after validation failures must be the valid subscribe_chunks")
	var first_request_id := ""
	if sub is Dictionary:
		first_request_id = str(sub.get("requestId", ""))
		check(first_request_id.length() >= 1 and first_request_id.length() <= 64, "requestId must satisfy the server's 1-64 character rule")
		var chunks = sub.get("chunks", [])
		check(chunks is Array and chunks.size() == 2 and int(chunks[0]["x"]) == 0 and int(chunks[1]["y"]) == -1, "Chunk coordinates must round-trip")

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
	# Resync: replay the tracked chunk subscription with a fresh requestId. The
	# server itself re-pushes player_state/creature_party/base_state after `auth`.
	var resync = await _read_packet(peer2)
	check(resync is Dictionary and resync.get("type") == "subscribe_chunks", "Reconnect must replay subscribe_chunks for tracked chunks")
	if resync is Dictionary:
		check(str(resync.get("requestId", "")) != first_request_id and str(resync.get("requestId", "")).length() >= 1, "Resync must use a fresh requestId")
		var resync_chunks = resync.get("chunks", [])
		check(resync_chunks is Array and resync_chunks.size() == 2, "Resync must carry the tracked chunk set")
	check(_resyncs == [2], "resync_requested must report the chunk count once (got %s)" % [_resyncs])

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
