extends Node3D
## Chapter 2 wildlife: boar (charges; hide + meat), crab (beach; scuttles,
## pinches), snake (jungle; poison over time), monkey (steals from the stash
## and flees), gull (steals fish/food), goat (passive; meat + milk).
## Cheap per-animal state machine, at most MAX animals. Spawns by zone and
## time of day. Stats come from data/scenarios/wildlife.json when present.
## Art: no CC0 animal models in the repo, so each animal is a small composed
## mesh with matte materials (no glow).

const MAX := 8
const DEFAULTS := {
	"boar": {"hp": 70, "damage": 18, "speed": 2.2, "charge_speed": 7.5, "aggro": 7.0, "zones": ["jungle", "camp"], "time": "any", "drops": {"hide": 2, "meat": 3}, "weight": 3},
	"crab": {"hp": 18, "damage": 5, "speed": 2.6, "aggro": 2.5, "zones": ["beach"], "time": "any", "drops": {"meat": 1}, "weight": 4},
	"snake": {"hp": 22, "damage": 4, "poison": 3.0, "poison_s": 5.0, "speed": 1.6, "aggro": 3.0, "zones": ["jungle"], "time": "night", "drops": {"hide": 1}, "weight": 2},
	"monkey": {"hp": 25, "damage": 0, "speed": 4.2, "aggro": 0.0, "zones": ["jungle", "camp"], "time": "day", "steals": ["food", "wood", "stone", "iron"], "drops": {}, "weight": 2},
	"gull": {"hp": 8, "damage": 0, "speed": 5.0, "aggro": 0.0, "zones": ["beach", "camp"], "time": "day", "steals": ["fish", "food"], "drops": {"feather": 2}, "weight": 3},
	"goat": {"hp": 40, "damage": 0, "speed": 1.4, "aggro": 0.0, "zones": ["jungle", "camp"], "time": "day", "drops": {"meat": 2, "hide": 1}, "passive": true, "weight": 2},
}
const SPAWN_POINTS := {
	"beach": [Vector3(3.5, 0, 3.0), Vector3(8, 0, 1.5), Vector3(13, 0, 2.6), Vector3(17, 0, 5.6)],
	"jungle": [Vector3(0.5, 0, 8), Vector3(23, 0, 12), Vector3(1.0, 0, 16), Vector3(22, 0, 18), Vector3(12, 0, 21)],
	"camp": [Vector3(8, 0, 15), Vector3(16, 0, 9)],
}

var host: Node   # outpost.gd (ground_y, hurt_player, state, events)
var kinds: Dictionary = {}
var animals: Array = []   # [{kind, node, hp, state, t, target, carry, dot...}]
var rng := RandomNumberGenerator.new()
var _spawn_t := 20.0
var poison_left := 0.0
var poison_dps := 0.0
var auto_spawn := true
var guard_pos := Vector3.INF   # pet guarding here scares thieves


func setup(data = null) -> void:
	kinds = DEFAULTS.duplicate(true)
	if data is Dictionary:
		var rows = data.get("animals", data)
		if rows is Dictionary:
			for k in rows.keys():
				if rows[k] is Dictionary:
					var base: Dictionary = kinds.get(k, {})
					base.merge(rows[k], true)
					kinds[k] = base
		elif rows is Array:
			# Bestiary rows (wildlife.json): take hp, zones and drops for the
			# animals this AI drives; damage may be {attack: n}; drops [min,max].
			for r in rows:
				if r is Dictionary and kinds.has(str(r.get("id", ""))):
					var k2: Dictionary = kinds[str(r["id"])]
					if r.has("hp"):
						k2["hp"] = float(r["hp"])
					var zs: Array = []
					for z in r.get("zones", []):
						var m: String = {"reef": "beach", "sea": "beach", "outpost": "camp", "cliff": "jungle", "cave": "jungle"}.get(str(z), str(z))
						if m in ["beach", "camp", "jungle"] and not (m in zs):
							zs.append(m)
					if not zs.is_empty():
						k2["zones"] = zs
					var dm = r.get("damage", null)
					if dm is Dictionary and float(k2.get("damage", 0)) > 0.0:
						var best := 0.0
						for dk in dm.keys():
							if not ("dot" in str(dk)):
								best = maxf(best, float(dm[dk]))
						k2["damage"] = best
					elif dm is float or dm is int:
						k2["damage"] = float(dm)
					if r.get("drops", null) is Dictionary:
						k2["drops"] = r["drops"]
	rng.seed = int(host.state.ext.get("director", {}).get("seed", 1)) + 77 if host and host.state else 77


