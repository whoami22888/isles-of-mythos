extends Node3D
## Milestone 3: the Silas rescue (Blueprint Act 2).
## bottle -> raft at the Fishing Dock -> voyage across the strait -> stockade
## fight on the northern isle (2 waves + Captain mini-boss with a telegraphed
## charge) -> free Silas and 3 sailors -> home: Silas at the Barracks, +2 crew
## slots, Harpooner unlocked -> warship flag cliffhanger (Chapter 3).

const Art := preload("res://gameplay/opening/opening_art.gd")
const Gear := preload("res://gameplay/outpost/outpost_gear.gd")
const HUT := preload("res://assets/ashore/library/hut_hy3d/hut_hy3d.glb")
const FIRE_PIT := preload("res://assets/ashore/library/stone_fire_pit/stone_fire_pit.glb")
const FLAG := preload("res://assets/opening/kenney/flag-pirate.glb")

var host: Node
var cfg: Dictionary = {}
var phase := ""   # mirrors state.rescue_phase
var bottle: Node3D
var raft: Node3D
var island: Node3D
var island_xf := Transform3D.IDENTITY
var landing := Vector3.ZERO
var moor := Vector3.ZERO
var cage := Vector3.ZERO
var prisoners: Array = []
var silas_npc: Node3D
var flag: Node3D
var arena_wave := 0
var boss: Dictionary = {}
var voyage_t := 0.0
var _heading := 0.0
var _flag_t := -1.0


func setup(data: Dictionary) -> void:
	cfg = data
	_build_island()
	phase = host.state.rescue_phase
	if phase in ["voyage", "island", "prisoners", "freed"]:
		phase = "raft_ready"   # resume safely at the dock after a reload
	_apply_phase_props()


func story(id: String) -> void:
	var beat: Dictionary = cfg.get("story", {}).get(id, {})
	if beat.is_empty():
		return
	var pet: String = host.state.pet_name
	for line in beat.get("lines", []):
		host.subtitle(str(line[0]).replace("{pet}", pet), str(line[1]).replace("{pet}", pet))
	var j := str(beat.get("journal", "")).replace("{pet}", pet)
	if j != "":
		host.state.journal.append({"title": str(beat.get("title", "")), "text": j})


func _set_phase(p: String) -> void:
	phase = p
	host.state.rescue_phase = p
	host.state.save()


# --- Northern isle: the island terrain kit re-laid smaller and turned ---------

func _build_island() -> void:
	var src: MeshInstance3D = host._slice.get_node_or_null("IrregularCoastalTerrain")
	if src == null:
		return
	var row: Dictionary = cfg.get("island2", {})
	island = Node3D.new()
	island.name = "NorthernIsle"
	add_child(island)
	var t := MeshInstance3D.new()
	t.name = "Terrain"
	t.mesh = src.mesh
	t.material_override = src.material_override
	for i in src.get_surface_override_material_count():
		t.set_surface_override_material(i, src.get_surface_override_material(i))
	island.add_child(t)
	var sc := float(row.get("scale", 0.55))
	var basis := Basis(Vector3.UP, deg_to_rad(float(row.get("yaw", 180)))).scaled(Vector3(sc, sc * 0.8, sc))
	island_xf = Transform3D(basis, Vector3(float(row.get("x", -18)), 0, float(row.get("z", -128)))) * src.global_transform
	t.global_transform = island_xf
	host.register_terrain(island_xf)
	# Landing: come in from the open water on the home side (+z) and stop at
	# the first dry sand.
	var c := Vector3(float(row.get("x", -18)), 0, float(row.get("z", -128)))
	var wy: float = host._water_y
	landing = c
	for k in 120:
		var p := c + Vector3(0, 0, 30.0 - k * 0.5)
		var y: float = host.ground_y(p.x, p.z)
		if y > wy + 0.35:
			landing = Vector3(p.x, y, p.z - 1.0)
			landing.y = host.ground_y(landing.x, landing.z)
			moor = Vector3(p.x, wy, p.z + 4.0)
			break
	cage = landing + Vector3(1.5, 0, -7.0)
	cage.y = host.ground_y(cage.x, cage.z)
	_dress_stockade()


