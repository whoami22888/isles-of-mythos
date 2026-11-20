extends Node3D
## Milestone 2 raid director: UTC privateer longboat raids on the outpost.
## Warning -> longboat lands -> wave of privateers -> fight -> rewards.
## Also owns the trained crew and the pet's bites. Cheap AI: straight-line
## steering on the terrain, one target per unit, re-picked every 0.5 s.
## Caps: 8 enemies + 6 crew (data milestone2.max_enemies / max_crew).

signal wave_started(n: int)
signal wave_cleared(n: int, loot: Dictionary)

const Art := preload("res://gameplay/opening/opening_art.gd")
const Gear := preload("res://gameplay/outpost/outpost_gear.gd")
const HIT := preload("res://assets/opening/audio/hit.ogg")
const SWING := preload("res://assets/opening/audio/swing.ogg")
const CHEER := preload("res://assets/opening/audio/cheer.ogg")
const SHOT := preload("res://assets/opening/audio/explosion.ogg")

var host: Node   # outpost.gd
var cfg: Dictionary = {}
var phase := "idle"   # idle | warning | landing | fight
var timer := 0.0      # countdown to the next raid (idle) or warning end
var wave := 0
## Each unit: {kind, team ("enemy"|"crew"), node, rig, hp, max, cd, stun, kb (Vector3),
##  target (Node3D or ""), retarget, dead (float), flash}
var units: Array = []
var shots: Array = []
var boat: Node3D
var _sfx: Array = []
var _retarget := 0.0
var _armed := false
var kills := 0
var freeze := 0.0


func setup(data: Dictionary) -> void:
	cfg = data
	timer = float(cfg.get("raid_interval", 180))
	for i in 3:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)


func _play(stream: AudioStream, db: float = -6.0, pitch: float = 1.0) -> void:
	for p in _sfx:
		if not p.playing:
			p.stream = stream
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return


## Low ship's horn, synthesised (no asset needed).
func _horn() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 1.6)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := minf(t / 0.15, 1.0) * minf((1.6 - t) / 0.4, 1.0)
		var v := 0.0
		for h in [1.0, 2.0, 3.0, 4.0]:
			v += sin(TAU * 98.0 * h * t + 0.3 * sin(TAU * 5.0 * t)) / h
		bytes.encode_s16(i * 2, int(clampf(v * 0.35 * env, -1.0, 1.0) * 30000))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = bytes
	return w


func unit_row(kind: String) -> Dictionary:
	return cfg.get("units", {}).get(kind, {})


func enemies_alive() -> int:
	var n := 0
	for u in units:
		if u["team"] == "enemy" and float(u["dead"]) < 0.0:
			n += 1
	return n


func crew_alive() -> int:
	var n := 0
	for u in units:
		if u["team"] == "crew" and float(u["dead"]) < 0.0:
			n += 1
	return n


func active() -> bool:
	return phase != "idle"


## Seconds until the next raid while idle (for the HUD), else 0.
func eta() -> float:
	return timer if phase == "idle" and _armed else 0.0


# --- Director ---------------------------------------------------------------

func _process(delta: float) -> void:
	if freeze > 0.0:
		freeze -= delta
		return
	var st = host.state
	if not _armed and st.camp_level >= int(cfg.get("first_raid_after_camp_level", 2)):
		_armed = true
		timer = float(cfg.get("raid_interval", 180))
	match phase:
		"idle":
			if _armed:
				timer -= delta
				if timer <= 0.0:
					start_warning()
		"warning":
			timer -= delta
			if timer <= 0.0:
				_land()
		"landing":
			timer -= delta
			if boat:
				boat.global_position = boat.global_position.lerp(_boat_beach(), clampf(delta * 1.2, 0.0, 1.0))
			if timer <= 0.0:
				_spawn_wave()
		"fight":
			if enemies_alive() == 0:
				_victory()
	_field_crew()
	_tick_units(delta)
	_tick_shots(delta)


