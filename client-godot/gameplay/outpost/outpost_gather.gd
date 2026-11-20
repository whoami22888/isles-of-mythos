extends Node3D
## Strikeable trees and rocks around the outpost. Same feel as the island's
## gathering: swing, local hit-stop, wobble, flying chips, camera kick,
## haptics, material sound, and the yield flying to the HUD.

const Art := preload("res://gameplay/opening/opening_art.gd")
const TREE := preload("res://assets/external/generated/foliage/island_tree_01_lod2.glb")
const ROCK := preload("res://assets/opening/library/coast_rocks_03/coast_rocks_03.glb")
const STONE := preload("res://assets/ashore/library/stone_01/stone_01.glb")
const CHOP := preload("res://assets/ashore/audio/chop.ogg")
const STONE_HIT := preload("res://assets/ashore/audio/stone_hit.ogg")
const PALM_A := preload("res://assets/ashore/models/palm_a.glb")
const PALM_B := preload("res://assets/ashore/models/palm_b.glb")
const BUSH := preload("res://assets/ashore/models/bush.glb")
const Tools := preload("res://gameplay/outpost/outpost_tools.gd")
const W := preload("res://gameplay/outpost/outpost_wildlife.gd")
const WOODY := ["tree", "hardwood", "palm", "coconut_palm", "bamboo", "berry_bush"]

var tools = Tools.new()
var rng := RandomNumberGenerator.new()
var last_crit := false

var host: Node   # outpost.gd: ground_y(), state, fly_from_world(), camera_kick()
var cfg: Dictionary = {}
## [{kind, root, body, hp, left, pos}]
var nodes: Array = []
var _cooldown := 0.0
var _sfx: AudioStreamPlayer3D


func setup(data: Dictionary) -> void:
	cfg = data
	tools.setup(host.state)
	rng.seed = int(host.state.ext.get("director", {}).get("seed", 3)) + 313
	_sfx = AudioStreamPlayer3D.new()
	add_child(_sfx)
	for row in cfg.get("nodes", []):
		var kind := str(row.get("kind", "tree"))
		var x := float(row.get("x", 0))
		var z := float(row.get("z", 0))
		var root := Node3D.new()
		root.name = "%s_%d" % [kind, nodes.size()]
		add_child(root)
		var gy := float(host.ground_y(x, z))
		if kind == "fishing_spot":
			gy = float(host._water_y) + 0.03
		root.global_position = Vector3(x, gy, z)
		root.rotation_degrees.y = fmod(x * 37.0 + z * 11.0, 360.0)
		var body := _art(kind)
		body.name = "Body"
		root.add_child(body)
		if body.get_meta("fit", true):
			var tall := float(_kind_row(kind).get("height", 6.5 if kind in WOODY else 1.1))
			Art.fit_height(body, tall)
			var box := Art.world_aabb(body)
			var wide := maxf(box.size.x, box.size.z)
			var cap := float(_kind_row(kind).get("footprint", 4.5 if kind in WOODY else 1.7))
			if wide > cap:
				body.scale *= cap / wide
				box = Art.world_aabb(body)
			body.global_position.y += root.global_position.y - box.position.y - (0.15 if kind in WOODY else 0.25)
		nodes.append({"kind": kind, "root": root, "body": body, "hp": _hits(kind), "left": 0.0, "pos": root.global_position, "rest": body.position})


func _kind_row(kind: String) -> Dictionary:
	return cfg.get("kinds", {}).get(kind, {})


## Verb for the action button.
func verb(kind: String) -> String:
	return str(_kind_row(kind).get("verb", "Chop" if kind in WOODY else "Mine"))


