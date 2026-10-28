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
	check(gateway.send_request("not_a_server_command") == "", "Unknown protocol command rejected")
	check(gateway.send_request("build", {"buildingType":"town_hall","level":1,"gridX":2,"gridY":3,"currency":999}) == "", "Unknown command fields rejected")
	var normalized_chat: Dictionary = gateway._normalized_fields("chat_history", {"channel":"local"})
	check(normalized_chat.get("recipientUserId") == null and normalized_chat.get("guildId") == null and normalized_chat.get("partyId") == null, "Chat nullable fields are serialized explicitly")
	var normalized_auction: Dictionary = gateway._normalized_fields("auction_list", {})
	check(normalized_auction.get("itemId") == null and normalized_auction.get("minPrice") == null and normalized_auction.get("maxPrice") == null, "Auction nullable fields are serialized explicitly")
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
	var chat_id: String = gateway.send_request("chat_history", {"channel":"local"})
	var auction_id: String = gateway.send_request("auction_list")
	check(chat_id.length() == 32 and auction_id.length() == 32, "Nullable-field requests accepted")
	var wire_chat: Dictionary = {}
	var wire_auction: Dictionary = {}
	for _frame in range(200):
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var wire_packet = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if wire_packet is Dictionary and wire_packet.get("type") == "chat_history":
				wire_chat = wire_packet
			elif wire_packet is Dictionary and wire_packet.get("type") == "auction_list":
				wire_auction = wire_packet
		if not wire_chat.is_empty() and not wire_auction.is_empty():
			break
		await process_frame
	check(wire_chat.has("recipientUserId") and wire_chat["recipientUserId"] == null and wire_chat.has("guildId") and wire_chat["guildId"] == null and wire_chat.has("partyId") and wire_chat["partyId"] == null, "chat_history wire frame carries explicit null fields")
	for key in ["itemId", "rarity", "category", "minLevel", "maxLevel", "minPrice", "maxPrice"]:
		check(wire_auction.has(key) and wire_auction[key] == null, "auction_list wire frame carries explicit null %s" % key)
	gateway._on_protocol_message({"type":"chat_history","requestId":chat_id,"messages":[]})
	gateway._on_protocol_message({"type":"auction_list","requestId":auction_id,"listings":[]})
	check(acked == [chat_id, auction_id] and gateway.pending_count() == 1, "Nullable-field requests acknowledged by correlated reply")
	acked.clear()
	gateway._on_protocol_message({"type":"guild_state","requestId":"wrong-id","guild":null})
	check(gateway.pending_count() == 1 and acked.is_empty(), "Wrong ID cannot acknowledge")
	gateway._on_protocol_message({"type":"client_only_fake_ack","requestId":request_id})
	check(gateway.pending_count() == 1 and acked.is_empty(), "Unknown response type cannot acknowledge")
	gateway._on_protocol_message({"type":"guild_state","requestId":request_id,"guild":null,"currency":999})
	check(gateway.pending_count() == 0 and acked == [request_id], "Authoritative response is observed, never minted locally")
	var second_id: String = gateway.send_request("get_guild")
	check(second_id.length() == 32, "Second read-only request accepted")
	check(peer.send_text(JSON.stringify({"type":"guild_state","requestId":request_id,"guild":null})) == OK, "Reply transmitted")
	for _frame in range(200):
		peer.poll()
		await process_frame
		if gateway.pending_count() == 0:
			break
	check(acked == [request_id], "Duplicate network ACK cannot alter acknowledged state")
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
