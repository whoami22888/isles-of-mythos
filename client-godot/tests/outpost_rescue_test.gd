extends SceneTree
## Headless M3: bottle after wave 2, raft builds, voyage arrives, the rescue
## fight (2 waves + Captain charge) completes, Silas joins, Harpooner unlocks.

var scene: Node
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _init() -> void:
	call_deferred("run")

func fight(limit: float) -> float:
	var g := 0
	while g < limit * 30:
		if scene.rescue.phase != "island":
			break
		var u: Dictionary = scene.raid.nearest_enemy(scene._player.global_position, 999.0)
		if not u.is_empty():
			var at: Vector3 = u["node"].global_position
			var me: Vector3 = scene._player.global_position
			if me.distance_to(at) > 1.8:
				var np := me.move_toward(at, 4.6 / 30.0)
				np.y = scene.ground_y(np.x, np.z)
				scene._player.global_position = np
			else:
				scene.strike_enemy()
		scene.player_hp = maxf(scene.player_hp, 80.0)
		await frames(1)
		g += 1
	return g / 30.0

func run() -> void:
	for f in ["user://washed_ashore.cfg", "user://outpost.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	scene = load("res://gameplay/outpost/outpost.tscn").instantiate()
	root.add_child(scene)
	await frames(3)
	var st = scene.state
	var rs = scene.rescue
	for r in st.inv.keys():
		st.inv[r] = 2000
	for k in 200:
		for id in ["mill", "dock", "palisade", "camp", "forge", "watchtower", "barracks"]:
			if st.block_reason(id) == "" and (id != "camp" or st.camp_level < 3):
				st.start(id)
		st.tick(10.0)
	scene._refresh_sites(true)
	print("isle landing ", rs.landing, " moor ", rs.moor, " cage ", rs.cage, " water ", scene._water_y)
	check(rs.landing.y > scene._water_y + 0.3 and rs.moor != Vector3.ZERO, "northern isle has a beach landing")
	await frames(2)
	check(rs.phase == "", "no bottle before wave 2")
	st.waves_done = 2
	await frames(2)
	check(rs.phase == "bottle" and rs.bottle.visible, "bottle washed up after wave 2")
	scene.place_player(rs.bottle.global_position + Vector3(0, 0, 1.2))
	await frames(2)
	check(scene._action_text() == "Read the bottle", "action reads the bottle ('%s')" % scene._action_text())
	scene.on_action()
	check(rs.phase == "raft_needed" and st.journal.size() == 1, "bottle read, journal entry")
	scene.stand_at("dock")
	await frames(2)
	check(scene._action_text().begins_with("Build raft"), "dock offers the raft ('%s')" % scene._action_text())
	scene.on_action()
	check(rs.phase == "raft_building", "raft building")
	await frames(42 * 30)
	check(rs.phase == "raft_ready" and rs.raft.visible, "raft built")
	scene.stand_at("dock")
	await frames(2)
	scene.on_action()
	check(rs.phase == "voyage", "set sail")
	var vt := 0
	while rs.phase == "voyage" and vt < 90 * 30:
		await frames(1)
		vt += 1
	check(rs.phase == "island", "voyage arrived in %.1fs (raft at %s)" % [vt / 30.0, rs.raft.global_position])
	if rs.phase != "island":
		rs.arrive()
	var t1 := await fight(120.0)
	check(rs.phase == "prisoners", "stockade fight won in %.1fs (boss charges seen: %s)" % [t1, rs.boss.get("charge_cd", -1)])
	scene.place_player(rs.cage + Vector3(0, 0, 2.5))
	await frames(2)
	print("free action '%s' alive=%s rescue='%s' dist=%.1f" % [scene._action_text(), scene.player_alive(), rs.action_text(), scene._player.global_position.distance_to(rs.cage)])
	scene.on_action()
	check(rs.phase == "freed" and scene._hud.subtitle_count() > 0, "prisoners freed, Silas speaks")
	scene.place_player(rs.landing)
	await frames(2)
	scene.on_action()
	check(rs.phase == "home" and st.silas_joined and rs.silas_npc != null, "home: Silas at the Barracks")
	check(st.crew_slots() == 2 + 2, "Barracks +2 slots (%d)" % st.crew_slots())
	check(st.train("harpooner") == "", "Harpooner unlocked and trainable")
	await frames(8 * 30)
	check(rs.phase == "done" and rs.flag != null, "warship flag cliffhanger")
	print("journal entries: %d" % st.journal.size())
	print("OUTPOST RESCUE: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
