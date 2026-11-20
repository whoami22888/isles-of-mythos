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

var host: Node   # outpost.gd: ground_y(), state, fly_from_world(), camera_kick()
var cfg: Dictionary = {}
## [{kind, root, body, hp, left, pos}]
var nodes: Array = []
var _cooldown := 0.0
var _sfx: AudioStreamPlayer3D


func setup(data: Dictionary) -> void:
	cfg = data
	_sfx = AudioStreamPlayer3D.new()
	add_child(_sfx)
	for row in cfg.get("nodes", []):
		var kind := str(row.get("kind", "tree"))
		var x := float(row.get("x", 0))
		var z := float(row.get("z", 0))
		var root := Node3D.new()
		root.name = "%s_%d" % [kind, nodes.size()]
		add_child(root)
		root.global_position = Vector3(x, float(host.ground_y(x, z)), z)
		root.rotation_degrees.y = fmod(x * 37.0 + z * 11.0, 360.0)
		var body := Art.spawn(TREE if kind == "tree" else ROCK, "Body")
		root.add_child(body)
		Art.fit_height(body, 6.5 if kind == "tree" else 1.1)
		var box := Art.world_aabb(body)
		# Wide flat rock meshes: cap the footprint, not just the height.
		var wide := maxf(box.size.x, box.size.z)
		var cap := 4.5 if kind == "tree" else 1.7
		if wide > cap:
			body.scale *= cap / wide
			box = Art.world_aabb(body)
		body.global_position.y += root.global_position.y - box.position.y - (0.15 if kind == "tree" else 0.25)
		nodes.append({"kind": kind, "root": root, "body": body, "hp": _hits(kind), "left": 0.0, "pos": root.global_position, "rest": body.position})


func _hits(kind: String) -> int:
	return int(cfg.get("kinds", {}).get(kind, {}).get("hits", 4))


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
	_cooldown = 0.32
	var kind := str(n["kind"])
	var row: Dictionary = cfg.get("kinds", {}).get(kind, {})
	n["hp"] = int(n["hp"]) - 1
	var gain: Dictionary = (row.get("yield", {}) as Dictionary).duplicate()
	var body: Node3D = n["body"]
	# Wobble about the base, a short local hit-stop, chips and the kick.
	var t := create_tween()
	var rest: Vector3 = n["rest"]
	t.tween_property(body, "rotation_degrees:z", 6.0 if kind == "tree" else 0.0, 0.05)
	t.tween_property(body, "position", rest + Vector3(0.06, 0, 0), 0.04)
	t.tween_interval(0.05)
	t.tween_property(body, "rotation_degrees:z", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(body, "position", rest, 0.2)
	_chips(n["pos"] + Vector3.UP * (1.1 if kind == "tree" else 0.6), kind)
	_sfx.stream = CHOP if kind == "tree" else STONE_HIT
	_sfx.global_position = n["pos"]
	_sfx.pitch_scale = randf_range(0.92, 1.08)
	_sfx.play()
	Input.vibrate_handheld(35 if int(n["hp"]) > 0 else 80, 0.6)
	if host.has_method("camera_kick"):
		host.camera_kick(0.08 if int(n["hp"]) > 0 else 0.18)
	if int(n["hp"]) <= 0:
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


func _chips(at: Vector3, kind: String) -> void:
	for k in 5:
		var chip := Art.spawn(STONE if kind == "rock" else Art.DRIFT_BRANCHES)
		add_child(chip)
		Art.fit_height(chip, 0.12 if kind == "rock" else 0.18)
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
