extends SceneTree

const Adapter = preload("res://scripts/websocket_adapter.gd")
var _failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/boot.tscn").instantiate()
	root.add_child(scene)
	check(scene.get_node("Panel/Margin/Content/Token").secret, "Token entry must be masked")
	check(scene.get_node("Panel/Margin/Content/Connect").pressed.is_connected(scene._connect_from_form), "Connect must be wired")
	var theme: Theme = load("res://ui/iom_theme.tres")
	check(theme != null, "Shared UI theme must load")
	check(ProjectSettings.get_setting("gui/theme/custom", "") == "res://ui/iom_theme.tres", "Shared UI theme must be the project theme")
	if theme != null:
		check(theme.get_color("font_color", "TitleLabel").to_html(false) == "f4e6c8", "Title must use parchment token")
		check(theme.get_color("font_color", "SubtitleLabel").to_html(false) == "6ed6d1", "Subtitle must use seafoam token")
		var normal := theme.get_stylebox("normal", "Button") as StyleBoxFlat
		check(normal != null and normal.bg_color.to_html(false) == "145b63", "Button must use lagoon token")
		check(theme.get_type_variation_base("HeroButton") == &"Button", "HeroButton must extend Button")
	check(scene.get_node("Panel/Margin/Content/Title").text == "ISLES OF MYTHOS", "Title must read exactly ISLES OF MYTHOS")
	var preset := ConfigFile.new()
	check(preset.load("res://export_presets.cfg") == OK, "Export preset must load")
	check(preset.get_value("preset.0.options", "permissions/internet", false), "APK must allow Internet access")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method", "") == "mobile", "Mobile renderer required")
	var adapter := Adapter.new()
	root.add_child(adapter)
	for url in ["wss://example.invalid/ws", "ws://127.0.0.1:3000/ws", "ws://localhost:3000/ws", "ws://[::1]:3000/ws"]:
		check(adapter._is_safe_authenticated_url(url), "Valid endpoint rejected: " + url)
	for url in ["ws://example.invalid/ws", "ws://localhost.evil.invalid/ws", "ws://localhost@evil.invalid/ws", "https://example.invalid/ws"]:
		check(not adapter._is_safe_authenticated_url(url), "Unsafe endpoint accepted: " + url)
	# A real loopback WebSocket proves one auth frame and safe explicit reconnect.
	var server := TCPServer.new()
	check(server.listen(0, "127.0.0.1") == OK, "Loopback test server must start")
	for attempt in range(2):
		adapter.configure("ws://127.0.0.1:%s/ws" % server.get_local_port(), "test-token-%s" % attempt)
		adapter.connect_to_server()
		var peer := WebSocketPeer.new()
		var accepted := false
		var received := false
		for frame in range(600):
			if not accepted and server.is_connection_available():
				check(peer.accept_stream(server.take_connection()) == OK, "Server handshake must start")
				accepted = true
			if accepted:
				peer.poll()
				if peer.get_available_packet_count() > 0:
					var payload = JSON.parse_string(peer.get_packet().get_string_from_utf8())
					check(payload == {"type": "auth", "token": "test-token-%s" % attempt}, "Auth frame must match server contract and current credentials")
					received = true
					break
			await process_frame
		check(received, "Authentication must reach real WebSocket on attempt %s" % attempt)
		peer.close()
	var closed_port := server.get_local_port()
	server.stop()
	adapter.configure("ws://127.0.0.1:%s/ws" % closed_port, "test-token")
	adapter.connect_to_server()
	for frame in range(600):
		if not adapter._attempt_active:
			break
		await process_frame
	check(not adapter._attempt_active, "Refused connections must terminate the pending attempt")
	adapter.queue_free()
	scene.queue_free()
	print("IOM-00 connection checks: %s failures" % _failures)
	quit(1 if _failures else 0)
