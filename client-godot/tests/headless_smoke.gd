extends SceneTree

const Adapter = preload("res://scripts/websocket_adapter.gd")
const PerformancePolicy = preload("res://autoload/performance_adapter.gd")
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
	check(scene._http.max_redirects == 0, "Password-bearing auth requests must not follow redirects")
	check(scene._http.timeout > 0.0 and scene._http.timeout <= 30.0, "Authentication must have a bounded network timeout")
	check(scene.get_node("Panel/Margin/Content/Password").secret, "Password entry must be masked")
	check(scene.get_node("Panel/Margin/Content/Modes/PlayerLogin").pressed.get_connections().size() == 1, "Player mode button must be wired")
	check(scene.get_node("Panel/Margin/Content/Modes/RegisterPlayer").pressed.get_connections().size() == 1, "Registration button must be wired")
	check(scene.get_node("Panel/Margin/Content/Modes/AdminLogin").pressed.get_connections().size() == 1, "Admin button must be wired")
	check(scene._auth_api_path("player") == "/auth/login", "Player endpoint must be login")
	check(scene._auth_api_path("register") == "/auth/register", "Registration endpoint must be separate")
	check(scene._auth_api_path("admin") == "/auth/admin/login", "Admin endpoint must be separate")
	check(scene._auth_base_url_for_endpoint("wss://game.example.test/ws") == "https://game.example.test", "Remote authentication must use HTTPS")
	check(scene._auth_base_url_for_endpoint("ws://127.0.0.1:3000/ws") == "http://127.0.0.1:3000", "Local auth may use HTTP loopback")
	check(scene._auth_base_url_for_endpoint("ws://game.example.test/ws").is_empty(), "Remote plaintext authentication must be rejected")
	check(scene._auth_base_url_for_endpoint("wss://evil.example/ws?x=1").is_empty(), "Authentication URL queries must be rejected")
	check(not scene._auth_payload("tester", "password", "user@example.test", "register").has("role"), "Registration payload may not request an admin role")
	scene._switch_mode("register")
	check(scene.get_node("Panel/Margin/Content/Email").visible, "Registration must show email")
	scene._switch_mode("admin")
	check(not scene.get_node("Panel/Margin/Content/Email").visible, "Admin must not ask for email registration")
	scene._switch_mode("player")
	check(str(ProjectSettings.get_setting("application/config/default_ws_url", "")) == "", "Client must not advertise Android localhost as a live server")
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
	var login_endpoint := "ws://127.0.0.1:1/ws"
	scene.get_node("Panel/Margin/Content/Endpoint").text = login_endpoint
	scene.get_node("Panel/Margin/Content/Identifier").text = "test-player"
	scene.get_node("Panel/Margin/Content/Password").text = "test-password-only"
	scene._connect_from_form()
	check(scene._busy, "Login request must enter busy state")
	scene.get_node("Panel/Margin/Content/Endpoint").text = "ws://127.0.0.1:2/ws"
	scene._on_auth_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"accessToken": "test-token"}).to_utf8_buffer())
	check(scene._adapter._url == login_endpoint, "JWT must use the endpoint that received the password")
	scene._http.cancel_request()
	scene._set_busy(true)
	scene.get_node("Panel/Margin/Content/Password").text = "test-password-only"
	scene._on_auth_completed(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	check(not scene._busy and scene.get_node("Panel/Margin/Content/Password").text.is_empty(), "Timeout must restore the form and clear the password")
	var preset := ConfigFile.new()
	check(preset.load("res://export_presets.cfg") == OK, "Export preset must load")
	check(preset.get_value("preset.0.options", "permissions/internet", false), "APK must allow Internet access")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method", "") == "mobile", "Mobile renderer required")

	var viewport := root.get_viewport()
	var original_3d_scale := viewport.scaling_3d_scale
	var original_canvas_transform := viewport.canvas_transform
	var performance_adapter = root.get_node_or_null("PerformanceAdapter")
	check(performance_adapter != null, "Dynamic resolution adapter must be registered as an autoload")
	if performance_adapter != null:
		performance_adapter.monitoring_enabled = false

	var low_fps_step := PerformancePolicy.next_policy_state(1.0, 47.9, 16.0, 0.0, 0.5)
	check(is_equal_approx(low_fps_step.x, 0.95) and is_equal_approx(low_fps_step.y, 0.0), "FPS below 48 must lower 3D scale by 0.05")
	var slow_frame_step := PerformancePolicy.next_policy_state(1.0, 55.0, 20.1, 0.0, 0.5)
	check(is_equal_approx(slow_frame_step.x, 0.95), "Average frame time above 20 ms must lower 3D scale")
	var exact_boundary := PerformancePolicy.next_policy_state(1.0, 48.0, 20.0, 0.0, 0.5)
	check(is_equal_approx(exact_boundary.x, 1.0), "Exact 48 FPS and 20 ms boundaries must not lower scale")
	var minimum_step := PerformancePolicy.next_policy_state(0.72, 47.0, 25.0, 0.0, 0.5)
	check(is_equal_approx(minimum_step.x, 0.70), "3D scale must not fall below 0.70")
	var restore_step := PerformancePolicy.next_policy_state(0.70, 59.0, 16.5, 9.5, 0.5)
	check(is_equal_approx(restore_step.x, 0.72) and is_equal_approx(restore_step.y, 9.0), "Ten stable seconds must restore one 0.02 step")
	var unstable_step := PerformancePolicy.next_policy_state(0.80, 58.4, 16.5, 9.5, 0.5)
	check(is_equal_approx(unstable_step.x, 0.80) and is_equal_approx(unstable_step.y, 0.0), "Below 58.5 FPS must reset the restore timer")
	var restore_cap := PerformancePolicy.next_policy_state(0.99, 59.0, 16.5, 9.5, 0.5)
	check(is_equal_approx(restore_cap.x, 1.0), "Restoration must never exceed native 1.0x resolution")
	var restore_spacing := PerformancePolicy.next_policy_state(0.72, 59.0, 16.5, 9.0, 0.5)
	check(is_equal_approx(restore_spacing.x, 0.72) and is_equal_approx(restore_spacing.y, 9.5), "Restore increments must be spaced one second apart")

	if performance_adapter != null:
		performance_adapter._set_scale(1.0)
		performance_adapter._stable_seconds = 0.0
		performance_adapter.apply_metrics_sample(47.9, 16.0, 0.5)
		check(is_equal_approx(viewport.scaling_3d_scale, 0.95), "Autoload must apply the 3D-only scale step")
		performance_adapter._set_scale(0.72)
		performance_adapter.apply_metrics_sample(47.0, 25.0, 0.5)
		check(is_equal_approx(viewport.scaling_3d_scale, 0.70), "Autoload must clamp the 3D scale at 0.70")
		performance_adapter._stable_seconds = 9.5
		performance_adapter.apply_metrics_sample(59.0, 16.5, 0.5)
		check(is_equal_approx(viewport.scaling_3d_scale, 0.72), "Autoload must restore 3D scale after ten stable seconds")
		check(viewport.canvas_transform == original_canvas_transform, "3D scaling must leave the 2D canvas transform unchanged")
		performance_adapter._set_scale(original_3d_scale)
		performance_adapter._stable_seconds = 0.0
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