func start_warning() -> void:
	if phase != "idle":
		return
	phase = "warning"
	timer = float(cfg.get("warning_seconds", 8)) + float(host.state.warning_seconds())
	_play(_horn(), -3.0)
	host.banner("Sails on the horizon!", "UTC privateers  ·  wave %d  ·  landing in %ds" % [wave + 1, int(timer)])
	boat = Node3D.new()
	boat.name = "Longboat"
	add_child(boat)
	var hull := Art.spawn(Art.HULL_STERN)
	boat.add_child(hull)
	Art.fit_height(hull, 1.6)
	var b := Art.world_aabb(hull)
	if maxf(b.size.x, b.size.z) > 6.0:
		hull.scale *= 6.0 / maxf(b.size.x, b.size.z)
	boat.global_position = _boat_beach() + Vector3(0, 0, -16)
	boat.global_position.y = float(host._water_y) - 0.4


func _boat_beach() -> Vector3:
	var p: Dictionary = cfg.get("boat", {"x": 11, "z": -2})
	return Vector3(float(p["x"]), float(host._water_y) - 0.4, float(p["z"]))


func _land() -> void:
	phase = "landing"
	timer = 2.5


func _spawn_wave() -> void:
	wave += 1
	phase = "fight"
	var rows: Array = cfg.get("waves", [])
	var row: Dictionary = rows[clampi(wave - 1, 0, rows.size() - 1)]
	var scale_hp := 1.0 + float(cfg.get("wave_hp_scale", 0.1)) * maxi(wave - rows.size(), 0)
	var land: Dictionary = cfg.get("landing", {"x": 11, "z": 1})
	var i := 0
	for kind in ["deckhand", "musketeer", "brute", "captain"]:
		for k in int(row.get(kind, 0)):
			if enemies_alive() >= int(cfg.get("max_enemies", 8)):
				break
			var at := Vector3(float(land["x"]) + (i % 4 - 1.5) * 1.3, 0, float(land["z"]) + (i / 4) * -1.0)
			spawn(kind, "enemy", at, scale_hp)
			i += 1
	wave_started.emit(wave)
	host.banner("Privateers ashore!", "Wave %d  ·  %d raiders" % [wave, i])


func _victory() -> void:
	phase = "idle"
	timer = float(cfg.get("raid_interval", 180))
	var st = host.state
	st.waves_done = wave
	var rewards: Array = cfg.get("rewards", [])
	var loot: Dictionary = (rewards[clampi(wave - 1, 0, rewards.size() - 1)] as Dictionary).duplicate()
	for k in loot.keys():
		if k == "relic_shard":
			st.relics += int(loot[k])
		else:
			st.inv[k] = int(st.inv.get(k, 0)) + int(loot[k])
	_play(CHEER, -4.0)
	host.banner("Victory!", "Wave %d repelled  ·  %s" % [wave, st.cost_text(loot)])
	host.fly_from_world(host._player.global_position + Vector3.UP * 2.0, _no_relic(loot))
	if boat:
		boat.queue_free()
		boat = null
	for u in units:
		if u["team"] == "enemy" and is_instance_valid(u["node"]):
			u["node"].queue_free()
	units = units.filter(func(u): return u["team"] != "enemy")
	wave_cleared.emit(wave, loot)
	st.save()


func _no_relic(d: Dictionary) -> Dictionary:
	var o := d.duplicate()
	o.erase("relic_shard")
	return o


# --- Units ------------------------------------------------------------------

func spawn(kind: String, team: String, at: Vector3, hp_scale: float = 1.0) -> Dictionary:
	var row := unit_row(kind)
	var node := Node3D.new()
	node.name = "%s_%s_%d" % [team, kind, units.size()]
	add_child(node)
	at.y = float(host.ground_y(at.x, at.z))
	node.global_position = at
	var sc: Array = row.get("shirt", [0.5, 0.5, 0.5])
	var rig := Art.castaway(Color(float(sc[0]), float(sc[1]), float(sc[2])))
	node.add_child(rig)
	Art.fit_height(rig, 1.78 * float(row.get("scale", 1.0)))
	if str(row.get("weapon", "")) == "cutlass":
		Art.arm_with_cutlass(rig)
	var height := 1.78 * float(row.get("scale", 1.0))
	var gun: Node3D = null
	if bool(row.get("ranged", false)):
		gun = Gear.musket(node, height)
	if str(row.get("hat", "")) == "tricorn":
		Gear.tricorn(rig)
	# Darken skin/trousers slightly per faction so crew and raiders read apart.
	var hpv := float(row.get("hp", 50)) * hp_scale
	var u := {"kind": kind, "team": team, "node": node, "rig": rig, "hp": hpv, "max": hpv, "cd": randf_range(0.8, 1.6),
		"stun": 0.0, "kb": Vector3.ZERO, "target": null, "tid": "", "dead": -1.0, "flash": 0.0, "home": at, "wind": 0.0, "gun": gun, "h": height, "tele": null, "engaged": false}
	node.look_at(at + Vector3(0, 0, 1 if team == "enemy" else -1), Vector3.UP)
	units.append(u)
	return u


