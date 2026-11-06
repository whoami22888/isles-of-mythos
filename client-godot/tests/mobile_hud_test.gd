extends SceneTree

## Phone HUD layout for the vertical slice: once a session is handed off or
## authenticated the connection form disappears, the HUD collapses to a compact
## strip (status, Gather, drawer toggle) by default, the drawer toggle expands
## the viewport-bounded objectives/crafting scroll area, and the touch joystick
## zone follows the HUD edge. Presentation only; the stub client records
## intents and the server stays the only authority.
const Scene = preload("res://gameplay/vertical_slice.tscn")
const CONTENT := "Interface/Panel/Margin/Content/"
const MAX_COLLAPSED_FRACTION := 0.22

class StubClient extends Node:
	var authed := true
	var connects := 0
	func configure(_u: String, _t: String) -> void: pass
	func connect_to_server() -> void: connects += 1
	func is_authenticated() -> bool: return authed
	func request_world_chunk(_x: int, _y: int) -> String: return ""
	func request_move(_dx: float, _dy: float) -> bool: return true
	func request_gather(_id: String) -> String: return ""
	func request_craft(_id: String) -> String: return ""

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		push_error("mobile HUD test failed: " + label)
		failures += 1

func _settle() -> void:
	for _i in range(3):
		await process_frame

func _make() -> Array:
	var world = Scene.instantiate()
	world.begin_authenticated_session("ws://127.0.0.1:9/ws", "test-session")
	root.add_child(world)
	await process_frame
	var stub := StubClient.new()
	world.add_child(stub)
	world._client = stub
	world._on_authenticated("u1")
	await _settle()
	return [world, stub]

func _panel(world) -> Control:
	return world.get_node("Interface/Panel") as Control

## Collapsed HUD right edge as a fraction of the visible width.
func _collapsed_fraction(world) -> float:
	var visible := root.get_visible_rect().size
	return _panel(world).get_global_rect().end.x / visible.x

