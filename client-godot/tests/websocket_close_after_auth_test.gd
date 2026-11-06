extends SceneTree

# MYTHOS-NET-01/05 regression: when auth_ok (and following frames) arrive in the
# same poll as an abrupt server close, Godot discards the queued packets, so the
# adapter cannot see auth_ok. An abrupt (non-1008) drop after `auth` was sent must
# still be recovered automatically. Before the fix the adapter reported a plain
# "Disconnected" and never retried: the intermittent NET05 e2e timeout
# (phase1_parties=0, completes=0).
const Adapter = preload("res://scripts/websocket_adapter.gd")

var failures := 0
var statuses: Array = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		push_error("close-after-auth test failed: " + label)
		failures += 1

func wait_until(cond: Callable, timeout_ms: int, peer: WebSocketPeer = null) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not cond.call():
		if Time.get_ticks_msec() > deadline:
			return false
		if peer != null:
			peer.poll()
		await process_frame
	return true

func run() -> void:
	var server := TCPServer.new()
	check(server.listen(0, "127.0.0.1") == OK, "loopback listen")
	var port := server.get_local_port()
	var adapter = Adapter.new()
	adapter.reconnect_base_delay = 0.05
	root.add_child(adapter)
	adapter.status_changed.connect(func(s: String) -> void: statuses.append(s))
	adapter.configure("ws://127.0.0.1:%d/ws" % port, "test-token")
	adapter.connect_to_server()
	check(await wait_until(func(): return server.is_connection_available(), 3000), "client connects")
	var stream := server.take_connection()
	var peer := WebSocketPeer.new()
	check(peer.accept_stream(stream) == OK, "accept websocket")
	check(await wait_until(func(): return peer.get_ready_state() == WebSocketPeer.STATE_OPEN, 3000, peer), "handshake")
	check(await wait_until(func(): return peer.get_available_packet_count() > 0, 3000, peer), "client sends auth")
	peer.get_packet()
	# Pause the adapter so the server's frames and its abrupt close land in one client poll.
	adapter.process_mode = Node.PROCESS_MODE_DISABLED
	peer.send_text('{"type":"auth_ok"}')
	peer.send_text('{"type":"player_state","x":0,"y":0}')
	peer.poll()
	await create_timer(0.2).timeout
	stream.disconnect_from_host()
	await create_timer(0.2).timeout
	adapter.process_mode = Node.PROCESS_MODE_INHERIT
	var retried := await wait_until(func():
		for s in statuses:
			if str(s).begins_with("Connection lost"):
				return true
		return false, 3000)
	check(retried, "auth_ok queued before an abrupt close still yields an automatic reconnect; statuses=%s" % [statuses])
	check(not statuses.has("Disconnected"), "not reported as a plain disconnect; statuses=%s" % [statuses])
	adapter.disconnect_from_server()
	server.stop()
	print("Close-after-auth regression: %d failures" % failures)
	quit(1 if failures > 0 else 0)