func _field_crew() -> void:
	var st = host.state
	st.fielded = crew_alive()
	while not st.crew_ready.is_empty() and crew_alive() < int(cfg.get("max_crew", 6)):
		var kind := str(st.crew_ready.pop_front())
		var pal: Vector3 = host.site_pos("palisade")
		var n := crew_alive()
		spawn(kind, "crew", pal + Vector3((n % 3 - 1) * 1.6, 0, 1.6 + (n / 3) * 1.2))
		st.fielded = crew_alive()


## Target candidates for a unit: [kind, ref, position]. Enemies go for the
## palisade first while it stands (it blocks the beach approach), then any
## crew/player within 5 m, then the nearest standing building.
func _pick_target(u: Dictionary) -> void:
	var me: Vector3 = u["node"].global_position
	var best_d := 1e9
	u["target"] = null
	u["tid"] = ""
	if u["team"] == "enemy":
		var ranged := bool(unit_row(u["kind"]).get("ranged", false))
		var walled := _south(me) and palisade_line() < INF and not ranged
		for o in units:
			if walled and not _south(o["node"].global_position):
				continue
			if o["team"] == "crew" and float(o["dead"]) < 0.0:
				var d: float = me.distance_to(o["node"].global_position)
				if d < 5.0 + (float(unit_row(u["kind"]).get("range", 1.5)) if unit_row(u["kind"]).get("ranged", false) else 0.0) and d < best_d:
					best_d = d
					u["target"] = o
		if host.player_alive() and not (walled and not _south(host._player.global_position)):
			var dp: float = me.distance_to(host._player.global_position)
			if dp < 5.0 + (6.0 if unit_row(u["kind"]).get("ranged", false) else 0.0) and dp < best_d:
				best_d = dp
				u["target"] = "player"
		if u["target"] != null:
			return
		var st = host.state
		if st.hp_of("palisade") > 0.0 and st.level_of("palisade") > 0:
			u["tid"] = "palisade"
			return
		for id in host.site_ids():
			if st.max_hp(id) > 0.0 and st.hp_of(id) > 0.0:
				var d2: float = me.distance_to(host.site_pos(id))
				if d2 < best_d:
					best_d = d2
					u["tid"] = id
	else:
		for o in units:
			if o["team"] == "enemy" and float(o["dead"]) < 0.0:
				var d3: float = me.distance_to(o["node"].global_position)
				if d3 < 10.0 and d3 < best_d:
					best_d = d3
					u["target"] = o


func _target_pos(u: Dictionary) -> Vector3:
	var t = u["target"]
	if t is String and t == "player":
		return host._player.global_position
	if t is Dictionary:
		return (t["node"] as Node3D).global_position
	if str(u["tid"]) != "":
		var p: Vector3 = host.site_pos(str(u["tid"]))
		if str(u["tid"]) == "palisade":
			# Hit the stake line at the point nearest the raider.
			p.x = clampf(u["node"].global_position.x, p.x - 2.6, p.x + 2.6)
		return p
	return u["home"]


func _stop_dist(u: Dictionary) -> float:
	var row := unit_row(u["kind"])
	var r := float(row.get("range", 1.6))
	if u["target"] is String and u["target"] == "player" and not bool(u["engaged"]):
		return maxf(r, 3.2)
	if u["target"] == null and str(u["tid"]) != "":
		return r + (0.6 if str(u["tid"]) == "palisade" else 2.6)
	return r


## Palisade line (world z) while it stands, else INF. Raiders south of it
## can't cross until it is breached.
func palisade_line() -> float:
	var st = host.state
	if st.level_of("palisade") <= 0 or st.hp_of("palisade") <= 0.0:
		return INF
	return host.site_pos("palisade").z - 0.7


