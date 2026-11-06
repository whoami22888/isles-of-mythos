extends SceneTree

## Daily objectives HUD: server-reported progress only, one claim at a time,
## no claim for incomplete/claimed objectives, and a 409 re-reads server state.
const ObjectivesPanel = preload("res://gameplay/daily_objectives_panel.gd")
const WorldScene = preload("res://gameplay/vertical_slice.tscn")

var failures := 0
var sent: Array = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		push_error("daily objectives test failed: " + label)
		failures += 1

func record(method: int, path: String, body: Variant) -> void:
	sent.append({"method": method, "path": path, "body": body})

func listing(wood_progress: int, wood_claimed: bool) -> Dictionary:
	return {"day": "2026-11-05", "objectives": [
		{"objectiveId": "gather.wood", "kind": "gather", "target": 10, "progress": wood_progress, "complete": wood_progress >= 10, "claimed": wood_claimed, "rewardGold": "50"},
		{"objectiveId": "craft.any", "kind": "craft", "target": 2, "progress": 0, "complete": false, "claimed": false, "rewardGold": "60"},
		{"objectiveId": "unknown.thing", "kind": "gather", "target": 1, "progress": 1, "complete": true, "claimed": false, "rewardGold": "9999"},
	]}

func run() -> void:
	var panel = ObjectivesPanel.new()
	panel.request_sender = record
	root.add_child(panel)
	await process_frame

	check(not panel.refresh(true), "unconfigured panel sends nothing")
	check(sent.is_empty(), "no request before configure")
	panel.configure("http://127.0.0.1:3000", "player-access-token")
	check(panel.refresh(true), "configured panel requests the server list")
	check(sent.size() == 1 and sent[0]["path"] == "/daily-objectives" and sent[0]["method"] == HTTPClient.METHOD_GET, "GET /daily-objectives")
	check(not panel.refresh(true), "no second list request while one is in flight")

	panel.on_list_response(200, listing(4, false))
	check(panel.row_text("gather.wood") == "Gather wood 4/10 (+50 gold)", "server progress rendered, got '%s'" % panel.row_text("gather.wood"))
	check(not panel.claim_enabled("gather.wood"), "incomplete objective cannot be claimed")
	check(not panel.claim("gather.wood"), "claim() refuses an incomplete objective")
	check(panel.row_text("unknown.thing") == "", "unknown server objective ids are not rendered")
	check(not panel.refresh(), "rate-bounded refresh within the interval")

	panel.on_list_response(200, listing(10, false))
	check(panel.claim_enabled("gather.wood"), "complete objective can be claimed")
	sent.clear()
	check(panel.claim("gather.wood"), "claim sends")
	check(sent.size() == 1 and sent[0]["path"] == "/daily-objectives/claim" and sent[0]["body"] == {"objectiveId": "gather.wood"}, "POST claim body is only the objective id")
	check(not panel.claim_enabled("gather.wood"), "button disabled while claim is in flight")
	check(not panel.claim("gather.wood"), "no double submit while in flight")
	var paid: Array = []
	panel.reward_claimed.connect(func(id: String, gold: String) -> void: paid.append([id, gold]))
	panel.on_claim_response("gather.wood", 200, {"objectiveId": "gather.wood", "rewardGold": "50", "replayed": false})
	check(paid == [["gather.wood", "50"]], "reward signal carries the server amount")
	check(panel.row_text("gather.wood") == "Gather wood 10/10 (claimed)", "claimed state rendered")
	check(not panel.claim("gather.wood"), "claimed objective cannot be claimed again")

	# Server says not complete (e.g. stale view): re-read instead of trusting the client.
	panel.on_list_response(200, {"objectives": [{"objectiveId": "craft.any", "target": 2, "progress": 2, "complete": true, "claimed": false, "rewardGold": "60"}]})
	sent.clear()
	check(panel.claim("craft.any"), "craft claim sends")
	panel.on_claim_response("craft.any", 409, {"error": "DAILY_OBJECTIVE_INCOMPLETE"})
	check(sent.size() == 2 and sent[1]["path"] == "/daily-objectives", "409 triggers an authoritative re-read")
	check(paid.size() == 1, "409 pays nothing")
	panel.on_list_response(500, null)
	check(panel.get_child(0).text == "Daily objectives (unavailable)", "server error shown, no crash")
	panel.queue_free()

	# Integration: the world scene mounts the panel inside its HUD.
	var world = WorldScene.instantiate()
	world.begin_authenticated_session("ws://127.0.0.1:9/ws", "test-session")
	root.add_child(world)
	await process_frame
	check(world.get_node_or_null("Interface/Panel/Margin/Content/HudScroll/HudPanels/DailyObjectives") != null, "world HUD contains the daily objectives panel")
	world.queue_free()
	await process_frame

	print("Daily objectives panel: %d failures" % failures)
	quit(1 if failures > 0 else 0)