func run() -> void:
	# The headless window does not start at the project size; pin 1280x720.
	root.size = Vector2i(1280, 720)
	await _settle()
	var screen_size := root.get_visible_rect().size
	print("visible rect at start: %s" % [screen_size])
	check(screen_size == Vector2(1280, 720), "test view is 1280x720, got %s" % [screen_size])

	# Pre-login/debug flow keeps the full form (no handoff, no auth yet).
	var debug_world = Scene.instantiate()
	root.add_child(debug_world)
	await _settle()
	check(debug_world.get_node(CONTENT + "Endpoint").visible, "pre-login form shows the endpoint")
	check(debug_world.get_node(CONTENT + "Connect").visible, "pre-login form shows the connect button")
	check(not debug_world.is_gameplay_hud(), "pre-login flow is not the compact HUD")
	debug_world.queue_free()
	await process_frame

	var made = await _make()
	var world = made[0]
	var stub: StubClient = made[1]

	# Connection fields hidden after authentication.
	for path in ["Endpoint", "Token", "Connect", "Title"]:
		check(not world.get_node(CONTENT + path).visible, "%s hidden after authentication" % path)
	check(world.get_node(CONTENT + "Token").text.is_empty(), "JWT never rendered")
	check(world.get_node(CONTENT + "Status").visible, "status line stays visible")
	var gather: Button = world.get_node(CONTENT + "Gather")
	var toggle: Button = world.get_node(CONTENT + "DrawerToggle")
	check(gather.visible and gather.get_global_rect().size.y >= 48.0, "Gather visible with a 48 px touch target, h %.0f" % gather.get_global_rect().size.y)
	check(toggle.visible and toggle.get_global_rect().size.y >= 48.0 and toggle.get_global_rect().size.x >= 48.0, "drawer toggle is a 48 px touch target, size %s" % [toggle.get_global_rect().size])

	# Collapsed by default in gameplay.
	check(world.is_gameplay_hud() and not world.is_drawer_open(), "gameplay HUD starts collapsed")
	check(not world.get_node(CONTENT + "HudScroll").visible, "drawer scroll area hidden when collapsed")
	check(world.get_node_or_null(CONTENT + "HudScroll/HudPanels/CraftPanel") != null, "craft panel still mounted while collapsed")

	# Collapsed width at 1280x720.
	var fraction_720 := _collapsed_fraction(world)
	print("collapsed HUD at %s: end.x %.1f (%.1f%%)" % [root.get_visible_rect().size, _panel(world).get_global_rect().end.x, fraction_720 * 100.0])
	check(fraction_720 <= MAX_COLLAPSED_FRACTION, "collapsed HUD covers %.1f%% of 1280-wide view (<= 22%%)" % (fraction_720 * 100.0))

	# Joystick zone widens when collapsed.
	var touch = world.get_node("Interface/TouchControls")
	var collapsed_free: float = touch.free_area_left()
	var collapsed_split: float = touch.joystick_split_x()
	check(is_equal_approx(collapsed_free, _panel(world).get_global_rect().end.x), "joystick free area follows the collapsed HUD edge")

	# Toggle expands.
	toggle.pressed.emit()
	await _settle()
	check(world.is_drawer_open(), "toggle expands the drawer")
	check(world.get_node(CONTENT + "HudScroll").visible, "expanded drawer shows the scroll area")
	check(toggle.visible and toggle.get_global_rect().size.y >= 48.0, "toggle stays a 48 px target when expanded")
	var expanded_free: float = touch.free_area_left()
	var expanded_split: float = touch.joystick_split_x()
	print("joystick zone: collapsed free_left %.0f split %.0f width %.0f; expanded free_left %.0f split %.0f width %.0f" % [collapsed_free, collapsed_split, collapsed_split - collapsed_free, expanded_free, expanded_split, expanded_split - expanded_free])
	check(collapsed_free < expanded_free and collapsed_split - collapsed_free > expanded_split - expanded_free, "joystick zone is wider when the HUD is collapsed")

	# Craft buttons reachable when expanded: viewport-bounded scroll, every
	# Craft button can be scrolled into the scroll area and is on screen.
	var scroll: ScrollContainer = world.get_node(CONTENT + "HudScroll")
	var hud_panels: Control = world.get_node(CONTENT + "HudScroll/HudPanels")
	for i in range(20):
		var filler := Button.new()
		filler.custom_minimum_size = Vector2(0, 48)
		hud_panels.add_child(filler)
	hud_panels.move_child(world.get_node(CONTENT + "HudScroll/HudPanels/CraftPanel"), hud_panels.get_child_count() - 1)
	await _settle()
	var visible_size := root.get_visible_rect().size
	var hud_rect := _panel(world).get_global_rect()
	check(hud_rect.end.y <= visible_size.y, "expanded HUD bottom %.0f fits viewport height %.0f" % [hud_rect.end.y, visible_size.y])
	var craft_buttons: Array = []
	for node in world.get_node(CONTENT + "HudScroll/HudPanels/CraftPanel").find_children("*", "Button", true, false):
		if (node as Button).text.to_lower().contains("craft"):
			craft_buttons.append(node)
	check(not craft_buttons.is_empty(), "craft panel exposes Craft buttons")
	for button in craft_buttons:
		scroll.ensure_control_visible(button)
		await _settle()
		var rect: Rect2 = (button as Control).get_global_rect()
		var scroll_rect := scroll.get_global_rect()
		var reachable := scroll_rect.encloses(rect) and Rect2(Vector2.ZERO, visible_size).encloses(rect)
		check(reachable, "Craft button %s reachable at %s inside scroll %s" % [(button as Node).name, rect, scroll_rect])

	# Toggle collapses again, and the joystick zone widens back.
	toggle.pressed.emit()
	await _settle()
	check(not world.is_drawer_open() and not scroll.visible, "toggle collapses the drawer")
	check(is_equal_approx(touch.free_area_left(), collapsed_free), "joystick zone returns to the collapsed width")

	# A lost session brings back only the Reconnect control.
	stub.authed = false
	world._process(0.016)
	await _settle()
	var reconnect: Button = world.get_node(CONTENT + "Connect")
	check(reconnect.visible and reconnect.text.to_lower().contains("reconnect"), "Reconnect returns after the session drops")
	check(not world.get_node(CONTENT + "Endpoint").visible and not world.get_node(CONTENT + "Token").visible, "endpoint and JWT stay hidden after a drop")
	check(_collapsed_fraction(world) <= MAX_COLLAPSED_FRACTION, "collapsed HUD with Reconnect stays <= 22%")
	reconnect.pressed.emit()
	check(stub.connects == 1, "Reconnect reuses the in-memory session")
	stub.authed = true
	world._on_authenticated("u1")
	await _settle()
	check(not reconnect.visible and not world.is_drawer_open(), "re-authentication hides Reconnect and keeps the drawer choice")

	# S23 Ultra landscape: 2340x1080 window. With canvas_items/expand stretch
	# the visible rect keeps a 720 px height and widens; the fraction is
	# resolution independent either way.
	var old_size: Vector2i = root.size
	root.size = Vector2i(2340, 1080)
	await _settle()
	var wide := root.get_visible_rect().size
	var fraction_wide := _collapsed_fraction(world)
	print("window %s visible %s: collapsed HUD end.x %.1f (%.1f%%)" % [root.size, wide, _panel(world).get_global_rect().end.x, fraction_wide * 100.0])
	check(root.size == Vector2i(2340, 1080), "window resized to 2340x1080, got %s" % [root.size])
	check(fraction_wide <= MAX_COLLAPSED_FRACTION, "collapsed HUD covers %.1f%% of the 2340x1080 view (<= 22%%)" % (fraction_wide * 100.0))
	toggle.pressed.emit()
	await _settle()
	check(_panel(world).get_global_rect().end.y <= root.get_visible_rect().size.y, "expanded HUD fits the 2340x1080 view")
	root.size = old_size
	await _settle()

	world.queue_free()
	await process_frame
	if failures > 0:
		push_error("mobile HUD test: %d failure(s)" % failures)
		print("FAIL mobile_hud_test")
		quit(1)
	else:
		print("PASS mobile_hud_test")
		quit(0)
