extends SceneTree

## Guild objectives HUD: server progress and eligibility only, single-flight claim,
## the personal-contribution hint, and a 409 re-reads the server.
const GuildPanel = preload("res://gameplay/guild_objectives_panel.gd")
const WorldScene = preload("res://gameplay/vertical_slice.tscn")

var failures := 0
var sent: Array = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		push_error("guild objectives test failed: " + label)
		failures += 1

func record(method: int, path: String, body: Variant) -> void:
	sent.append({"method": method, "path": path, "body": body})

func listing(progress: int, mine: int, claimed: bool, in_guild: bool = true) -> Dictionary:
	return {
		"weekStart": "2026-11-02",
		"guildId": "g1" if in_guild else null,
		"objectives": [{"objectiveId": "guild.wood", "itemId": "resource.wood", "target": 200, "guildProgress": progress, "myContribution": mine, "minContribution": 10, "complete": progress >= 200, "eligible": progress >= 200 and mine >= 10, "claimed": claimed, "rewardGold": "30"}] if in_guild else [],
	}

func run() -> void:
	var panel = GuildPanel.new()
	panel.request_sender = record
	root.add_child(panel)
	await process_frame

	check(not panel.refresh(true), "unconfigured panel sends nothing")
	panel.configure("http://127.0.0.1:3000", "player-access-token")
	check(panel.refresh(true) and sent[0]["path"] == "/guild-objectives", "GET /guild-objectives")
	panel.on_list_response(200, listing(0, 0, false, false))
	check(panel.get_child(0).text == "Guild objectives (join a guild)", "no guild shown")

	panel.on_list_response(200, listing(200, 4, false))
	check(panel.row_text("guild.wood") == "Guild wood 200/200 · you 4 (add 6 more yourself)", "contribution hint, got '%s'" % panel.row_text("guild.wood"))
	check(not panel.claim_enabled("guild.wood") and not panel.claim("guild.wood"), "not eligible without own contribution")

	panel.on_list_response(200, listing(120, 12, false))
	check(panel.row_text("guild.wood") == "Guild wood 120/200 · you 12 (+30 gold)", "progress from server, got '%s'" % panel.row_text("guild.wood"))
	check(not panel.claim("guild.wood"), "incomplete guild objective cannot be claimed")

	panel.on_list_response(200, listing(200, 12, false))
	sent.clear()
	check(panel.claim("guild.wood") and sent[0]["path"] == "/guild-objectives/claim" and sent[0]["body"] == {"objectiveId": "guild.wood"}, "claim body is only the objective id")
	check(not panel.claim_enabled("guild.wood") and not panel.claim("guild.wood"), "single flight")
	var paid: Array = []
	panel.reward_claimed.connect(func(id: String, gold: String) -> void: paid.append([id, gold]))
	panel.on_claim_response(200, {"objectiveId": "guild.wood", "rewardGold": "30", "replayed": false})
	check(paid == [["guild.wood", "30"]], "reward signal carries the server amount")
	check(panel.row_text("guild.wood").ends_with("(claimed)") and not panel.claim("guild.wood"), "claimed state is final")

	# Server refuses (e.g. member left the guild): nothing paid, authoritative re-read.
	panel.on_list_response(200, listing(200, 12, false))
	sent.clear()
	panel.claim("guild.wood")
	panel.on_claim_response(409, {"error": "GUILD_MEMBERSHIP_REQUIRED"})
	check(paid.size() == 1 and sent.size() == 2 and sent[1]["path"] == "/guild-objectives", "409 pays nothing and re-reads")
	panel.on_list_response(500, null)
	check(panel.get_child(0).text == "Guild objectives (unavailable)", "server error shown, no crash")
	panel.queue_free()

	var world = WorldScene.instantiate()
	world.begin_authenticated_session("ws://127.0.0.1:9/ws", "test-session")
	root.add_child(world)
	await process_frame
	check(world.get_node_or_null("Interface/Panel/Margin/Content/GuildObjectives") != null, "world HUD contains the guild objectives panel")
	world.queue_free()
	await process_frame
	print("Guild objectives panel: %d failures" % failures)
	quit(1 if failures > 0 else 0)