func alive() -> Array:
	return animals.filter(func(a): return a["state"] != "dead")


func count_kind(kind: String) -> int:
	return alive().filter(func(a): return a["kind"] == kind).size()


## Spawn `kind` near the player's zone (or `at`). Returns the animal or {}.
func spawn_kind(kind: String, at: Vector3 = Vector3.INF) -> Dictionary:
	if not kinds.has(kind) or alive().size() >= MAX:
		return {}
	if at == Vector3.INF:
		var zs: Array = kinds[kind].get("zones", ["camp"])
		var z := str(zs[rng.randi() % zs.size()])
		var pts: Array = SPAWN_POINTS.get(z, SPAWN_POINTS["camp"])
		at = pts[rng.randi() % pts.size()]
		at += Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.0, 1.0))
	var node := Node3D.new()
	node.name = "%s_%d" % [kind, animals.size()]
	add_child(node)
	at.y = float(host.ground_y(at.x, at.z)) if host else 0.0
	node.global_position = at
	var body := build_body(kind)
	node.add_child(body)
	var a := {"kind": kind, "node": node, "body": body, "hp": float(kinds[kind].get("hp", 20)), "state": "wander", "t": 0.0,
		"goal": at, "home": at, "carry": "", "cd": 0.0, "dir": Vector3.ZERO, "age": 0.0}
	animals.append(a)
	return a


func _row(a: Dictionary) -> Dictionary:
	return kinds.get(a["kind"], {})


func _player_pos() -> Vector3:
	return host._player.global_position if host else Vector3.ZERO


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if poison_left > 0.0 and host:
		poison_left -= delta
		host.player_hp = maxf(host.player_hp - poison_dps * delta, 1.0)
	if auto_spawn:
		_spawn_t -= delta
		if _spawn_t <= 0.0:
			_spawn_t = rng.randf_range(25.0, 60.0)
			_ambient_spawn()
	for a in animals:
		if a["state"] == "dead":
			continue
		a["cd"] = maxf(float(a["cd"]) - delta, 0.0)
		a["age"] = float(a["age"]) + delta
		_think(a, delta)
		_animate(a, delta)
	animals = animals.filter(func(a): return a["state"] != "dead" or is_instance_valid(a["node"]))


func _ambient_spawn() -> void:
	if alive().size() >= 5 or host == null:
		return
	var night: bool = host.events.is_night() if host.get("events") != null else false
	var opts: Array = []
	var ws: Array = []
	for k in kinds.keys():
		var t := str(kinds[k].get("time", "any"))
		if (t == "night" and not night) or (t == "day" and night):
			continue
		opts.append(k)
		ws.append(float(kinds[k].get("weight", 1)))
	if opts.is_empty():
		return
	var total := 0.0
	for w in ws:
		total += w
	var r := rng.randf() * total
	for i in opts.size():
		r -= ws[i]
		if r <= 0.0:
			spawn_kind(opts[i])
			return


func _walk(a: Dictionary, goal: Vector3, speed: float, delta: float) -> bool:
	var n: Node3D = a["node"]
	var to := goal - n.global_position
	to.y = 0.0
	if to.length() < 0.3:
		return true
	var p := n.global_position + to.normalized() * minf(speed * delta, to.length())
	p.y = float(host.ground_y(p.x, p.z)) if host else 0.0
	n.look_at(Vector3(p.x + to.x, p.y, p.z + to.z), Vector3.UP)
	n.global_position = p
	return false


