extends SceneTree

const Gateway = preload("res://scripts/network/authoritative_command_gateway.gd")
var failures := 0
var acked: Array[String] = []
var unresolved: Array[String] = []

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var gateway = Gateway.new()
	root.add_child(gateway)
	gateway.request_acknowledged.connect(func(id: String, _message: Dictionary): acked.append(id))
	gateway.request_outcome_unknown.connect(func(id: String, _reason: String): unresolved.append(id))
	check(gateway.send_request("get_guild") == "", "Unauthenticated command rejected")
	check(gateway.send_request("auth") == "", "Auth cannot be issued as generic request")
	var listener := TCPServer.new()
	check(listener.listen(0, "127.0.0.1") == OK, "Loopback server must bind")
	gateway.configure("ws://127.0.0.1:%s/ws" % listener.get_local_port(), "test-token")
	gateway.connect_to_server()
	var peer := WebSocketPeer.new()
	var accepted := false
	var auth_received := false
	for _frame in range(600):
		if not accepted and listener.is_connection_available():
			check(peer.accept_stream(listener.take_connection()) == OK, "Socket handshake")
			accepted = true
		if accepted:
			peer.poll()
			while peer.get_available_packet_count() > 0:
				var message = JSON.parse_string(peer.get_packet().get_string_from_utf8())
				if message is Dictionary and message.get("type") == "auth":
					check(message.get("token") == "test-token", "Auth frame contract")
					check(peer.send_text(JSON.stringify({"type":"auth_ok","userId":"test-user"})) == OK, "Auth response")
					auth_received = true
		await process_frame
		if gateway.is_authenticated():
			break
	check(auth_received and gateway.is_authenticated(), "Server-confirmed auth required")
	var request_id: String = gateway.send_request("get_guild")
	check(request_id.length() == 32, "Random 32-character requestId")
	check(gateway.send_request("build", {"requestId":"spoof"}) == "", "Caller cannot overwrite requestId")
	check(gateway.pending_count() == 1, "One pending request")
	var wire_request: Dictionary = {}
	for _frame in range(200):
		peer.poll()
		if peer.get_available_packet_count() > 0:
			var packet = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if packet is Dictionary and packet.get("type") == "get_guild":
				wire_request = packet
				break
		await process_frame
	check(wire_request.get("requestId") == request_id, "Request ID reaches socket peer")
	gateway._on_protocol_message({"type":"guild_state","requestId":"wrong-id","guild":null})
	check(gateway.pending_count() == 1 and acked.is_empty(), "Wrong ID cannot acknowledge")
	check(peer.send_text(JSON.stringify({"type":"guild_state","requestId":request_id,"guild":null})) == OK, "Reply transmitted")
	for _frame in range(200):
		peer.poll()
		await process_frame
		if gateway.pending_count() == 0:
			break
	check(acked == [request_id], "Correlated reply acknowledges once")
	gateway._on_protocol_message({"type":"guild_state","requestId":request_id,"guild":null})
	check(acked.size() == 1, "Duplicate ACK ignored")
	var unresolved_id: String = gateway.send_request("build", {"buildingType":"town_hall","level":1,"gridX":2,"gridY":3})
	check(unresolved_id.length() == 32, "Mutation held pending only")
	gateway.connect_to_server()
	check(unresolved.has(unresolved_id) and gateway.pending_count() == 0, "Reconnect invalidates ambiguous mutation")
	gateway.queue_free()
	peer.close()
	listener.stop()
	print("IOM-03 command gateway smoke: %s failure(s)" % failures)
	quit(1 if failures else 0)
