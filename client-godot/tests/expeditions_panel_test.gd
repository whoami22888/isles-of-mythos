extends SceneTree

## Expeditions HUD: server lists drive the UI, one action in flight, no collect
## before the server's return time, and every action re-reads the server.
const ExpPanel = preload("res://gameplay/expeditions_panel.gd")
const WorldScene = preload("res://gameplay/vertical_slice.tscn")

var failures := 0
var sent: Array = []
var now := 1_780_000_000.0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		push_error("expeditions test failed: " + label)
		failures += 1

func record(method: int, path: String, body: Variant) -> void:
	sent.append({"method": method, "path": path, "body": body})

func iso(unix: float) -> String:
	return Time.get_datetime_string_from_unix_time(int(unix)) + ".000Z"

func listing(ship_status: String, expeditions: Array) -> Dictionary:
	return {
		"routes": [{"routeId": "reef.short", "durationSeconds": 120, "items": {"resource.wood": 6}, "gold": "20"}],
		"ships": [{"shipId": "11111111-1111-1111-1111-111111111111", "name": "Tide Runner", "status": ship_status}],
		"expeditions": expeditions,
	}

func run() -> void:
	var panel = ExpPanel.new()
	panel.request_sender = record
	panel.clock = func() -> float: return now
	root.add_child(panel)
	await process_frame

	check(not panel.refresh(), "unconfigured panel sends nothing")
	panel.configure("http://127.0.0.1:3000", "player-access-token")
	check(panel.refresh() and sent.size() == 1 and sent[0]["path"] == "/expeditions", "GET /expeditions")
	panel.on_list_response(200, listing("active", []))
	check(panel.row_text("route:reef.short") == "reef.short · 120s · +20 gold", "route rendered from server, got '%s'" % panel.row_text("route:reef.short"))
	check(panel.button_enabled("route:reef.short"), "free ship can sail")
	check(not panel.start("moon.trip"), "unknown route refused client-side")

	sent.clear()
	check(panel.start("reef.short"), "start sends")
	var body: Dictionary = sent[0]["body"]
	check(sent[0]["path"] == "/expeditions/start" and body["shipId"] == "11111111-1111-1111-1111-111111111111" and body["routeId"] == "reef.short", "start body carries ship and route")
	check(str(body["requestId"]).begins_with("exp-") and str(body["requestId"]).length() >= 8 and not body.has("durationSeconds"), "fresh request id, no client duration")
	check(not panel.start("reef.short"), "no second action while one is in flight")
	check(not panel.button_enabled("route:reef.short"), "sail disabled while in flight")
	panel.on_action_response(200, {"expeditionId": "e1"})
	check(sent.size() == 2 and sent[1]["path"] == "/expeditions", "start re-reads the server")

	var exp := {"expeditionId": "e1", "routeId": "reef.short", "startedAt": iso(now), "returnsAt": iso(now + 120), "collectedAt": null, "reward": {"items": {"resource.wood": 6}, "gold": "20"}}
	panel.on_list_response(200, listing("docked", [exp]))
	check(not panel.button_enabled("route:reef.short"), "docked ship cannot sail again")
	check(panel.row_text("exp:e1") == "reef.short · 120s left", "countdown from server returnsAt, got '%s'" % panel.row_text("exp:e1"))
	check(not panel.can_collect("e1") and not panel.collect("e1"), "no collect before return")

	now += 121
	panel.tick()
	check(panel.row_text("exp:e1") == "reef.short · returned", "returned state after server time passes")
	sent.clear()
	var paid: Array = []
	panel.expedition_collected.connect(func(id: String, gold: String) -> void: paid.append([id, gold]))
	check(panel.collect("e1") and sent[0]["body"] == {"expeditionId": "e1"}, "collect body is only the expedition id")
	check(not panel.collect("e1"), "no double collect while in flight")
	panel.on_action_response(200, {"expeditionId": "e1", "reward": {"items": {"resource.wood": 6}, "gold": "20"}, "replayed": false})
	check(paid == [["e1", "20"]], "collected signal carries the server reward")
	check(sent.size() == 2 and sent[1]["path"] == "/expeditions", "collect re-reads the server")
	exp["collectedAt"] = iso(now)
	panel.on_list_response(200, listing("active", [exp]))
	check(panel.row_text("exp:e1") == "", "collected expedition leaves the list")
	check(panel.button_enabled("route:reef.short"), "ship can sail again")

	# Server refuses (e.g. 409 early): nothing paid, authoritative re-read.
	var exp2 := {"expeditionId": "e2", "routeId": "reef.short", "returnsAt": iso(now - 1), "collectedAt": null}
	panel.on_list_response(200, listing("docked", [exp2]))
	sent.clear()
	panel.collect("e2")
	panel.on_action_response(409, {"error": "EXPEDITION_IN_PROGRESS"})
	check(paid.size() == 1 and sent.size() == 2 and sent[1]["path"] == "/expeditions", "409 pays nothing and re-reads")
	panel.on_list_response(500, null)
	check(panel.get_child(0).text == "Expeditions (unavailable)", "server error shown, no crash")
	panel.queue_free()

	var world = WorldScene.instantiate()
	world.begin_authenticated_session("ws://127.0.0.1:9/ws", "test-session")
	root.add_child(world)
	await process_frame
	check(world.get_node_or_null("Interface/Panel/Margin/Content/Expeditions") != null, "world HUD contains the expeditions panel")
	world.queue_free()
	await process_frame
	print("Expeditions panel: %d failures" % failures)
	quit(1 if failures > 0 else 0)