func _art(kind: String) -> Node3D:
	var b: Node3D
	match kind:
		"palm":
			b = Art.spawn(PALM_A)
		"coconut_palm":
			b = Node3D.new()
			var p := Art.spawn(PALM_B)
			b.add_child(p)
			Art.fit_height(p, 6.0)
			for i in 4:
				W._part(b, W._sphere(), Vector3(cos(i * 1.6) * 0.3, 5.3, sin(i * 1.6) * 0.3), Vector3.ONE * 0.24, Color(0.36, 0.26, 0.14))
			b.set_meta("fit", false)
		"bamboo":
			b = Node3D.new()
			for i in 7:
				var h := 3.2 + float((i * 37) % 13) / 8.0
				var at := Vector3(cos(i * 2.4) * 0.45 * (i % 3), h * 0.5, sin(i * 2.4) * 0.45 * (i % 3))
				W._part(b, W._cyl(0.05, 0.06), at, Vector3(1, h, 1), Color(0.5, 0.55, 0.27).lerp(Color(0.62, 0.58, 0.36), (i % 3) / 3.0), Vector3((i % 3 - 1) * 4.0, 0, (i % 2) * 5.0))
				for k in 3:
					W._part(b, W._sphere(), at + Vector3(0.18, h * 0.3 + k * 0.4 - 0.2, 0), Vector3(0.5, 0.03, 0.12), Color(0.38, 0.47, 0.22), Vector3(0, i * 50 + k * 120, -20))
			b.set_meta("fit", false)
		"flint":
			b = Node3D.new()
			var r := Art.spawn(STONE)
			b.add_child(r)
			Art.fit_height(r, 0.55)
			for i in 4:
				W._part(b, BoxMesh.new(), Vector3(cos(i * 1.7) * 0.5, 0.08, sin(i * 1.7) * 0.5), Vector3(0.22, 0.1, 0.14), Color(0.17, 0.18, 0.2), Vector3(20, i * 70, 15))
			b.set_meta("fit", false)
		"iron_seam":
			b = Node3D.new()
			var r2 := Art.spawn(ROCK)
			b.add_child(r2)
			Art.fit_height(r2, 1.3)
			var bx := Art.world_aabb(r2)
			if maxf(bx.size.x, bx.size.z) > 2.0:
				r2.scale *= 2.0 / maxf(bx.size.x, bx.size.z)
			for i in 5:
				W._part(b, W._sphere(), Vector3(cos(i * 1.3) * 0.5, 0.35 + (i % 2) * 0.3, sin(i * 1.3) * 0.45), Vector3(0.32, 0.1, 0.22), Color(0.42, 0.2, 0.1), Vector3(30, i * 40, 10))
			b.set_meta("fit", false)
		"berry_bush":
			b = Node3D.new()
			var bu := Art.spawn(BUSH)
			b.add_child(bu)
			Art.fit_height(bu, 1.1)
			for i in 9:
				W._part(b, W._sphere(), Vector3(cos(i * 0.9) * 0.45, 0.5 + (i % 3) * 0.18, sin(i * 0.9) * 0.45), Vector3.ONE * 0.08, Color(0.5, 0.06, 0.1))
			b.set_meta("fit", false)
		"fishing_spot":
			b = Node3D.new()
			for i in 3:
				var tm := TorusMesh.new()
				tm.inner_radius = 0.5 + i * 0.45
				tm.outer_radius = 0.56 + i * 0.45
				W._part(b, tm, Vector3.ZERO, Vector3(1, 0.05, 1), Color(0.75, 0.82, 0.85, 1.0))
			b.set_meta("fit", false)
		"tide_pool":
			b = Node3D.new()
			W._part(b, W._cyl(0.9, 0.9), Vector3(0, 0.02, 0), Vector3(1, 0.04, 0.8), Color(0.12, 0.2, 0.22))
			for i in 8:
				W._part(b, W._sphere(), Vector3(cos(i * 0.8) * 1.0, 0.06, sin(i * 0.8) * 0.82), Vector3(0.28, 0.16, 0.22), Color(0.36, 0.34, 0.3))
			b.set_meta("fit", false)
		"rock":
			b = Art.spawn(ROCK)
		_:
			b = Art.spawn(TREE)
	return b


func _hits(kind: String) -> int:
	return tools.hits_needed(_kind_row(kind)) if tools.st != null else int(_kind_row(kind).get("hits", 4))


## Index of the nearest live node within reach of `at` (-1 when none).
func nearest(at: Vector3) -> int:
	var best := -1
	var best_d := float(cfg.get("reach", 2.6)) + 0.8
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		if float(n["left"]) > 0.0:
			continue
		var d := Vector2(at.x - n["pos"].x, at.z - n["pos"].z).length()
		if d < best_d:
			best_d = d
			best = i
	return best


func kind_of(i: int) -> String:
	return str(nodes[i]["kind"]) if i >= 0 and i < nodes.size() else ""