func _dress_stockade() -> void:
	var art = host.art
	var root := Node3D.new()
	root.name = "Stockade"
	island.add_child(root)
	root.global_position = cage
	# Ring of stakes around the camp, open toward the beach.
	for i in 22:
		var a := TAU * i / 26.0 + PI * 0.65
		art.post(root, Vector3(cos(a) * 7.5, 0, sin(a) * 7.5), 2.4 + (0.3 if i % 2 == 0 else 0.0), (i % 3 - 1) * 3.0)
	art._piece(root, HUT, Vector3(-4.0, 0, -3.0), 30, 2.6)
	art._piece(root, HUT, Vector3(4.2, 0, -2.6), -25, 2.4)
	art._piece(root, FIRE_PIT, Vector3(0, 0, 2.2), 0, 0.5)
	art._piece(root, Art.CRATE_A, Vector3(-2.0, 0, 3.4), 20, 0.7)
	art._piece(root, Art.BARRELS, Vector3(2.6, 0, 3.2), 0, 1.0)
	# The cage: tight stakes around the prisoners.
	for i in 12:
		var a2 := TAU * i / 12.0
		art.post(root, Vector3(cos(a2) * 1.7, 0, -1.0 + sin(a2) * 1.7), 2.0, 0.0)
	var flag_post: Node3D = art.post(root, Vector3(0, 0, -5.5), 4.5)
	var f := Art.spawn(FLAG)
	root.add_child(f)
	Art.fit_height(f, 1.4)
	f.global_position = flag_post.global_position + Vector3(0, 4.0, 0)
	var kinds := ["silas", "prisoner", "prisoner", "prisoner"]
	for i in kinds.size():
		var u: Dictionary = host.raid.spawn(kinds[i], "prisoner", cage + Vector3((i % 2 - 0.5) * 1.0, 0, -1.0 + (i / 2 - 0.5) * 1.0))
		Art.play(u["rig"], "Kneel")
		u["node"].look_at(u["node"].global_position + Vector3(0, 0, 1), Vector3.UP)
		prisoners.append(u)


func _apply_phase_props() -> void:
	var b: Dictionary = cfg.get("bottle", {"x": 7, "z": 1.6})
	if bottle == null:
		bottle = Node3D.new()
		bottle.name = "Bottle"
		add_child(bottle)
		var m := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.025
		cyl.bottom_radius = 0.06
		cyl.height = 0.3
		m.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.42, 0.3, 0.75)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.15
		mat.metallic_specular = 0.8
		m.material_override = mat
		m.rotation_degrees = Vector3(0, 30, 80)
		bottle.add_child(m)
		bottle.global_position = Vector3(float(b["x"]), host.ground_y(float(b["x"]), float(b["z"])) + 0.06, float(b["z"]))
	bottle.visible = phase == "bottle"
	if raft == null:
		raft = _build_raft()
	raft.visible = phase in ["raft_ready", "voyage", "island", "prisoners", "freed"]
	if raft.visible and phase == "raft_ready":
		raft.global_position = dock_water()
	if host.state.silas_joined and silas_npc == null:
		_spawn_silas_npc()


func dock_water() -> Vector3:
	var d: Vector3 = host.site_pos("dock") + Vector3(0, 0, -6.5)
	d.y = host._water_y
	return d


func _build_raft() -> Node3D:
	var art = host.art
	var r := Node3D.new()
	r.name = "Raft"
	add_child(r)
	for i in 5:
		var log := Art.spawn(Art.DRIFT_TRUNK)
		r.add_child(log)
		var b := Art.world_aabb(log)
		if b.size.z > b.size.x:
			log.rotation_degrees.y = 90
		Art.fit_height(log, 0.32)
		var b2 := Art.world_aabb(log)
		log.scale *= 3.0 / maxf(maxf(b2.size.x, b2.size.z), 0.01)
		log.position = Vector3(0, 0, (i - 2) * 0.36)
	var mast := Node3D.new()
	r.add_child(mast)
	var pole := Gear._cyl(mast, 0.05, 0.06, 3.0, _wood_mat())
	pole.position.y = 1.5
	var sail := Art.spawn(Art.TORN_SAIL)
	mast.add_child(sail)
	# The torn sail mesh lies flat and wide: fit its largest extent, not height.
	var sb := Art.world_aabb(sail)
	sail.scale *= 1.8 / maxf(maxf(sb.size.x, sb.size.y), maxf(sb.size.z, 0.01))
	if sb.size.y < maxf(sb.size.x, sb.size.z) * 0.5:
		sail.rotation_degrees.x = 90
	sail.position = Vector3(0, 1.8, 0.08)
	return r


func _wood_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.25, 0.16)
	m.roughness = 0.85
	return m


# --- Flow -----------------------------------------------------------------------

func controls_player() -> bool:
	return phase == "voyage"


func action_text() -> String:
	var p: Vector3 = host._player.global_position
	match phase:
		"bottle":
			if p.distance_to(bottle.global_position) < 2.4:
				return "Read the bottle"
		"raft_needed":
			if p.distance_to(host.site_pos("dock")) < 5.0:
				var c: Dictionary = cfg.get("raft", {}).get("cost", {})
				return "Build raft (%s)" % host.State.cost_text(c)
		"raft_ready":
			if p.distance_to(host.site_pos("dock")) < 5.5:
				return "Set sail"
		"prisoners":
			if p.distance_to(cage) < 3.5:
				return "Free the prisoners"
		"freed":
			if p.distance_to(landing) < 5.0:
				return "Sail home"
	return ""


