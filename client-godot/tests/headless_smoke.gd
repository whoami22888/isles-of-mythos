extends SceneTree

const Adapter = preload("res://scripts/websocket_adapter.gd")
const FallbackFactory = preload("res://scripts/render_fallback_factory.gd")
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
	# Isolate both bounded log generations from earlier headless test runs.
	for log_path in [FallbackFactory.LOG_PATH, FallbackFactory.ROTATED_LOG_PATH]:
		if FileAccess.file_exists(log_path):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(log_path)) == OK, "Missing-asset test log generation must reset")
	# Prompt 004: missing resources must not crash or replace genuine production graphics.
	var missing_character := FallbackFactory.get_fallback_mesh("res://_missing_character_004.glb")
	check(missing_character.mesh is CapsuleMesh, "Missing characters use a capsule diagnostic")
	var character_material := missing_character.material_override as StandardMaterial3D
	check(character_material != null and character_material.albedo_color == Color(0.0, 0.8, 1.0), "Missing character diagnostic must be cyan")
	missing_character.free()
	var missing_prop := FallbackFactory.load_mesh_or_fallback("res://_missing_prop_004.gltf", "building") as MeshInstance3D
	check(missing_prop != null and missing_prop.mesh is BoxMesh, "Missing building uses a box diagnostic")
	if missing_prop != null:
		var prop_material := missing_prop.material_override as StandardMaterial3D
		check(prop_material != null and prop_material.albedo_color == Color(1.0, 0.0, 1.0), "Missing building diagnostic must be magenta")
		missing_prop.free()
	var missing_sprite := FallbackFactory.load_sprite_or_fallback("res://_missing_ui_004.png") as ColorRect
	check(missing_sprite != null and missing_sprite.size == Vector2(32, 32), "Missing sprite must be a 32px ColorRect")
	if missing_sprite != null:
		var checker := missing_sprite.get_node_or_null("Checkerboard") as TextureRect
		check(checker != null and checker.texture != null, "Missing sprite must have checkerboard texture")
		if checker != null and checker.texture != null:
			var pixels := checker.texture.get_image()
			check(pixels.get_pixel(0, 0) != pixels.get_pixel(4, 0), "Checkerboard must have alternating tiles")
		missing_sprite.free()
	var missing_audio := FallbackFactory.load_audio_or_fallback("res://_missing_clip_004.ogg")
	check(missing_audio != null and missing_audio.stream == null, "Missing audio must be safely silent")
	missing_audio.free()
	var missing_texture := FallbackFactory.load_texture_or_fallback("res://_missing_skin_004.png")
	check(missing_texture != null, "Missing skin texture must return a checkerboard texture")
	var missing_animation := FallbackFactory.load_scene_or_null("res://_missing_animation_004.fbx", "animation")
	check(missing_animation == null, "Missing FBX animation scene must fail safely")
	# A PackedScene resource may exist but have no instantiable root; it must
	# become a diagnostic fallback rather than dereferencing a null instance.
	var empty_scene := PackedScene.new()
	check(not empty_scene.can_instantiate(), "Empty PackedScene fixture must be non-instantiable")
	var empty_scene_fallback := FallbackFactory.mesh_resource_or_fallback(
		empty_scene, "res://_empty_scene_004.glb", "character"
	)
	check(empty_scene_fallback is MeshInstance3D and empty_scene_fallback.mesh is CapsuleMesh,
		"Non-instantiable PackedScene must use a capsule diagnostic")
	if empty_scene_fallback != null:
		empty_scene_fallback.free()
	# A valid PackedScene with a non-3D root is instantiated safely, type-checked,
	# freed and replaced with the requested diagnostic primitive.
	var control_root := Control.new()
	var control_scene := PackedScene.new()
	check(control_scene.pack(control_root) == OK, "Non-3D PackedScene fixture must pack")
	control_root.free()
	var control_instance := FallbackFactory.instantiate_scene_or_null(control_scene)
	check(control_instance is Control, "Valid non-3D PackedScene must instantiate for caller type validation")
	if is_instance_valid(control_instance):
		control_instance.free()
	var non_3d_fallback := FallbackFactory.mesh_resource_or_fallback(
		control_scene, "res://_non_3d_scene_004.glb", "building"
	)
	check(non_3d_fallback is MeshInstance3D and non_3d_fallback.mesh is BoxMesh,
		"Non-3D PackedScene must use a box diagnostic")
	non_3d_fallback.free()
	# A valid Node3D scene can still be visually empty; it must not bypass the fallback.
	var empty_3d_root := Node3D.new()
	var empty_3d_scene := PackedScene.new()
	check(empty_3d_scene.pack(empty_3d_root) == OK, "Empty Node3D fixture must pack")
	empty_3d_root.free()
	var empty_3d_fallback := FallbackFactory.mesh_resource_or_fallback(
		empty_3d_scene, "res://_empty_3d_scene_004.glb", "character"
	)
	check(empty_3d_fallback is MeshInstance3D and empty_3d_fallback.mesh is CapsuleMesh,
		"Node3D without a renderable mesh must use a capsule diagnostic")
	if is_instance_valid(empty_3d_fallback):
		empty_3d_fallback.free()

	# A real mesh nested under a Node3D root remains valid.
	var valid_3d_root := Node3D.new()
	var valid_mesh_instance := MeshInstance3D.new()
	valid_mesh_instance.mesh = BoxMesh.new()
	valid_3d_root.add_child(valid_mesh_instance)
	valid_mesh_instance.owner = valid_3d_root
	var valid_3d_scene := PackedScene.new()
	check(valid_3d_scene.pack(valid_3d_root) == OK, "Renderable Node3D fixture must pack")
	valid_3d_root.free()
	var valid_3d_instance := FallbackFactory.mesh_resource_or_fallback(
		valid_3d_scene, "res://_valid_3d_scene_004.glb", "character"
	)
	check(valid_3d_instance.name != "MissingAssetDiagnostic" and FallbackFactory._has_renderable_mesh(valid_3d_instance),
		"Node3D scene with a real mesh must remain loaded")
	valid_3d_instance.free()

	# Empty Mesh resources are also invalid visual payloads.
	var empty_mesh_fallback := FallbackFactory.mesh_resource_or_fallback(
		ArrayMesh.new(), "res://_empty_mesh_004.glb", "building"
	)
	check(empty_mesh_fallback is MeshInstance3D and empty_mesh_fallback.mesh is BoxMesh,
		"Mesh resource with no surfaces must use a box diagnostic")
	empty_mesh_fallback.free()

	var asset_log := FileAccess.open("user://missing_assets.log", FileAccess.READ)
	check(asset_log != null, "Missing asset paths must be written to the user log")
	if asset_log != null:
		var logged := asset_log.get_as_text()
		check(logged.contains("_missing_character_004.glb") and logged.contains("_missing_prop_004.gltf") and logged.contains("_missing_ui_004.png") and logged.contains("_missing_clip_004.ogg") and logged.contains("_missing_skin_004.png") and logged.contains("_missing_animation_004.fbx"), "Every missing asset category must be logged")
		var log_before := logged.count("mesh\tres://_missing_character_004.glb")
		check(log_before == 1, "Initial missing character must create exactly one TSV log record")
		check(logged.ends_with("\n"), "Missing-asset log records must be newline terminated")
		var duplicate := FallbackFactory.get_fallback_mesh("res://_missing_character_004.glb")
		duplicate.free()
		var after_duplicate := FileAccess.get_file_as_string("user://missing_assets.log")
		check(after_duplicate.count("mesh\tres://_missing_character_004.glb") == log_before, "Repeated missing paths must not duplicate diagnostic log entries")
		asset_log.close()
	# A failed write must not poison deduplication; a later successful retry must log.
	var retry_path := "res://_write_retry_004.glb"
	var retry_key := "mesh:" + retry_path
	FallbackFactory._logged_paths.erase(retry_key)
	var write_attempts := [0]
	var fail_then_succeed := func(_line: String):
		check(_line.contains("\t") and _line.ends_with("\n"), "Diagnostic records must use actual TSV delimiters")
		write_attempts[0] += 1
		return FAILED if write_attempts[0] == 1 else OK
	FallbackFactory._log_missing_with_writer(retry_path, "mesh", fail_then_succeed)
	check(not FallbackFactory._logged_paths.has(retry_key), "Failed write must not mark the path as logged")
	FallbackFactory._log_missing_with_writer(retry_path, "mesh", fail_then_succeed)
	check(FallbackFactory._logged_paths.has(retry_key), "Successful retry must mark the path as logged")
	FallbackFactory._log_missing_with_writer(retry_path, "mesh", fail_then_succeed)
	check(write_attempts[0] == 2, "Successful retry must deduplicate subsequent writes")
	# A failed append may already have written a prefix. It must be truncated before retry.
	var before_partial_append := FileAccess.get_file_as_string(FallbackFactory.LOG_PATH)
	var partial_record := "mesh\tpartial_retry_004.glb\n"
	var partial_prefix_written := [false]
	var partial_writer := func(file: FileAccess, _line: String) -> bool:
		partial_prefix_written[0] = file.store_string("mesh\tpartial_retry_004")
		return false
	var partial_error := FallbackFactory._append_log_line(partial_record, partial_writer)
	check(partial_prefix_written[0], "Partial-write fixture must append a prefix before reporting failure")
	check(partial_error == FAILED, "A writer that reports failure must fail the append")
	var after_partial_failure := FileAccess.get_file_as_string(FallbackFactory.LOG_PATH)
	check(after_partial_failure == before_partial_append, "Failed partial append must roll the log back to its original byte length")
	var retry_error := FallbackFactory._append_log_line(partial_record)
	var after_partial_retry := FileAccess.get_file_as_string(FallbackFactory.LOG_PATH)
	check(retry_error == OK and after_partial_retry == before_partial_append + partial_record,
		"Retry after a partial append must produce exactly one complete TSV record")
	# Simulate a new process: the in-memory set resets, but persisted log size stays bounded.
	var restart_path := "res://_restart_repeat_004.glb"
	var restart_key := "mesh:" + restart_path
	FallbackFactory._logged_paths.erase(restart_key)
	FallbackFactory._log_missing(restart_path, "mesh")
	var first_session_bytes := FileAccess.get_file_as_string(FallbackFactory.LOG_PATH).to_utf8_buffer().size()
	FallbackFactory._logged_paths.clear()
	FallbackFactory._logged_path_order.clear()
	FallbackFactory._logged_path_cursor = 0
	FallbackFactory._log_missing(restart_path, "mesh")
	var second_session_bytes := FileAccess.get_file_as_string(FallbackFactory.LOG_PATH).to_utf8_buffer().size()
	check(second_session_bytes > first_session_bytes, "A restarted client may repeat a missing path")
	check(second_session_bytes <= FallbackFactory.MAX_LOG_BYTES, "Persisted diagnostics must remain byte-bounded across restarts")
	# Untrusted asset paths must not introduce extra TSV columns or records.
	var tabbed_asset := FallbackFactory.get_fallback_mesh("res://_missing\tunsafe_004.glb")
	tabbed_asset.free()
	var sanitized_log := FileAccess.get_file_as_string("user://missing_assets.log")
	check(sanitized_log.contains("mesh\tres://_missing unsafe_004.glb\n"), "Tabs in missing asset paths must be sanitized into one TSV record")
	check(not sanitized_log.contains("res://_missing\tunsafe_004.glb"), "Untrusted tabs must not create extra TSV fields")
	# C0/DEL controls must not create TSV separators or hidden record contents.
	var control_path := "res://_missing" + String.chr(11) + String.chr(12) + String.chr(127) + "unsafe_004.glb"
	var control_asset := FallbackFactory.get_fallback_mesh(control_path)
	control_asset.free()
	var safe_log := FileAccess.get_file_as_string(FallbackFactory.LOG_PATH)
	check(safe_log.contains("mesh\tres://_missing   unsafe_004.glb\n"), "Vertical tab, form feed and DEL must become spaces in one TSV record")
	check(not safe_log.contains(String.chr(11)) and not safe_log.contains(String.chr(12)) and not safe_log.contains(String.chr(127)), "Raw C0/DEL controls must never enter missing-resource log")
	# C1 controls (including NEL) and Unicode line/paragraph separators must also stay within one record.
	var unicode_controls := ""
	for codepoint in range(0x80, 0xA0):
		unicode_controls += String.chr(codepoint)
	unicode_controls += String.chr(0x2028) + String.chr(0x2029)
	var unicode_path := "res://_unicode" + unicode_controls + "_unsafe_004.glb"
	var unicode_asset := FallbackFactory.get_fallback_mesh(unicode_path)
	unicode_asset.free()
	var unicode_log := FileAccess.get_file_as_string(FallbackFactory.LOG_PATH)
	var expected_unicode_line := "mesh\tres://_unicode" + " ".repeat(34) + "_unsafe_004.glb\n"
	check(unicode_log.contains(expected_unicode_line), "C1 and Unicode line separators must become spaces in one TSV record")
	for codepoint in range(0x80, 0xA0):
		check(not unicode_log.contains(String.chr(codepoint)), "Raw C1 controls must never enter missing-resource log")
	check(not unicode_log.contains(String.chr(0x2028)) and not unicode_log.contains(String.chr(0x2029)), "Unicode line and paragraph separators must never enter missing-resource log")
	# A caller-supplied category must not inject a TSV column or a second record.
	var category_path := "res://_category_injection_004.fbx"
	var category_input := "mesh" + String.chr(9) + "__INJECTED_COLUMN_004__" + String.chr(10) + "__INJECTED_RECORD_004__"
	var category_probe := FallbackFactory.load_scene_or_null(category_path, category_input)
	check(category_probe == null, "Missing scene with an invalid category must fail safely")
	var category_log := FileAccess.get_file_as_string(FallbackFactory.LOG_PATH)
	check(category_log.contains("other" + String.chr(9) + category_path + String.chr(10)), "Unknown categories must map to the fixed other field")
	check(not category_log.contains("__INJECTED_COLUMN_004__") and not category_log.contains("__INJECTED_RECORD_004__"), "Caller-supplied category text must never enter the TSV log")
	# A full log must be renamed to a bounded .1 generation, not truncated.
	var full_log := FileAccess.open(FallbackFactory.LOG_PATH, FileAccess.WRITE)
	check(full_log != null, "Log rotation fixture must open")
	if full_log != null:
		var historical_line := "mesh\tres://historical_004.glb\n"
		full_log.store_string(historical_line)
		full_log.store_string("x".repeat(FallbackFactory.MAX_LOG_BYTES - historical_line.to_utf8_buffer().size()))
		full_log.close()
		var rotated_asset := FallbackFactory.get_fallback_mesh("res://_rotation_probe_004.glb")
		rotated_asset.free()
		var rotated_text := FileAccess.get_file_as_string(FallbackFactory.LOG_PATH)
		check(rotated_text.contains("_rotation_probe_004.glb"), "New missing asset must be logged after rotation")
		var archive := FileAccess.open(FallbackFactory.ROTATED_LOG_PATH, FileAccess.READ)
		check(archive != null, "Rotation must preserve the previous log in a .1 archive")
		if archive != null:
			check(archive.get_length() == FallbackFactory.MAX_LOG_BYTES, "Archived log must remain at its byte cap")
			check(archive.get_as_text().begins_with(historical_line), "Rotation must preserve prior diagnostics")
			archive.close()
		var active := FileAccess.open(FallbackFactory.LOG_PATH, FileAccess.READ)
		check(active != null, "Active log must be readable after rotation")
		if active != null:
			check(active.get_length() <= FallbackFactory.MAX_LOG_BYTES, "Active diagnostic log must stay under its byte cap")
			active.close()
		# A second rotation replaces the old archive instead of retaining infinite history.
		var second_log := FileAccess.open(FallbackFactory.LOG_PATH, FileAccess.WRITE)
		check(second_log != null, "Second rotation fixture must open")
		if second_log != null:
			var new_history := "mesh\tres://newer_history_004.glb\n"
			second_log.store_string(new_history)
			second_log.store_string("x".repeat(FallbackFactory.MAX_LOG_BYTES - new_history.to_utf8_buffer().size()))
			second_log.close()
			var second_probe := FallbackFactory.get_fallback_mesh("res://_rotation_probe_second_004.glb")
			second_probe.free()
			var final_archive := FileAccess.get_file_as_string(FallbackFactory.ROTATED_LOG_PATH)
			check(final_archive.begins_with(new_history) and not final_archive.contains(historical_line), "Second rotation must replace the old bounded archive")
			check(FileAccess.get_file_as_string(FallbackFactory.LOG_PATH).contains("_rotation_probe_second_004.glb"), "Second rotation must keep logging")
		# Oversized legacy logs must not silently become unbounded archives.
		var legacy_log := FileAccess.open(FallbackFactory.LOG_PATH, FileAccess.WRITE)
		check(legacy_log != null, "Legacy oversized log fixture must open")
		if legacy_log != null:
			legacy_log.store_string("x".repeat(FallbackFactory.MAX_LOG_BYTES + 1))
			legacy_log.close()
			var legacy_probe := FallbackFactory.get_fallback_mesh("res://_legacy_oversized_probe_004.glb")
			legacy_probe.free()
			var legacy_text := FileAccess.get_file_as_string(FallbackFactory.LOG_PATH)
			check(legacy_text.contains("_legacy_oversized_probe_004.glb"), "Oversized historical log must not block new records")
			var archived_size := FileAccess.open(FallbackFactory.ROTATED_LOG_PATH, FileAccess.READ)
			check(archived_size != null, "Bounded archive must survive a legacy oversized log")
			if archived_size != null:
				check(archived_size.get_length() <= FallbackFactory.MAX_LOG_BYTES, "Oversized legacy log must not grow the archive beyond its cap")
				archived_size.close()
	# The dedupe cache is a bounded FIFO, not a hard limit on diagnostic logging.
	FallbackFactory._logged_paths.clear()
	FallbackFactory._logged_path_order.clear()
	FallbackFactory._logged_path_cursor = 0
	var capped_lines: Array[String] = []
	var capture_line := func(line: String):
		capped_lines.append(line)
		return OK
	for index in range(FallbackFactory.MAX_LOGGED_PATHS + 1):
		var cap_path := "res://_dedupe_cap_%04d.glb" % index
		FallbackFactory._log_missing_with_writer(cap_path, "mesh", capture_line)
	check(capped_lines.size() == FallbackFactory.MAX_LOGGED_PATHS + 1, "New unique paths must still be logged after the dedupe cache fills")
	check(FallbackFactory._logged_paths.size() == FallbackFactory.MAX_LOGGED_PATHS, "In-memory dedupe dictionary must stay bounded")
	check(FallbackFactory._logged_path_order.size() == FallbackFactory.MAX_LOGGED_PATHS, "In-memory dedupe order must stay bounded")
	check(not FallbackFactory._logged_paths.has("mesh:res://_dedupe_cap_0000.glb"), "The oldest dedupe key must be evicted")
	check(FallbackFactory._logged_paths.has("mesh:res://_dedupe_cap_1024.glb"), "The newest dedupe key must be retained")
	FallbackFactory._log_missing_with_writer("res://_dedupe_cap_1024.glb", "mesh", capture_line)
	check(capped_lines.size() == FallbackFactory.MAX_LOGGED_PATHS + 1, "A recent duplicate must still be suppressed")
	FallbackFactory._log_missing_with_writer("res://_dedupe_cap_0000.glb", "mesh", capture_line)
	check(capped_lines.size() == FallbackFactory.MAX_LOGGED_PATHS + 2, "An evicted path must be logged again when it reappears")
	check(FallbackFactory._logged_paths.size() == FallbackFactory.MAX_LOGGED_PATHS, "FIFO eviction must keep the cache at its fixed cap")
	FallbackFactory._logged_paths.clear()
	FallbackFactory._logged_path_order.clear()
	FallbackFactory._logged_path_cursor = 0
	adapter.queue_free()
	scene.queue_free()
	print("IOM-00 connection checks: %s failures" % _failures)
	quit(1 if _failures else 0)