func _think(a: Dictionary, delta: float) -> void:
	var row := _row(a)
	var n: Node3D = a["node"]
	var pp := _player_pos()
	var dist := Vector2(pp.x - n.global_position.x, pp.z - n.global_position.z).length()
	var kind: String = a["kind"]
	a["t"] = float(a["t"]) - delta
	match a["state"]:
		"wander":
			if float(row.get("aggro", 0)) > 0.0 and dist < float(row.get("aggro", 0)) and host and host.player_alive():
				a["state"] = "windup" if kind == "boar" else "chase"
				a["t"] = 0.8
				return
			if kind in ["monkey", "gull"] and a["carry"] == "" and float(a["age"]) > 4.0:
				a["state"] = "steal"
				return
			if float(a["t"]) <= 0.0 or _walk(a, a["goal"], float(row.get("speed", 2)) * 0.45, delta):
				a["t"] = rng.randf_range(2.0, 5.0)
				var h: Vector3 = a["home"]
				a["goal"] = h + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		"windup":   # boar paws the ground, then charges in a straight line
			n.look_at(Vector3(pp.x, n.global_position.y, pp.z), Vector3.UP)
			if float(a["t"]) <= 0.0:
				a["state"] = "charge"
				a["t"] = 1.2
				var d := pp - n.global_position
				d.y = 0
				a["dir"] = d.normalized()
		"charge":
			var goal: Vector3 = n.global_position + (a["dir"] as Vector3) * 2.0
			_walk(a, goal, float(row.get("charge_speed", 7)), delta)
			if dist < 1.3 and float(a["cd"]) <= 0.0:
				_hit_player(a, float(row.get("damage", 10)))
				a["cd"] = 1.5
				a["t"] = 0.0
			if float(a["t"]) <= 0.0:
				a["state"] = "recover"
				a["t"] = 1.4
		"recover":
			if float(a["t"]) <= 0.0:
				a["state"] = "wander" if dist > float(row.get("aggro", 0)) else "windup"
				a["t"] = 0.8
		"chase":
			if dist > float(row.get("aggro", 3)) * 2.0:
				a["state"] = "wander"
			elif dist > 1.0:
				_walk(a, pp, float(row.get("speed", 2)), delta)
			elif float(a["cd"]) <= 0.0:
				_hit_player(a, float(row.get("damage", 4)))
				a["cd"] = 1.6
				if row.has("poison"):
					poison_left = float(row.get("poison_s", 5))
					poison_dps = float(row["poison"])
		"steal":
			var stash := _stash_pos()
			if guard_pos != Vector3.INF and guard_pos.distance_to(stash) < 3.0 and n.global_position.distance_to(stash) < 5.0:
				a["state"] = "flee"
				a["t"] = 4.0
				_toast("%s chases off the %s!" % [_pet_name(), kind])
				return
			if _walk(a, stash, float(row.get("speed", 3)), delta) or n.global_position.distance_to(stash) < 1.2:
				var opts: Array = row.get("steals", ["food"])
				for k in opts:
					if host and host.state.count(str(k)) > 0:
						var amt := mini(host.state.count(str(k)), 3 + rng.randi() % 4)
						host.state.add_item(str(k), -amt)
						a["carry"] = str(k)
						a["carry_n"] = amt
						_toast("A %s stole %d %s!" % [kind, amt, k])
						break
				a["state"] = "flee"
				a["t"] = 8.0
		"flee":
			var away := n.global_position + (n.global_position - pp).normalized() * 3.0
			away.y = n.global_position.y
			_walk(a, Vector3(away.x, 0, maxf(away.z, 1.0)) if kind != "gull" else away, float(row.get("speed", 3)) * 1.2, delta)
			if float(a["t"]) <= 0.0:
				_despawn(a)


func _stash_pos() -> Vector3:
	if host and host.has_method("site_pos"):
		return host.site_pos("camp") + Vector3(-1.0, 0, 2.6)
	return Vector3(10, 0, 14)


func _hit_player(a: Dictionary, dmg: float) -> void:
	if host == null or dmg <= 0.0:
		return
	var before: float = host.player_hp
	host.hurt_player(dmg, (a["node"] as Node3D).global_position)
	if host.player_hp < before:
		host.knock_player(((host._player.global_position - (a["node"] as Node3D).global_position) * Vector3(1, 0, 1)).normalized() * 2.0)