func on_action() -> bool:
	var txt := action_text()
	if txt == "":
		return false
	match phase:
		"bottle":
			read_bottle()
		"raft_needed":
			build_raft()
		"raft_ready":
			set_sail()
		"prisoners":
			free_prisoners()
		"freed":
			sail_home()
	return true


func read_bottle() -> void:
	story("bottle")
	_set_phase("raft_needed")
	_apply_phase_props()
	host.banner("Silas is alive!", "Build a raft at the Fishing Dock")


func build_raft() -> bool:
	var st = host.state
	var c: Dictionary = cfg.get("raft", {}).get("cost", {})
	if not st.affordable(c):
		host._toast("Raft needs " + host.State.cost_text(st.missing(c)))
		return false
	for k in c.keys():
		st.inv[k] = int(st.inv.get(k, 0)) - int(c[k])
	st.raft_left = float(cfg.get("raft", {}).get("seconds", 40))
	_set_phase("raft_building")
	story("raft")
	return true


func set_sail() -> void:
	_set_phase("voyage")
	voyage_t = 0.0
	raft.global_position = dock_water()
	_heading = atan2(moor.x - raft.global_position.x, moor.z - raft.global_position.z)
	host.raid.hold = true
	story("voyage")


func arrive() -> void:
	_set_phase("island")
	host.respawn_override = landing + Vector3(0, 0, -1.5)
	raft.global_position = moor
	host.place_player(landing + Vector3(0, 0, -1.0))
	host.raid.arena = true
	arena_wave = 0
	story("stockade")
	_next_arena_wave()


func _next_arena_wave() -> void:
	var waves: Array = cfg.get("waves", [])
	if arena_wave < waves.size():
		var row: Dictionary = waves[arena_wave]
		arena_wave += 1
		var i := 0
		for kind in ["deckhand", "musketeer", "brute"]:
			for k in int(row.get(kind, 0)):
				host.raid.spawn(kind, "enemy", cage + Vector3((i - 1.5) * 1.4, 0, 4.0))
				i += 1
		host.banner("The stockade fights back", "Wave %d of %d" % [arena_wave, waves.size()])
	elif boss.is_empty():
		arena_wave += 1
		var b: Dictionary = cfg.get("boss", {})
		boss = host.raid.spawn(str(b.get("kind", "captain")), "enemy", cage + Vector3(0, 0, 3.0))
		boss["hp"] = float(b.get("hp", 500))
		boss["max"] = boss["hp"]
		boss["boss"] = b
		boss["charge_cd"] = 3.0
		host.banner("The UTC Captain", "Watch for his charge")
	else:
		_set_phase("prisoners")
		host.raid.arena = false
		host.banner("The stockade is ours", "Free the prisoners")


func free_prisoners() -> void:
	for u in prisoners:
		Art.play(u["rig"], "Idle")
	story("freed")
	_set_phase("freed")


func sail_home() -> void:
	# Return leg is a short cut (the outbound voyage is the playable one).
	for u in prisoners:
		if is_instance_valid(u["node"]):
			u["node"].queue_free()
	host.raid.units = host.raid.units.filter(func(u): return u["team"] != "prisoner")
	prisoners.clear()
	host.respawn_override = Vector3.INF
	host.raid.hold = false
	raft.global_position = dock_water()
	host.place_player(host.site_pos("dock") + Vector3(0, 0, 2.5))
	host.state.silas_joined = true
	_spawn_silas_npc()
	_set_phase("home")
	story("home")
	host.banner("The crew is home", "Barracks +%d crew slots  ·  Harpooner unlocked" % int(cfg.get("harpooner_slots", 2)))
	_flag_t = 7.0


func _spawn_silas_npc() -> void:
	var at: Vector3 = host.site_pos("barracks") + Vector3(1.5, 0, -3.0)
	var u: Dictionary = host.raid.spawn("silas", "npc", at)
	silas_npc = u["node"]
	silas_npc.look_at(silas_npc.global_position + Vector3(0, 0, -1), Vector3.UP)
	var lab: Label3D = host.art.label(silas_npc, "Quartermaster Silas", 2.2, host._font)
	lab.visible = true


func _cliffhanger() -> void:
	flag = Node3D.new()
	flag.name = "WarshipFlag"
	add_child(flag)
	var mast := Gear._cyl(flag, 0.12, 0.16, 9.0, _wood_mat())
	mast.position.y = 4.5
	var f := Art.spawn(FLAG)
	flag.add_child(f)
	Art.fit_height(f, 3.2)
	f.position = Vector3(0, 8.0, 0)
	flag.global_position = Vector3(30.0, host._water_y - 2.0, -150.0)
	story("flag")
	host.banner("Chapter 3: Flag & Fortress", "A Company warship is coming")
	_set_phase("done")