func _south(p: Vector3) -> bool:
	return p.z < palisade_line() + 0.05


## At most N raiders may fight the player at once; the rest hang back.
func _assign_slots() -> void:
	var cap := int(cfg.get("max_player_attackers", 2))
	var cands: Array = []
	for u in units:
		u["engaged"] = false
		if u["team"] == "enemy" and float(u["dead"]) < 0.0 and u["target"] is String and u["target"] == "player":
			cands.append(u)
	var me: Vector3 = host._player.global_position
	cands.sort_custom(func(a, b): return (a["node"] as Node3D).global_position.distance_to(me) < (b["node"] as Node3D).global_position.distance_to(me))
	for i in mini(cap, cands.size()):
		cands[i]["engaged"] = true


func attackers_on_player() -> int:
	var n := 0
	for u in units:
		if u["team"] == "enemy" and float(u["dead"]) < 0.0 and float(u["wind"]) > 0.0 and u["target"] is String and u["target"] == "player":
			n += 1
	return n


func _tick_units(delta: float) -> void:
	_assign_slots()
	_retarget -= delta
	var re := _retarget <= 0.0
	if re:
		_retarget = 0.5
	for u in units:
		var node: Node3D = u["node"]
		if not is_instance_valid(node):
			continue
		if float(u["dead"]) >= 0.0:
			u["dead"] = float(u["dead"]) + delta
			if float(u["dead"]) > 2.2:
				node.position.y -= delta * 0.6
			if float(u["dead"]) > 4.0:
				node.visible = false
			continue
		if float(u["flash"]) > 0.0:
			u["flash"] = float(u["flash"]) - delta
			if float(u["flash"]) <= 0.0:
				_tint(u, false)
		var kb: Vector3 = u["kb"]
		if kb.length() > 0.05:
			var p0 := node.global_position + kb * delta
			p0.y = float(host.ground_y(p0.x, p0.z))
			node.global_position = p0
			u["kb"] = kb.lerp(Vector3.ZERO, clampf(delta * 6.0, 0.0, 1.0))
		if float(u["stun"]) > 0.0:
			u["stun"] = float(u["stun"]) - delta
			continue
		if re or (u["target"] is Dictionary and float(u["target"]["dead"]) >= 0.0):
			_pick_target(u)
		var row := unit_row(u["kind"])
		if u["target"] == null and str(u["tid"]) == "":
			if u["team"] == "crew":
				_walk(u, u["home"], 0.4, delta)
			else:
				Art.play(u["rig"], "Idle")
			continue
		var goal := _target_pos(u)
		var dist := Vector2(goal.x - node.global_position.x, goal.z - node.global_position.z).length()
		u["cd"] = float(u["cd"]) - delta
		if dist > _stop_dist(u):
			_walk(u, goal, _stop_dist(u), delta)
			continue
		node.look_at(Vector3(goal.x, node.global_position.y, goal.z), Vector3.UP)
		if float(u["wind"]) > 0.0:
			u["wind"] = float(u["wind"]) - delta
			_telegraph(u, 1.0 - float(u["wind"]) / maxf(float(row.get("windup", 0.5)), 0.01))
			if float(u["wind"]) <= 0.0:
				u["wind"] = 0.0
				_telegraph(u, -1.0)
				u["cd"] = float(row.get("cooldown", 1.2))
				_attack(u, goal)
			continue
		var on_player: bool = u["target"] is String and u["target"] == "player"
		if on_player and not bool(u["engaged"]):
			Art.play(u["rig"], "SwordIdle" if str(row.get("weapon", "")) == "cutlass" else "Idle")
			continue
		if float(u["cd"]) <= 0.0:
			u["wind"] = float(row.get("windup", 0.5))
			if u["gun"]:
				Gear.aim(u["gun"], float(u["h"]))
				Art.play(u["rig"], "SwordIdle", 0.1)
			else:
				Art.play(u["rig"], "Attack", 0.1, 0.55)
		elif not (u["rig"].get_meta("clips") as AnimationPlayer).is_playing() or (u["rig"].get_meta("clips") as AnimationPlayer).current_animation in ["Walk", "Run"]:
			Art.play(u["rig"], "SwordIdle" if str(row.get("weapon", "")) == "cutlass" else "Idle")