## Nearest live animal within `radius` of `at` (for the player's strike).
func nearest(at: Vector3, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := radius
	for a in animals:
		if a["state"] == "dead":
			continue
		var d := (a["node"] as Node3D).global_position.distance_to(at)
		if d < bd:
			bd = d
			best = a
	return best


## Damage an animal. Returns the drops when it dies (else {}).
func hurt(a: Dictionary, dmg: float, from: Vector3) -> Dictionary:
	if a.is_empty() or a["state"] == "dead":
		return {}
	a["hp"] = float(a["hp"]) - dmg
	var n: Node3D = a["node"]
	var push := (n.global_position - from) * Vector3(1, 0, 1)
	n.global_position += push.normalized() * 0.4
	if bool(_row(a).get("passive", false)) or a["kind"] in ["monkey", "gull"]:
		a["state"] = "flee"
		a["t"] = 5.0
	elif a["kind"] == "crab" or a["kind"] == "snake":
		a["state"] = "chase"
	if float(a["hp"]) > 0.0:
		return {}
	var drops: Dictionary = {}
	var dd: Dictionary = _row(a).get("drops", {})
	for k in dd.keys():
		var v = dd[k]
		var n2: int = rng.randi_range(int(v[0]), int(v[1])) if v is Array else int(v)
		if n2 > 0:
			drops[k] = n2
	if str(a.get("carry", "")) != "":
		drops[a["carry"]] = int(drops.get(a["carry"], 0)) + int(a.get("carry_n", 1))
	a["state"] = "dead"
	var body: Node3D = a["body"]
	var t := n.create_tween()
	t.tween_property(body, "rotation_degrees:z", 90.0, 0.3)
	t.tween_interval(1.2)
	t.tween_property(body, "scale", Vector3.ONE * 0.01, 0.4)
	t.tween_callback(n.queue_free)
	if host and host.get("pet_sys") != null:
		host.pet_sys.drop_at(n.global_position, drops)
	return drops


func _despawn(a: Dictionary) -> void:
	a["state"] = "dead"
	if is_instance_valid(a["node"]):
		(a["node"] as Node3D).queue_free()


func _toast(t: String) -> void:
	if host and host.has_method("_toast"):
		host._toast(t)


func _pet_name() -> String:
	return str(host.state.pet_name) if host else "The pup"


func _animate(a: Dictionary, delta: float) -> void:
	var body: Node3D = a["body"]
	var k: String = a["kind"]
	var ph := float(a["age"]) * (14.0 if a["state"] in ["charge", "flee", "steal", "chase"] else 6.0)
	if k == "snake":
		var i := 0
		for c in body.get_children():
			c.position.x = sin(ph * 0.6 + i * 0.8) * 0.07
			i += 1
	elif k == "gull":
		var wl := body.get_node_or_null("WingL") as Node3D
		var wr := body.get_node_or_null("WingR") as Node3D
		if wl and wr:
			wl.rotation.z = sin(ph) * 0.6
			wr.rotation.z = -sin(ph) * 0.6
		body.position.y = 0.6 + sin(ph * 0.3) * 0.15 if a["state"] != "wander" else 0.0
	else:
		body.position.y = absf(sin(ph)) * 0.03
		if a["state"] == "windup":
			body.rotation.x = sin(ph * 2.0) * 0.06


# --- Art: composed, matte, stylised-realistic ------------------------------------

static var _grain: NoiseTexture2D


## Matte material with a fine mottled grain (fur, shell, hide) so composed
## shapes don't read as smooth plastic toys.
static func _mat(c: Color, rough: float = 0.92) -> StandardMaterial3D:
	if _grain == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.09
		n.fractal_octaves = 4
		_grain = NoiseTexture2D.new()
		_grain.width = 128
		_grain.height = 128
		_grain.seamless = true
		_grain.noise = n
		var g := Gradient.new()
		g.set_color(0, Color(0.62, 0.6, 0.58))
		g.set_color(1, Color(1.05, 1.03, 1.0))
		_grain.color_ramp = g
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = _grain
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(6, 6, 6)
	m.roughness = rough
	return m


static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, scl: Vector3, col: Color, rot: Vector3 = Vector3.ZERO, nm: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col)
	mi.position = pos
	mi.scale = scl
	mi.rotation_degrees = rot
	if nm != "":
		mi.name = nm
	parent.add_child(mi)
	return mi


