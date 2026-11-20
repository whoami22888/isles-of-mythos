extends SceneTree
## Headless M2: a wave spawns, the player kills them, a building is damaged
## and repaired, crew train and take the field, rewards land.

var scene: Node
var fails := 0
var t := 0.0

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame
		t += 1.0 / 30.0

func _init() -> void:
	call_deferred("run")

func run() -> void:
	for f in ["user://washed_ashore.cfg", "user://outpost.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	scene = load("res://gameplay/outpost/outpost.tscn").instantiate()
	root.add_child(scene)
	await frames(3)
	var st = scene.state
	# Fast-forward an outpost at camp L2 with mill, dock, palisade, barracks.
	for r in st.inv.keys():
		st.inv[r] = 2000
	for k in 200:
		for id in ["mill", "dock", "palisade", "camp", "forge", "watchtower", "barracks"]:
			if st.block_reason(id) == "" and (id != "camp" or st.camp_level < 3):
				st.start(id)
		st.tick(10.0)
	scene._refresh_sites(true)
	check(st.level_of("barracks") >= 1 and st.camp_level >= 2, "outpost built (camp L%d, barracks L%d)" % [st.camp_level, st.level_of("barracks")])
	await frames(2)
	check(scene.raid._armed, "raid director armed after camp L2")
	# Crew.
	check(st.train("sailor") == "", "sailor queued")
	check(st.train("crew_musketeer") == "", "musketeer queued")
	for k in 60 * 30:
		st.tick_crew(1.0 / 30.0) if false else null
	st.tick(25.0)
	st.tick(35.0)
	await frames(3)
	check(scene.raid.crew_alive() == 2, "2 crew fielded at the palisade (%d)" % scene.raid.crew_alive())
	# Raid.
	scene.raid.start_warning()
	check(scene.raid.phase == "warning", "warning phase")
	var w := 0
	while scene.raid.phase != "fight" and w < 120 * 30:
		await frames(1)
		w += 1
	check(scene.raid.phase == "fight" and scene.raid.enemies_alive() == 4, "wave 1 ashore with 4 raiders (%d)" % scene.raid.enemies_alive())
	# Damage + repair a building directly.
	var mill_hp: float = st.max_hp("mill")
	st.damage("mill", mill_hp + 10)
	scene.site_hit("mill")
	check(st.is_damaged("mill"), "mill wrecked at 0 HP")
	var stock0: Dictionary = st.ready_amount("mill").duplicate()
	st.tick(30.0)
	check(st.ready_amount("mill") == stock0, "production paused while wrecked")
	var wood0 := int(st.inv["wood"])
	check(st.repair("mill") and not st.is_damaged("mill") and int(st.inv["wood"]) < wood0, "mill repaired with wood")
	# Player hunts the raiders.
	var guard := 0
	var swings := 0
	while scene.raid.enemies_alive() > 0 and guard < 90 * 30:
		var u: Dictionary = scene.raid.nearest_enemy(scene._player.global_position, 999.0)
		if not u.is_empty():
			var at: Vector3 = u["node"].global_position
			var me: Vector3 = scene._player.global_position
			if me.distance_to(at) > 1.8:
				var np := me.move_toward(at, 5.0 / 30.0)
				np.y = scene.ground_y(np.x, np.z)
				scene._player.global_position = np
			elif scene.strike_enemy():
				swings += 1
		scene.player_hp = maxf(scene.player_hp, 60.0)
		await frames(1)
		guard += 1
	check(scene.raid.enemies_alive() == 0, "wave 1 cleared in %.1fs, %d player hits, %d kills, %d pet bites" % [guard / 30.0, swings, scene.raid.kills, scene.pet_bites])
	await frames(3)
	check(st.waves_done == 1 and int(st.inv.get("gold", 0)) >= 5, "rewards: waves_done=%d gold=%d" % [st.waves_done, int(st.inv.get("gold", 0))])
	check(scene.raid.phase == "idle", "back to idle, next raid in %ds" % int(scene.raid.eta()))
	# Death + respawn.
	scene.raid.start_warning()
	scene.hurt_player(9999, Vector3.ZERO)
	check(not scene.player_alive(), "player can fall")
	await frames(4 * 30)
	check(scene.player_alive() and scene.player_hp == scene.player_max, "respawned at camp with full HP")
	print("OUTPOST RAID: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
