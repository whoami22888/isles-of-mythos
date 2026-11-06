extends SceneTree

## Craft panel: server-reported inventory only, one craft in flight, rejection and
## unknown outcomes never change local inventory, and the world wires it through
## the vertical-slice protocol's correlated `craft` / `craft_result` flow.
const CraftPanel = preload("res://gameplay/craft_panel.gd")
const Protocol = preload("res://gameplay/vertical_slice_protocol.gd")
const WorldScene = preload("res://gameplay/vertical_slice.tscn")

var failures := 0
var sent: Array = []
var next_id := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		push_error("craft panel test failed: " + label)
		failures += 1

func fake_sender(recipe_id: String) -> String:
	next_id += 1
	var request_id := "req-%d" % next_id
	sent.append([request_id, recipe_id])
	return request_id

func ack(request_id: String, recipe_id: String, inventory: Dictionary) -> Dictionary:
	return {"type": "craft_result", "requestId": request_id, "transactionId": "t", "recipeId": recipe_id, "state": {"inventory": inventory}}

func run() -> void:
	var panel = CraftPanel.new()
	panel.craft_sender = fake_sender
	root.add_child(panel)
	await process_frame

	check(panel.craft_enabled("tool.wooden-club"), "craft button enabled when idle")
	check(not panel.craft("not.a.recipe"), "unknown recipe is never sent")
	check(sent.is_empty(), "nothing sent yet")
	panel.set_inventory({"resource.wood": 9, "resource.stone": 1})
	check(panel.row_text("tool.wooden-club") == "Wooden Club: wood 9/8", "server inventory rendered, got '%s'" % panel.row_text("tool.wooden-club"))
	check(panel.row_text("tool.stone-axe") == "Stone Axe: wood 9/6, stone 1/4", "ingredients rendered, got '%s'" % panel.row_text("tool.stone-axe"))

	# Send exactly one craft; disabled and no double send while in flight.
	check(panel.craft("tool.wooden-club"), "craft sends")
	check(sent == [["req-1", "tool.wooden-club"]], "one craft sent with recipeId only")
	check(not panel.craft_enabled("tool.wooden-club") and not panel.craft_enabled("tool.stone-axe"), "all craft buttons disabled while in flight")
	check(not panel.craft("tool.wooden-club") and not panel.craft("tool.stone-axe"), "no second send while in flight")
	check(sent.size() == 1, "still exactly one request sent")

	# An uncorrelated error may belong to another command: the craft stays pending.
	panel.on_server_error("INSUFFICIENT_INVENTORY")
	check(panel.is_busy() and not panel.craft_enabled("tool.wooden-club"), "uncorrelated error keeps the craft pending")
	# Attributed rejection: server error text shown, inventory untouched, request cleared.
	panel.on_craft_rejected("other-id", "INSUFFICIENT_INVENTORY")
	check(panel.is_busy(), "rejection for another request id ignored")
	panel.on_craft_rejected("req-1", "INSUFFICIENT_INVENTORY")
	check(panel.message_text() == "Server: not enough materials", "server error shown, got '%s'" % panel.message_text())
	check(panel.inventory_count("resource.wood") == 9 and panel.inventory_count("tool.wooden-club") == 0, "rejection leaves inventory unchanged")
	check(panel.craft_enabled("tool.wooden-club"), "buttons re-enabled after rejection")
	panel.on_craft_rejected("req-1", "INSUFFICIENT_INVENTORY")
	check(panel.message_text() == "Server: not enough materials" and panel.inventory_count("resource.wood") == 9, "stray rejection with nothing in flight is ignored")

	# ACK handling: uncorrelated / mismatched / malformed ACKs are ignored.
	check(panel.craft("tool.wooden-club"), "second craft sends a fresh request id")
	check(sent[1][0] == "req-2", "fresh request id, not a reuse")
	panel.on_craft_ack("req-1", ack("req-1", "tool.wooden-club", {"resource.wood": 1}))
	check(panel.inventory_count("resource.wood") == 9 and panel.is_busy(), "stale request id ACK ignored")
	panel.on_craft_ack("req-2", ack("req-2", "tool.stone-axe", {"resource.wood": 1}))
	check(panel.inventory_count("resource.wood") == 9 and panel.is_busy(), "ACK for a different recipe ignored")
	panel.on_craft_ack("req-2", {"type": "craft_result", "requestId": "req-2", "recipeId": "tool.wooden-club"})
	check(panel.is_busy(), "ACK without state ignored")
	var crafted: Array = []
	panel.craft_succeeded.connect(func(id: String) -> void: crafted.append(id))
	panel.on_craft_ack("req-2", ack("req-2", "tool.wooden-club", {"resource.wood": 1, "tool.wooden-club": 1}))
	check(crafted == ["tool.wooden-club"], "success signal emitted once")
	check(panel.inventory_count("resource.wood") == 1 and panel.inventory_count("tool.wooden-club") == 1, "inventory comes from the server ACK")
	check(not panel.is_busy() and panel.craft_enabled("tool.wooden-club"), "idle after ACK")
	panel.on_craft_ack("req-2", ack("req-2", "tool.wooden-club", {"resource.wood": 99}))
	check(panel.inventory_count("resource.wood") == 1 and crafted.size() == 1, "replayed ACK is not applied twice")

	# Ambiguous error keeps the request pending; unknown outcome clears it without inventory change.
	check(panel.craft("structure.wooden-wall"), "craft sends")
	panel.on_server_error("RATE_LIMITED")
	check(panel.is_busy(), "unrelated server error keeps request pending")
	panel.on_outcome_unknown("other-id")
	check(panel.is_busy(), "unknown outcome for another request ignored")
	panel.on_outcome_unknown("req-3")
	check(not panel.is_busy() and panel.inventory_count("resource.wood") == 1, "unknown outcome frees the panel, inventory unchanged")
	panel.queue_free()

	# Protocol: craft is a correlated action and craft_result is accepted only for it.
	var protocol = Protocol.new()
	root.add_child(protocol)
	await process_frame
	check(protocol.request_craft("tool.wooden-club") == "", "protocol refuses to send while unauthenticated")
	protocol._pending["abc"] = {"action": "craft", "started_ms": Time.get_ticks_msec()}
	protocol._pending["gat"] = {"action": "gather_resource", "started_ms": Time.get_ticks_msec()}
	var acked: Array = []
	protocol.command_acknowledged.connect(func(id: String, message: Dictionary) -> void: acked.append([id, message.get("type")]))
	protocol._on_message(ack("gat", "tool.wooden-club", {}))
	check(acked.is_empty() and protocol._pending.has("gat"), "craft_result cannot satisfy a gather request")
	protocol._on_message(ack("abc", "tool.wooden-club", {}))
	check(acked == [["abc", "craft_result"]] and not protocol._pending.has("abc"), "craft_result acknowledges the craft request")
	protocol._on_message(ack("abc", "tool.wooden-club", {}))
	check(acked.size() == 1, "duplicate craft_result is not acknowledged twice")
	# Error attribution: resolve a craft only when it is the sole possible owner.
	var rejected: Array = []
	protocol.command_rejected.connect(func(id: String, code: String) -> void: rejected.append([id, code]))
	protocol._pending.clear()
	protocol._pending["c1"] = {"action": "craft", "started_ms": Time.get_ticks_msec()}
	protocol._pending["g1"] = {"action": "gather_resource", "started_ms": Time.get_ticks_msec()}
	protocol._on_message({"type": "error", "code": "INVENTORY_LIMIT"})
	check(rejected.is_empty() and protocol._pending.has("c1"), "inventory error is not attributed to a craft while a gather is pending")
	protocol._on_message({"type": "error", "code": "RECIPE_NOT_FOUND"})
	check(rejected == [["c1", "RECIPE_NOT_FOUND"]] and not protocol._pending.has("c1"), "craft-only error resolves the sole pending craft")
	protocol._pending.erase("g1")
	protocol._on_message({"type": "error", "code": "RATE_LIMITED"})
	check(rejected.size() == 1, "non-craft error never resolves anything")
	# Repeated rejected crafts must not leak pending slots (MAX_PENDING = 8).
	for attempt in range(12):
		protocol._pending["r%d" % attempt] = {"action": "craft", "started_ms": Time.get_ticks_msec()}
		protocol._on_message({"type": "error", "code": "INSUFFICIENT_INVENTORY"})
	check(protocol._pending.is_empty() and rejected.size() == 13, "12 rejected crafts leave no pending slots, got %d" % protocol._pending.size())
	protocol.queue_free()

	# Integration: world mounts the panel and routes server inventory into it.
	var world = WorldScene.instantiate()
	world.begin_authenticated_session("ws://127.0.0.1:9/ws", "test-session")
	root.add_child(world)
	await process_frame
	var mounted = world.get_node_or_null("Interface/Panel/Margin/Content/HudScroll/HudPanels/CraftPanel")
	check(mounted != null, "world HUD contains the craft panel inside the scroll area")
	# Overflow: however long the panels grow, the HUD stays within the viewport.
	var hud_panels = world.get_node_or_null("Interface/Panel/Margin/Content/HudScroll/HudPanels")
	if hud_panels != null:
		for i in range(20):
			var filler := Button.new()
			filler.custom_minimum_size = Vector2(0, 48)
			hud_panels.add_child(filler)
	await process_frame
	await process_frame
	var hud_rect: Rect2 = (world.get_node("Interface/Panel") as Control).get_global_rect()
	var visible_size: Vector2 = root.get_visible_rect().size
	check(hud_rect.end.y <= visible_size.y, "HUD bottom %.0f fits viewport height %.0f" % [hud_rect.end.y, visible_size.y])
	if mounted != null:
		world._on_player_state({"x": 1, "y": 1, "health": 100, "inventory": {"resource.wood": 12}})
		check(mounted.inventory_count("resource.wood") == 12, "player_state inventory reaches the panel")
		check(not mounted.craft("tool.wooden-club"), "unauthenticated world does not send a craft")
		check(mounted.message_text() == "Command window unavailable", "unavailable command shown")
	world.queue_free()
	await process_frame

	if failures > 0:
		push_error("craft panel test: %d failure(s)" % failures)
		print("FAIL craft_panel_test")
		quit(1)
	else:
		print("PASS craft_panel_test")
		quit(0)
