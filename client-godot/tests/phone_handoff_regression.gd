extends SceneTree

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func run() -> void:
	var scene = load("res://gameplay/vertical_slice.tscn").instantiate()
	check(scene.has_method("begin_authenticated_session"), "Gameplay must accept an in-memory authenticated handoff")
	if scene.has_method("begin_authenticated_session"):
		scene.begin_authenticated_session("ws://127.0.0.1:9/ws", "test-session")
		root.add_child(scene)
		check(scene.get_node("Interface/Panel/Margin/Content/Token").text.is_empty(), "The handoff must not render the JWT in a form")
		check(not scene.get_node("Interface/Panel/Margin/Content/Token").visible, "The handoff must hide manual JWT input")
		check(scene._client._url == "ws://127.0.0.1:9/ws", "Gameplay must connect to the authenticated origin")
		check(scene._client._token == "test-session", "Gameplay must use only the handed-off session")
		scene.queue_free()
	else:
		scene.free()
	var default_boot = load("res://scenes/boot.tscn").instantiate()
	root.add_child(default_boot)
	default_boot._adapter.configure("ws://127.0.0.1:9/ws", "test-session")
	default_boot._adapter._attempt_active = true
	default_boot._adapter._auth_sent = true
	ProjectSettings.set_setting("application/config/internal_gameplay_handoff", true)
	default_boot._on_message({"type": "auth_ok", "userId": "test-user"})
	check(current_scene != null and current_scene.has_method("begin_authenticated_session"), "Default phone boot must enter the gameplay world")
	# The handoff frees the boot scene itself. Do not free it again.
	var entered = current_scene
	await process_frame
	if is_instance_valid(entered):
		entered.queue_free()
	await process_frame
	current_scene = null
	var held = load("res://scenes/boot.tscn").instantiate()
	root.add_child(held)
	held._adapter.configure("ws://127.0.0.1:9/ws", "test-session")
	held._adapter._attempt_active = true
	held._adapter._auth_sent = true
	ProjectSettings.set_setting("application/config/internal_gameplay_handoff", false)
	held._on_message({"type": "auth_ok", "userId": "test-user"})
	check(current_scene == null or not current_scene.has_method("begin_authenticated_session"), "Explicit handoff disable must stay on the login screen")
	held.queue_free()
	await process_frame
	var boot = load("res://scenes/boot.tscn").instantiate()
	root.add_child(boot)
	boot._adapter.configure("ws://127.0.0.1:9/ws", "test-session")
	boot._adapter._attempt_active = true
	boot._adapter._auth_sent = true
	ProjectSettings.set_setting("application/config/internal_gameplay_handoff", true)
	boot._on_message({"type": "auth_ok", "userId": "test-user"})
	await process_frame
	check(current_scene != null and current_scene.has_method("begin_authenticated_session"), "Server auth_ok must launch the internal gameplay scene")
	if current_scene != null:
		check(current_scene._client._url == "ws://127.0.0.1:9/ws", "Auth handoff must preserve the authenticated endpoint")
		check(current_scene._client._token == "test-session", "Auth handoff must preserve only the authenticated session")
	ProjectSettings.set_setting("application/config/internal_gameplay_handoff", false)
	print("Phone handoff regression: %s failures" % failures)
	await process_frame
	await process_frame
	quit(1 if failures else 0)