## One strike. Returns what was gained (may be empty while on cooldown).
func strike(i: int) -> Dictionary:
	if i < 0 or i >= nodes.size() or _cooldown > 0.0:
		return {}
	var n: Dictionary = nodes[i]
	if float(n["left"]) > 0.0:
		return {}
	var kind := str(n["kind"])
	var row: Dictionary = cfg.get("kinds", {}).get(kind, {})
	var why := tools.block(row)
	if why != "":
		_cooldown = 0.6
		if host.has_method("_toast"):
			host._toast(why)
		return {}
	_cooldown = 0.32
	n["hp"] = int(n["hp"]) - 1
	var fin_rolled := int(n["hp"]) <= 0
	var r: Dictionary = tools.roll(row, fin_rolled, rng)
	last_crit = r["crit"]
	if r["crit"]:
		n["hp"] = int(n["hp"]) - 1   # a crit also bites deeper
	var gain: Dictionary = r["gain"]
	for k in r["rare"].keys():
		gain[k] = int(gain.get(k, 0)) + 1
		if host.has_method("_toast"):
			host._toast("Rare find: %s!" % str(k).replace("_", " "))
	if r["broke"] != "" and host.has_method("_toast"):
		host._toast("Your %s broke!" % r["broke"])
	if r["crit"] and host.has_method("damage_number"):
		_crit_pop(n["pos"] + Vector3.UP * 1.8)
	var body: Node3D = n["body"]
	# Wobble about the base, a short local hit-stop, chips and the kick.
	var t := create_tween()
	var rest: Vector3 = n["rest"]
	t.tween_property(body, "rotation_degrees:z", 6.0 if kind == "tree" else 0.0, 0.05)
	t.tween_property(body, "position", rest + Vector3(0.06, 0, 0), 0.04)
	t.tween_interval(0.05)
	t.tween_property(body, "rotation_degrees:z", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(body, "position", rest, 0.2)
	_chips(n["pos"] + Vector3.UP * (1.1 if kind in WOODY else 0.6), kind)
	_sfx.stream = CHOP if kind in WOODY else STONE_HIT
	_sfx.global_position = n["pos"]
	_sfx.pitch_scale = randf_range(0.92, 1.08)
	_sfx.play()
	Input.vibrate_handheld(35 if int(n["hp"]) > 0 else 80, 0.6)
	if host.has_method("camera_kick"):
		host.camera_kick((0.08 if int(n["hp"]) > 0 else 0.18) * (1.8 if last_crit else 1.0))
	if int(n["hp"]) <= 0:
		if not fin_rolled:
			var fin: Dictionary = row.get("finish", {})
			for k in fin.keys():
				gain[k] = int(gain.get(k, 0)) + int(fin[k])
		n["left"] = float(cfg.get("respawn_seconds", 45))
		var gone := create_tween()
		gone.tween_interval(0.15)
		gone.tween_property(body, "scale", body.scale * Vector3(1, 0.02, 1), 0.35).set_ease(Tween.EASE_IN)
		gone.tween_callback(func(): body.visible = false)
		n["full_scale"] = n.get("full_scale", body.scale)
	return gain


## "CRIT!" pops off the node, bigger and gold.
func _crit_pop(at: Vector3) -> void:
	var lab := Label3D.new()
	lab.text = "CRIT!"
	lab.font_size = 96
	lab.outline_size = 18
	lab.modulate = Color(1.0, 0.82, 0.3)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	add_child(lab)
	lab.global_position = at
	var tw := lab.create_tween()
	tw.tween_property(lab, "global_position", at + Vector3.UP * 0.8, 0.6)
	tw.parallel().tween_property(lab, "modulate:a", 0.0, 0.3).set_delay(0.35)
	tw.tween_callback(lab.queue_free)
	Input.vibrate_handheld(90, 1.0)


func _chips(at: Vector3, kind: String) -> void:
	for k in 5:
		var chip := Art.spawn(Art.DRIFT_BRANCHES if kind in WOODY else STONE)
		add_child(chip)
		Art.fit_height(chip, 0.18 if kind in WOODY else 0.12)
		chip.global_position = at
		var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(0.6, 1.3)
		var land := at + dir
		land.y = float(host.ground_y(land.x, land.z)) + 0.05
		var peak := (at + land) * 0.5 + Vector3.UP * randf_range(0.5, 0.9)
		var tw := chip.create_tween()
		tw.tween_method(func(v: float): chip.global_position = at.lerp(peak, v).lerp(peak.lerp(land, v), v); chip.rotation.x = v * 9.0, 0.0, 1.0, 0.42)
		tw.tween_interval(0.5)
		tw.tween_property(chip, "scale", Vector3.ONE * 0.001, 0.25)
		tw.tween_callback(chip.queue_free)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	for n in nodes:
		if float(n["left"]) > 0.0:
			n["left"] = float(n["left"]) - delta
			if float(n["left"]) <= 0.0:
				n["left"] = 0.0
				n["hp"] = _hits(str(n["kind"]))
				var body: Node3D = n["body"]
				body.visible = true
				body.scale = n.get("full_scale", body.scale)
				body.position = n["rest"]