func _walk(u: Dictionary, goal: Vector3, stop: float, delta: float) -> void:
	var node: Node3D = u["node"]
	var to := Vector3(goal.x - node.global_position.x, 0, goal.z - node.global_position.z)
	if to.length() <= stop:
		Art.play(u["rig"], "Idle")
		return
	var dir := to.normalized()
	# Separation so a wave doesn't stack on one spot.
	for o in units:
		if o == u or float(o["dead"]) >= 0.0 or not is_instance_valid(o["node"]):
			continue
		var away: Vector3 = node.global_position - (o["node"] as Node3D).global_position
		away.y = 0
		if away.length() < 0.9 and away.length() > 0.01:
			dir += away.normalized() * 0.6
	dir = dir.normalized()
	var speed := float(unit_row(u["kind"]).get("speed", 2.5))
	var next := node.global_position + dir * speed * delta
	next.y = float(host.ground_y(next.x, next.z))
	if next.y < float(host._water_y) - 0.6:
		next.y = float(host._water_y) - 0.6
	if u["team"] == "enemy":
		var line := palisade_line()
		if node.global_position.z <= line + 0.05 and next.z > line:
			next.z = line
			next.y = float(host.ground_y(next.x, next.z))
	node.global_position = next
	node.look_at(next + dir, Vector3.UP)
	Art.play(u["rig"], "Run")


func _attack(u: Dictionary, goal: Vector3) -> void:
	var row := unit_row(u["kind"])
	var dmg := float(row.get("damage", 8))
	if bool(row.get("ranged", false)):
		_fire(u, goal, dmg, float(row.get("shot_speed", 12.0)))
		if u["gun"]:
			Gear.puff(self, (u["gun"].get_node("Muzzle") as Node3D).global_position)
			var gun: Node3D = u["gun"]
			var h := float(u["h"])
			get_tree().create_timer(0.6).timeout.connect(func(): if is_instance_valid(gun): Gear.carry(gun, h))
		return
	_play(SWING, -10.0, randf_range(0.9, 1.1))
	# The blow lands only if the target is still in reach (dodge/backstep).
	var reach := Vector2(goal.x - u["node"].global_position.x, goal.z - u["node"].global_position.z).length()
	if reach <= float(row.get("range", 1.6)) + 0.7 or str(u["tid"]) != "":
		_deal(u, dmg)


func _deal(u: Dictionary, dmg: float) -> void:
	var t = u["target"]
	if t is String and t == "player":
		host.hurt_player(dmg, (u["node"] as Node3D).global_position)
	elif t is Dictionary:
		hurt(t, dmg, (u["node"] as Node3D).global_position, 1.2)
	elif str(u["tid"]) != "":
		host.state.damage(str(u["tid"]), dmg)
		host.site_hit(str(u["tid"]))


## Musket ball: a small dark lead shot with a thin smoke-grey trail.
func _fire(u: Dictionary, goal: Vector3, dmg: float, speed: float) -> void:
	var from: Vector3 = (u["node"] as Node3D).global_position + Vector3.UP * 1.35
	if u["gun"]:
		from = (u["gun"].get_node("Muzzle") as Node3D).global_position
	var to := goal + Vector3.UP * 1.0
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 8
	sm.rings = 4
	ball.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.18, 0.2)
	m.metallic = 0.6
	m.roughness = 0.4
	ball.material_override = m
	add_child(ball)
	ball.global_position = from
	var trail := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.03
	cyl.height = 1.0
	cyl.radial_segments = 5
	trail.mesh = cyl
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.82, 0.8, 0.76, 0.55)
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	tm.roughness = 1.0
	trail.material_override = tm
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)
	_play(SHOT, -16.0, 1.6)
	shots.append({"ball": ball, "trail": trail, "from": from, "to": to, "t": 0.0, "dur": maxf(from.distance_to(to) / speed, 0.15),
		"dmg": dmg, "src": u, "target": u["target"], "tid": u["tid"]})