static func _sphere() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 14
	s.rings = 8
	return s


static func _cyl(top: float = 0.5, bottom: float = 0.5) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = 1.0
	c.radial_segments = 8
	return c


## Body for `kind`, facing -Z (look_at forward).
static func build_body(kind: String) -> Node3D:
	var b := Node3D.new()
	b.name = "Body"
	var sph := _sphere()
	match kind:
		"boar":
			var hide := Color(0.2, 0.16, 0.13)
			_part(b, sph, Vector3(0, 0.5, 0.12), Vector3(0.56, 0.52, 1.1), hide)
			_part(b, sph, Vector3(0, 0.56, -0.25), Vector3(0.6, 0.62, 0.6), hide.darkened(0.1))   # heavy shoulders
			_part(b, sph, Vector3(0, 0.66, 0.1), Vector3(0.18, 0.2, 0.9), Color(0.16, 0.12, 0.1))   # bristle ridge
			_part(b, sph, Vector3(0, 0.44, -0.62), Vector3(0.36, 0.38, 0.5), hide)
			_part(b, _cyl(0.07, 0.13), Vector3(0, 0.36, -0.9), Vector3(1, 0.32, 1), Color(0.26, 0.2, 0.17), Vector3(105, 0, 0))
			_part(b, _cyl(0.075, 0.075), Vector3(0, 0.32, -1.06), Vector3(1, 0.03, 0.8), Color(0.3, 0.22, 0.2), Vector3(105, 0, 0))   # snout disc
			for sx in [-1, 1]:
				_part(b, _cyl(0.0, 0.025), Vector3(0.1 * sx, 0.45, -0.85), Vector3(1, 0.16, 1), Color(0.86, 0.82, 0.7), Vector3(-30, 0, 15 * sx))
				_part(b, sph, Vector3(0.14 * sx, 0.72, -0.5), Vector3(0.07, 0.14, 0.05), hide)
				for sz in [-0.32, 0.38]:
					_part(b, _cyl(0.05, 0.04), Vector3(0.18 * sx, 0.18, sz), Vector3(1, 0.36, 1), Color(0.18, 0.14, 0.11))
		"crab":
			var shell := Color(0.4, 0.2, 0.14)
			_part(b, sph, Vector3(0, 0.1, 0), Vector3(0.34, 0.1, 0.26), shell)
			_part(b, sph, Vector3(0, 0.13, 0.02), Vector3(0.26, 0.06, 0.18), shell.lightened(0.08))
			for sx in [-1, 1]:
				for i in 3:
					var z := -0.06 + i * 0.08
					_part(b, _cyl(0.014, 0.016), Vector3(0.2 * sx, 0.1, z), Vector3(1, 0.14, 1), shell.darkened(0.15), Vector3(0, 0, 70 * sx))
					_part(b, _cyl(0.008, 0.013), Vector3(0.3 * sx, 0.05, z), Vector3(1, 0.12, 1), shell.darkened(0.25), Vector3(0, 0, -25 * sx))
				_part(b, sph, Vector3(0.17 * sx, 0.1, -0.2), Vector3(0.1, 0.07, 0.13), shell.lightened(0.05))
				_part(b, sph, Vector3(0.06 * sx, 0.18, -0.12), Vector3(0.025, 0.05, 0.025), Color(0.08, 0.06, 0.05))
		"snake":
			var scale_c := Color(0.32, 0.36, 0.18)
			for i in 10:
				var r := lerpf(0.07, 0.025, i / 9.0)
				_part(b, sph, Vector3(0, r, -0.2 + i * 0.13), Vector3(r * 2.2, r * 1.8, 0.2), scale_c.lerp(Color(0.5, 0.42, 0.22), float(i % 2) * 0.4))
			_part(b, sph, Vector3(0, 0.07, -0.3), Vector3(0.13, 0.08, 0.17), scale_c.darkened(0.15))
		"monkey":
			var fur := Color(0.24, 0.18, 0.12)
			_part(b, sph, Vector3(0, 0.42, 0.02), Vector3(0.24, 0.36, 0.22), fur)
			_part(b, sph, Vector3(0, 0.72, -0.06), Vector3(0.24, 0.23, 0.22), fur)
			_part(b, sph, Vector3(0, 0.7, -0.16), Vector3(0.13, 0.11, 0.07), Color(0.45, 0.35, 0.28))
			for sx in [-1, 1]:
				_part(b, _cyl(0.03, 0.035), Vector3(0.17 * sx, 0.36, -0.05), Vector3(1, 0.42, 1), fur, Vector3(20, 0, 10 * sx))
				_part(b, _cyl(0.035, 0.04), Vector3(0.1 * sx, 0.14, 0.04), Vector3(1, 0.3, 1), fur)
				_part(b, sph, Vector3(0.12 * sx, 0.76, -0.04), Vector3(0.05, 0.06, 0.02), Color(0.4, 0.3, 0.24))
				_part(b, sph, Vector3(0.045 * sx, 0.74, -0.2), Vector3(0.022, 0.022, 0.01), Color(0.05, 0.04, 0.03))
			for i in 5:
				_part(b, sph, Vector3(0, 0.3 + i * 0.07, 0.2 + i * 0.07), Vector3(0.05, 0.05, 0.1), fur)
		"gull":
			var white := Color(0.88, 0.88, 0.85)
			_part(b, sph, Vector3(0, 0.14, 0), Vector3(0.16, 0.15, 0.36), white)
			_part(b, sph, Vector3(0, 0.24, -0.17), Vector3(0.11, 0.11, 0.12), white)
			_part(b, _cyl(0.0, 0.02), Vector3(0, 0.23, -0.27), Vector3(1, 0.1, 1), Color(0.85, 0.65, 0.2), Vector3(-90, 0, 0))
			for sx in [-1, 1]:
				var w := Node3D.new()
				w.name = "WingL" if sx < 0 else "WingR"
				w.position = Vector3(0.07 * sx, 0.18, 0)
				b.add_child(w)
				_part(w, sph, Vector3(0.18 * sx, 0, 0.03), Vector3(0.36, 0.025, 0.2), Color(0.55, 0.57, 0.6))
			_part(b, sph, Vector3(0, 0.15, 0.3), Vector3(0.1, 0.03, 0.12), Color(0.2, 0.2, 0.22))
		"goat":
			var coat := Color(0.62, 0.56, 0.46)
			_part(b, sph, Vector3(0, 0.55, 0.05), Vector3(0.4, 0.42, 0.8), coat)
			_part(b, _cyl(0.08, 0.1), Vector3(0, 0.75, -0.38), Vector3(1, 0.3, 1), coat, Vector3(-35, 0, 0))
			_part(b, sph, Vector3(0, 0.88, -0.5), Vector3(0.17, 0.18, 0.3), coat.darkened(0.1))
			_part(b, sph, Vector3(0, 0.72, -0.56), Vector3(0.05, 0.12, 0.05), Color(0.3, 0.27, 0.22))   # beard
			for sx in [-1, 1]:
				_part(b, _cyl(0.0, 0.025), Vector3(0.06 * sx, 1.02, -0.42), Vector3(1, 0.22, 1), Color(0.3, 0.27, 0.22), Vector3(40, 0, 10 * sx))
				for sz in [-0.25, 0.33]:
					_part(b, _cyl(0.035, 0.03), Vector3(0.13 * sx, 0.2, sz), Vector3(1, 0.4, 1), coat.darkened(0.25))
		_:
			_part(b, sph, Vector3(0, 0.3, 0), Vector3(0.4, 0.4, 0.6), Color(0.4, 0.35, 0.3))
	return b