func _process(delta: float) -> void:
	var st = host.state
	match phase:
		"":
			if st.waves_done >= int(cfg.get("bottle_after_waves", 2)) and host.raid.phase == "idle":
				_set_phase("bottle")
				_apply_phase_props()
				host.banner("Something on the tide", "A bottle washed up on the beach")
		"raft_building":
			st.raft_left -= delta
			if st.raft_left <= 0.0:
				st.raft_left = -1.0
				_set_phase("raft_ready")
				_apply_phase_props()
				host._toast("The raft is ready at the dock")
		"voyage":
			_sail(delta)
		"island":
			if host.raid.enemies_alive() == 0:
				_next_arena_wave()
			if not boss.is_empty():
				_boss_tick(delta)
		"home":
			if _flag_t > 0.0:
				_flag_t -= delta
				if _flag_t <= 0.0:
					_cliffhanger()


## Joystick steers the raft (left/right turns, push to row harder); it always
## drifts forward so the crossing takes ~30-45 s.
func _sail(delta: float) -> void:
	voyage_t += delta
	var stick: Vector2 = host._hud.stick() if host._hud else Vector2.ZERO
	_heading -= stick.x * 1.1 * delta
	var speed := float(cfg.get("raft_speed", 3.6)) * (1.0 + 0.35 * clampf(-stick.y, 0.0, 1.0))
	var fwd := Vector3(sin(_heading), 0, cos(_heading))
	var p := raft.global_position + fwd * speed * delta
	if host.ground_y(p.x, p.z) > host._water_y - 0.3 and p.distance_to(moor) > 8.0:
		p = raft.global_position   # beached on a sandbar: steer off
	p.y = host._water_y + 0.05 + sin(voyage_t * 1.7) * 0.06
	raft.global_position = p
	raft.rotation = Vector3(sin(voyage_t * 1.3) * 0.04, _heading, sin(voyage_t * 0.9) * 0.05)
	host.place_player(p + Vector3(0, 0.25, 0), false)
	host._cam_yaw = lerp_angle(host._cam_yaw, _heading + PI, clampf(delta * 1.5, 0.0, 1.0))
	if p.distance_to(moor) < 7.0:
		arrive()


## The Captain's charge: a long ground telegraph toward you, then a rush.
func _boss_tick(delta: float) -> void:
	if float(boss["dead"]) >= 0.0:
		return
	var b: Dictionary = boss["boss"]
	var node: Node3D = boss["node"]
	if boss.has("charge_t"):
		boss["charge_t"] = float(boss["charge_t"]) - delta
		var dir: Vector3 = boss["charge_dir"]
		if float(boss["charge_t"]) > float(b.get("charge_time", 0.7)):
			return   # winding up (telegraph showing)
		var p := node.global_position + dir * float(b.get("charge_speed", 11.0)) * delta
		p.y = host.ground_y(p.x, p.z)
		node.global_position = p
		Art.play(boss["rig"], "Run")
		if not bool(boss.get("charge_hit", false)) and p.distance_to(host._player.global_position) < 1.3:
			boss["charge_hit"] = true
			host.hurt_player(float(b.get("charge_damage", 32)), p - dir)
			host.knock_player(dir * 4.0)
		if float(boss["charge_t"]) <= 0.0:
			boss.erase("charge_t")
			boss["stun"] = 0.6
			if boss.has("lane") and is_instance_valid(boss["lane"]):
				boss["lane"].queue_free()
		return
	boss["charge_cd"] = float(boss["charge_cd"]) - delta
	var to: Vector3 = host._player.global_position - node.global_position
	to.y = 0
	if float(boss["charge_cd"]) <= 0.0 and to.length() > 3.0 and to.length() < 11.0 and host.player_alive():
		boss["charge_cd"] = float(b.get("charge_every", 6.5))
		boss["charge_dir"] = to.normalized()
		boss["charge_t"] = float(b.get("charge_windup", 1.0)) + float(b.get("charge_time", 0.7))
		boss["charge_hit"] = false
		boss["stun"] = float(b.get("charge_windup", 1.0)) + float(b.get("charge_time", 0.7))
		node.look_at(node.global_position + to, Vector3.UP)
		Art.play(boss["rig"], "SwordIdle", 0.1)
		boss["lane"] = _lane(node.global_position, to.normalized(), float(b.get("charge_speed", 11.0)) * float(b.get("charge_time", 0.7)))
		host.banner("", "The Captain lowers his shoulder!")


func _lane(from: Vector3, dir: Vector3, length: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(1.4, length)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.08, 0.06, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	var mid := from + dir * length * 0.5
	mid.y = host.ground_y(mid.x, mid.z) + 0.08
	m.global_position = mid
	m.rotation.y = atan2(dir.x, dir.z)
	return m