func _tick_shots(delta: float) -> void:
	var keep: Array = []
	for s in shots:
		s["t"] = float(s["t"]) + delta
		var k := clampf(float(s["t"]) / float(s["dur"]), 0.0, 1.0)
		var from: Vector3 = s["from"]
		var to: Vector3 = s["to"]
		var p := from.lerp(to, k)
		(s["ball"] as Node3D).global_position = p
		var tail := from.lerp(to, maxf(k - 0.25, 0.0))
		var trail: MeshInstance3D = s["trail"]
		var len := maxf(p.distance_to(tail), 0.05)
		var up := (p - tail).normalized() if len > 0.06 else Vector3.UP
		var side := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
		trail.global_transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized().scaled(Vector3(1, len, 1)), (p + tail) * 0.5)
		if k >= 1.0:
			var fake := {"target": s["target"], "tid": s["tid"], "node": s["src"]["node"]}
			if is_instance_valid(fake["node"]):
				_deal(fake, float(s["dmg"]))
			(s["ball"] as Node).queue_free()
			trail.queue_free()
		else:
			keep.append(s)
	shots = keep


## Damage a unit: hit flash, knockback, number, death fall.
func hurt(u: Dictionary, dmg: float, from: Vector3, knock: float) -> void:
	if float(u["dead"]) >= 0.0:
		return
	u["hp"] = float(u["hp"]) - dmg
	var node: Node3D = u["node"]
	var away := node.global_position - from
	away.y = 0
	u["kb"] = away.normalized() * knock * (0.5 if u["kind"] in ["brute", "captain"] else 1.0) * 3.0
	u["flash"] = 0.12
	_tint(u, true)
	# Wind-ups have armour: hitting doesn't cancel the blow, dodging does.
	host.damage_number(node.global_position + Vector3.UP * 2.0, int(dmg), u["team"] == "enemy", node)
	_play(HIT, -6.0, randf_range(0.9, 1.15))
	if float(u["hp"]) <= 0.0:
		u["dead"] = 0.0
		Art.play(u["rig"], "Death", 0.05)
		if u["team"] == "enemy":
			kills += 1
	else:
		Art.play(u["rig"], "Hit", 0.05)


## Wind-up telegraph: a dark-red ring on the ground that closes in as the
## blow comes (lit, semi-transparent, no emission). k < 0 removes it.
func _telegraph(u: Dictionary, k: float) -> void:
	var ring: MeshInstance3D = u["tele"]
	if k < 0.0:
		if ring and is_instance_valid(ring):
			ring.visible = false
		return
	if ring == null or not is_instance_valid(ring):
		ring = MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.9
		c.bottom_radius = 0.9
		c.height = 0.02
		c.radial_segments = 24
		ring.mesh = c
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.08, 0.06, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 1.0
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(u["node"] as Node3D).add_child(ring)
		u["tele"] = ring
	ring.visible = true
	ring.position = Vector3(0, 0.06, -0.6)
	var r := lerpf(1.3, 0.35, clampf(k, 0.0, 1.0))
	ring.scale = Vector3(r, 1, r)


func stun(u: Dictionary, secs: float) -> void:
	u["wind"] = 0.0
	_telegraph(u, -1.0)
	u["stun"] = maxf(float(u["stun"]), secs)


## Hit flash: brief pale-red albedo override (lit, not emissive).
func _tint(u: Dictionary, on: bool) -> void:
	for mesh in Art.meshes(u["rig"]):
		if on:
			if not mesh.has_meta("flash_mat"):
				var fm := StandardMaterial3D.new()
				fm.albedo_color = Color(1.0, 0.55, 0.5)
				fm.roughness = 0.6
				mesh.set_meta("flash_mat", fm)
			mesh.material_overlay = mesh.get_meta("flash_mat")
			(mesh.material_overlay as StandardMaterial3D).albedo_color.a = 0.6
			(mesh.material_overlay as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		else:
			mesh.material_overlay = null


func nearest_enemy(at: Vector3, radius: float) -> Dictionary:
	var best := {}
	var best_d := radius
	for u in units:
		if u["team"] != "enemy" or float(u["dead"]) >= 0.0:
			continue
		var d: float = at.distance_to(u["node"].global_position)
		if d < best_d:
			best_d = d
			best = u
	return best
