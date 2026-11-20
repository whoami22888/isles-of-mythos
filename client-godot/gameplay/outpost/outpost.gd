extends Node3D
## Chapter 2 "Gathering the Scattered", Milestone 1: the survivor camp grows
## into an outpost. Entered from the washed-ashore epilogue; the castaway's
## haul and pet name carry over (OutpostState.carry_from_ashore).
##
## Same island slice (terrain, approved water, sky) as the ashore chapter, the
## same castaway rig, a raised follow camera and a joystick HUD. Buildings sit
## on fixed plots from data/outpost.json.
##
## Milestone 2 hook: `raid_director` (UTC privateer raids on the palisade,
## Barracks crew fighting beside the player) will hang off the state signals
## building_done / camp_levelled and read palisade_hp() / crew_slots().

const Rescue := preload("res://gameplay/outpost/outpost_rescue.gd")
const Raid := preload("res://gameplay/outpost/outpost_raid.gd")
const Gather := preload("res://gameplay/outpost/outpost_gather.gd")
const State := preload("res://gameplay/outpost/outpost_state.gd")
const OutpostArt := preload("res://gameplay/outpost/outpost_art.gd")
const Art := preload("res://gameplay/opening/opening_art.gd")
const SLICE_SCENE := preload("res://scenes/realistic_coastal_slice.tscn")
const FONT_PATH := "res://assets/fonts/PirataOne-Regular.ttf"
const HIDDEN_DRESSING := ["TropicalBayDressing/BeachSettlement", "TropicalBayDressing/BeachWreckage"]
const SPEED := 4.6
## Camera sits on the sea side (south) looking inland at the castaway.
const CAM_BACK := 7.0
const CAM_UP := 5.0
## Village clearing: the survivors cut back undergrowth here.
const CLEARING := Rect2(1.0, 2.0, 20.0, 17.0)
## Foliage within this many metres of the lens (or of the sightline) fades out.
const LENS_CLEAR := 3.4
const REACH := 4.8

var state = State.new()
var art = OutpostArt.new()
var raid_director: Node = null
var raid: Node3D
var player_hp := 120.0
var player_max := 120.0
var _strike_cd := 0.0
var _dodge_t := 0.0
var _dodge_dir := Vector3.ZERO
var _dead_t := -1.0
var _pet_cd := 0.0
var _pet_target: Dictionary = {}
var gather: Node3D
var _gather_focus := -1
var _kick := 0.0
var _slice: Node3D
var _water_y := 0.0
var _terrain_tm: TriangleMesh
var _terrain_xf := Transform3D.IDENTITY
var _camera: Camera3D
var _player: Node3D
var _rig: Node3D
var _pet: Node3D
var _hud: CanvasLayer
var _font: Font
## id -> {"root": Node3D, "plot": Vector3, "shown": "level:building"}
var _sites := {}
var _focus := ""
var _save_t := 0.0
var _cam_yaw := deg_to_rad(192.0)
## [{mm, i, xf, pos, r}] tall foliage instances that can block the lens.
var _lens_items: Array = []
var _lens_hidden := {}
var _cleared_meshes: PackedStringArray = []
## Sites currently see-through because they sit between the lens and the player.
var _ghosted := {}
var _age := 0.0


var _endpoint := ""
var _token := ""
var _refresh := ""


## Boot hands the authenticated session here (kept for Milestone 2 sync).
func begin_authenticated_session(url: String, token: String, refresh: String = "") -> void:
	_endpoint = url
	_token = token
	_refresh = refresh


func _ready() -> void:
	_font = load(FONT_PATH)
	state.load_data()
	if not state.load_save():
		state.carry_from_ashore()
		state.welcome()
	state.building_done.connect(_on_done)
	state.camp_levelled.connect(func(lv): _toast("%s raised!" % state.camp_title(lv)))
	art.ground = Callable(self, "ground_y")
	_build_world()
	_build_sites()
	gather = Gather.new()
	gather.name = "Gather"
	gather.host = self
	add_child(gather)
	gather.setup(state.data.get("gather", {}))
	_build_player()
	raid = Raid.new()
	raid.name = "Raid"
	raid.host = self
	add_child(raid)
	raid.setup(state.m2())
	raid_director = raid
	rescue = Rescue.new()
	rescue.name = "Rescue"
	rescue.host = self
	add_child(rescue)
	rescue.setup(state.data.get("milestone3", {}))
	player_max = float(state.m2().get("player", {}).get("hp", 120))
	player_hp = player_max
	_hud = CanvasLayer.new()
	_hud.set_script(load("res://gameplay/outpost/outpost_hud.gd"))
	_hud.world = self
	add_child(_hud)
	_refresh_sites(true)
	_toast(str(state.data.get("welcome_line", "")) if state.camp_level == 1 and state.level_of("mill") == 0 else "Welcome back to the outpost")
	_push()


func _build_world() -> void:
	_slice = SLICE_SCENE.instantiate()
	_slice.name = "CoastalWorld"
	add_child(_slice)
	for key in ["gameplay_camera", "cinematic_camera"]:
		var cam = _slice.get(key)
		if cam is Camera3D:
			(cam as Camera3D).current = false
	var focal = _slice.get("ship_focal")
	if focal is Node3D:
		(focal as Node3D).visible = false
		(focal as Node3D).process_mode = Node.PROCESS_MODE_DISABLED
	for path in HIDDEN_DRESSING:
		var d := _slice.get_node_or_null(NodePath(path)) as Node3D
		if d:
			d.visible = false
	if _slice.has_method("water_level"):
		_water_y = float(_slice.water_level())
	var terrain := _slice.get_node_or_null("IrregularCoastalTerrain") as MeshInstance3D
	if terrain and terrain.mesh:
		_terrain_tm = terrain.mesh.generate_triangle_mesh()
		_terrain_xf = terrain.global_transform
	_clear_village()
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 52.0
	_camera.near = 0.15
	_camera.far = 420.0
	add_child(_camera)
	_camera.make_current()


## Collapse foliage instances inside the clearing (per-scene multimesh copy)
## and remember the tall ones around it for the lens fade.
func _clear_village() -> void:
	# Rock slabs and cliff chunks the bay scene drops on the plateau.
	var zone := CLEARING.grow(1.5)
	for node in _slice.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.name == "IrregularCoastalTerrain" or mi.mesh == null:
			continue
		var box := mi.global_transform * mi.get_aabb()
		if box.size.x > 30.0 or box.size.z > 30.0:
			continue
		var c := box.get_center()
		if zone.has_point(Vector2(c.x, c.z)):
			mi.visible = false
			_cleared_meshes.append(str(_slice.get_path_to(mi)))
	var dressing := _slice.get_node_or_null("TropicalBayDressing")
	if dressing == null:
		return
	for node in dressing.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		var nm := str(mmi.name)
		if "Summit" in nm or "Cliff" in nm or mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		var mm := _copy_multimesh(mmi.multimesh)
		mmi.multimesh = mm
		var tall := "Palm" in nm or "Canopy" in nm or "Leeward" in nm or "Shrub" in nm or "Fern" in nm or "Understory" in nm or "Calathea" in nm
		var r := mm.mesh.get_aabb().size.length() * 0.35
		for i in mm.instance_count:
			var xf := mmi.global_transform * mm.get_instance_transform(i)
			var p := xf.origin
			if CLEARING.has_point(Vector2(p.x, p.z)) and not "Palm" in nm:
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), mm.get_instance_transform(i).origin))
			elif tall:
				var rs := r * xf.basis.get_scale().x
				_lens_items.append({"mm": mm, "i": i, "xf": mm.get_instance_transform(i), "pos": p + Vector3.UP * rs * 0.6, "r": rs})


func _copy_multimesh(src: MultiMesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = src.transform_format
	mm.use_colors = src.use_colors
	mm.use_custom_data = src.use_custom_data
	mm.mesh = src.mesh
	mm.instance_count = src.instance_count
	mm.visible_instance_count = src.visible_instance_count
	mm.custom_aabb = src.custom_aabb
	for i in src.instance_count:
		mm.set_instance_transform(i, src.get_instance_transform(i))
		if src.use_colors:
			mm.set_instance_color(i, src.get_instance_color(i))
		if src.use_custom_data:
			mm.set_instance_custom_data(i, src.get_instance_custom_data(i))
	return mm


## Hide tall foliage instances in front of the lens; restore once clear.
func _fade_lens() -> void:
	var eye := _camera.global_position
	var head := _player.global_position + Vector3.UP * 1.4
	var want := {}
	for k in _lens_items.size():
		var it: Dictionary = _lens_items[k]
		var p: Vector3 = it["pos"]
		if p.distance_squared_to(eye) > 400.0:
			continue
		var r := float(it["r"])
		var near := p.distance_to(eye) < LENS_CLEAR + r
		var seg := Geometry3D.get_closest_point_to_segment(p, eye, head)
		var blocks := seg.distance_to(p) < r * 0.8 and seg.distance_to(head) > 1.0
		if near or blocks:
			want[k] = true
	for k in want.keys():
		if not _lens_hidden.has(k):
			var it2: Dictionary = _lens_items[k]
			var xf: Transform3D = it2["xf"]
			(it2["mm"] as MultiMesh).set_instance_transform(int(it2["i"]), Transform3D(Basis().scaled(Vector3.ZERO), xf.origin))
	for k in _lens_hidden.keys():
		if not want.has(k):
			var it3: Dictionary = _lens_items[k]
			(it3["mm"] as MultiMesh).set_instance_transform(int(it3["i"]), it3["xf"])
	_lens_hidden = want


## Buildings between the lens and the castaway turn see-through.
func _ghost_sites() -> void:
	var eye := _camera.global_position
	var head := _player.global_position + Vector3.UP * 1.0
	for id in _sites.keys():
		var body: Node3D = _sites[id].get("body")
		var want := false
		if body and is_instance_valid(body):
			var box := Art.world_aabb(body).grow(0.2)
			want = box.intersects_segment(eye, head) != null and not box.has_point(_player.global_position + Vector3.UP * 0.5)
		if want != bool(_ghosted.get(id, false)):
			_ghosted[id] = want
			if body and is_instance_valid(body):
				for g in body.find_children("*", "GeometryInstance3D", true, false):
					if g.name != "Dirt":
						(g as GeometryInstance3D).transparency = 0.72 if want else 0.0


func ghosted() -> Array:
	var out: Array = []
	for id in _ghosted.keys():
		if _ghosted[id]:
			out.append(id)
	return out


func lens_hidden_count() -> int:
	return _lens_hidden.size()


func register_terrain(xf: Transform3D) -> void:
	_extra_terrain.append(xf)


func ground_y(x: float, z: float) -> float:
	if _terrain_tm and z < -60.0:
		for xf in _extra_terrain:
			var inv2: Transform3D = xf.affine_inverse()
			var hit2 := _terrain_tm.intersect_ray(inv2 * Vector3(x, 80.0, z), (inv2.basis * Vector3.DOWN).normalized())
			if not hit2.is_empty():
				return (xf * (hit2["position"] as Vector3)).y
		return _water_y - 6.0
	if _terrain_tm:
		var inv := _terrain_xf.affine_inverse()
		var hit := _terrain_tm.intersect_ray(inv * Vector3(x, 80.0, z), (inv.basis * Vector3.DOWN).normalized())
		if not hit.is_empty():
			return (_terrain_xf * (hit["position"] as Vector3)).y
	if _slice and _slice.has_method("terrain_height_at"):
		return float(_slice.terrain_height_at(x, z))
	return 0.0


func _plot_pos(row: Dictionary) -> Vector3:
	var x := float(row.get("x", 0))
	var z := float(row.get("z", 0))
	return Vector3(x, ground_y(x, z), z)


func _build_sites() -> void:
	var plots: Array = state.data.get("plots", [])
	var ids: Array = ["camp"] + state.data.get("buildings", {}).keys()
	for id in ids:
		var row: Dictionary
		if id == "camp":
			row = state.data.get("camp_plot", {})
		else:
			row = plots[int(state.data["buildings"][id].get("plot", 0))]
		var root := Node3D.new()
		root.name = "Site_" + str(id)
		add_child(root)
		root.global_position = _plot_pos(row)
		root.rotation_degrees.y = float(row.get("yaw", 0))
		var tag := art.label(root, state.title(id), 4.2, _font)
		tag.name = "Tag"
		_sites[id] = {"root": root, "plot": root.global_position, "shown": "", "tag": tag}


func _build_player() -> void:
	var start: Dictionary = state.data.get("player_start", {"x": 12, "z": 7})
	_player = Node3D.new()
	_player.name = "Player"
	add_child(_player)
	_player.global_position = _plot_pos(start)
	_rig = Art.castaway()
	_rig.name = "Rig"
	_player.add_child(_rig)
	Art.fit_height(_rig, 1.78)
	_pet = Node3D.new()
	_pet.name = "Pet"
	add_child(_pet)
	var body := Art.spawn(Art.TIDEPUCK, "Body")
	body.rotation.y = PI
	body.scale = Vector3.ONE * 0.55
	_pet.add_child(body)
	var lab := art.label(_pet, state.pet_name, 0.9, _font)
	lab.name = "Name"
	lab.visible = false
	_pet.global_position = _player.global_position + Vector3(1.2, 0, 0.6)


## Rebuild a site's mesh when its level or build state changes.
func _refresh_sites(force: bool = false) -> void:
	for id in _sites.keys():
		var site: Dictionary = _sites[id]
		var lv: int = state.camp_level if id == "camp" else state.level_of(id)
		var key := "%d:%s:%s:%s" % [lv, state.is_building(id), state.is_unlocked(id) if id != "camp" else true, state.is_damaged(id)]
		var root: Node3D = site["root"]
		if key != site["shown"] or force:
			site["shown"] = key
			for c in root.get_children():
				if c.name != "Tag":
					c.queue_free()
					root.remove_child(c)
			var building := state.is_building(id)
			var show_lv := lv + 1 if building else lv
			if show_lv >= 1:
				site["body"] = art.building(root, id, show_lv, state.is_damaged(id))
			else:
				site["body"] = null
				if id == "camp" or state.is_unlocked(id):
					art.plot_marker(root)
			if building:
				art.scaffold(root, 2.4, 4.0)
		var body: Node3D = site.get("body")
		if body and is_instance_valid(body):
			var p := state.progress(id)
			body.scale = Vector3(1.0, lerpf(0.12, 1.0, p), 1.0)
		var tag: Label3D = site["tag"]
		var unlocked: bool = id == "camp" or state.is_unlocked(id)
		var ready_now: bool = id != "camp" and not state.ready_amount(id).is_empty()
		site["show_tag"] = unlocked and (id == _focus or ready_now)
		tag.visible = false
		tag.text = _tag_text(id)


func _tag_text(id: String) -> String:
	var t := state.title(id)
	if state.is_building(id):
		return "%s  ·  %ds" % [t, int(ceil(state.time_left(id)))]
	var lv: int = state.camp_level if id == "camp" else state.level_of(id)
	if id != "camp" and lv == 0:
		return "%s plot" % t
	var ready: Dictionary = state.ready_amount(id) if id != "camp" else {}
	if not ready.is_empty():
		return "%s  ·  tap to collect %s" % [t, State.cost_text(ready)]
	return "%s  L%d" % [t, lv]


func _process(delta: float) -> void:
	_age += delta
	state.tick(delta)
	_strike_cd = maxf(_strike_cd - delta, 0.0)
	if _dead_t >= 0.0:
		_dead_t -= delta
		if _dead_t < 0.0:
			_respawn()
	elif _dodge_t > 0.0:
		_dodge_t -= delta
		var pc: Dictionary = state.m2().get("player", {})
		var step := _dodge_dir * float(pc.get("dodge_distance", 3.4)) / float(pc.get("dodge_seconds", 0.35)) * delta
		var np := _player.global_position + step
		np.y = ground_y(np.x, np.z)
		if np.y > _water_y + 0.15:
			_player.global_position = np
	elif rescue and rescue.controls_player():
		pass
	else:
		_move(delta)
	if not _pet_bite(delta):
		_follow_pet(delta)
	_follow_camera(delta, false)
	_fade_lens()
	_refresh_sites()
	_ghost_sites()
	_focus = _nearest_site(REACH)
	_gather_focus = gather.nearest(_player.global_position) if gather else -1
	_push()
	_save_t += delta
	if _save_t > 5.0:
		_save_t = 0.0
		state.save()


func _move(delta: float) -> void:
	var input := Vector2.ZERO
	if _hud:
		input += _hud.stick()
	input += Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input = input.limit_length(1.0)
	if input.length() < 0.08:
		var anim: AnimationPlayer = _rig.get_meta("clips") if _rig.has_meta("clips") else null
		if anim == null or anim.current_animation != "Attack" or not anim.is_playing():
			Art.play(_rig, "Idle")
		return
	var fwd := Vector3(-sin(_cam_yaw), 0, -cos(_cam_yaw))
	var right := Vector3(cos(_cam_yaw), 0, -sin(_cam_yaw))
	var dir := (right * input.x - fwd * input.y).normalized()
	var next := _player.global_position + dir * SPEED * input.length() * delta
	next.x = clampf(next.x, -4.0, 32.0)
	next.z = clampf(next.z, 1.0, 24.0)
	next.y = ground_y(next.x, next.z)
	if next.y > _water_y + 0.15:
		_player.global_position = next
	_player.look_at(_player.global_position + dir, Vector3.UP)
	Art.play(_rig, "Run" if input.length() > 0.6 else "Walk")


func _follow_pet(delta: float) -> void:
	var goal := _player.global_position + _player.global_transform.basis.x * 1.1 + _player.global_transform.basis.z * 0.9
	var p := _pet.global_position.lerp(goal, clampf(delta * 2.5, 0.0, 1.0))
	p.y = ground_y(p.x, p.z)
	if p.distance_to(_pet.global_position) > 0.002:
		var look := Vector3(p.x, p.y, p.z) + (p - _pet.global_position).normalized()
		if (look - p).length() > 0.1:
			_pet.look_at(look, Vector3.UP)
	_pet.global_position = p


func _follow_camera(delta: float, snap: bool) -> void:
	var target := _player.global_position + Vector3.UP * 1.2
	var off := Vector3(sin(_cam_yaw), 0, cos(_cam_yaw)) * CAM_BACK + Vector3.UP * CAM_UP
	var eye := target + off
	eye.y = maxf(eye.y, ground_y(eye.x, eye.z) + 2.0)
	_camera.global_position = eye if snap else _camera.global_position.lerp(eye, clampf(delta * 4.0, 0.0, 1.0))
	_camera.look_at(target, Vector3.UP)
	if _kick > 0.0:
		_camera.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _kick
		_kick = maxf(_kick - delta * 0.9, 0.0)


func snap_camera() -> void:
	_follow_camera(0.0, true)


func _nearest_site(radius: float) -> String:
	var best := ""
	var best_d := radius
	for id in _sites.keys():
		if id != "camp" and not state.is_unlocked(id):
			continue
		var d := (_sites[id]["plot"] as Vector3).distance_to(_player.global_position)
		if d < best_d:
			best_d = d
			best = id
	return best


func _action_text() -> String:
	if rescue and rescue.action_text() != "" and not (raid.active() and not raid.nearest_enemy(_player.global_position, 3.2).is_empty()):
		return rescue.action_text()
	if raid and raid.active() and player_alive() and not raid.nearest_enemy(_player.global_position, 3.2).is_empty():
		return "Strike"
	if _focus != "" and state.needs_repair(_focus) and not state.is_building(_focus):
		return "Repair (%s)" % State.cost_text(state.repair_cost(_focus))
	if _gather_focus >= 0 and (_focus == "" or _site_idle(_focus)):
		return "Chop" if gather.kind_of(_gather_focus) == "tree" else "Mine"
	if _focus == "":
		return ""
	if _focus != "camp" and not state.ready_amount(_focus).is_empty():
		return "Collect"
	if state.is_building(_focus):
		return ""
	var nl: int = state.next_level(_focus)
	if nl == 0:
		return ""
	var lv: int = state.camp_level if _focus == "camp" else state.level_of(_focus)
	return ("Build %s" % state.title(_focus)) if lv == 0 else ("Upgrade %s" % state.title(_focus))


## A site with nothing to do right now (lets a nearby tree/rock take the button).
func _site_idle(id: String) -> bool:
	if id != "camp" and not state.ready_amount(id).is_empty():
		return false
	return state.is_building(id) or state.block_reason(id) != ""


func on_action() -> void:
	if not player_alive():
		return
	if rescue and _action_text() == rescue.action_text() and rescue.action_text() != "":
		rescue.on_action()
		return
	if raid and raid.active() and not raid.nearest_enemy(_player.global_position, 3.2).is_empty():
		strike_enemy()
		return
	if _focus != "" and state.needs_repair(_focus) and not state.is_building(_focus):
		if state.repair(_focus):
			_toast("%s repaired" % state.title(_focus))
			_sites[_focus]["shown"] = ""
		else:
			_toast("Repair needs " + State.cost_text(state.repair_cost(_focus)))
		return
	if _gather_focus >= 0 and (_focus == "" or _site_idle(_focus)):
		strike(_gather_focus)
		return
	if _focus == "":
		return
	interact(_focus)


func strike(i: int) -> Dictionary:
	var target: Vector3 = gather.nodes[i]["pos"]
	_player.look_at(Vector3(target.x, _player.global_position.y, target.z), Vector3.UP)
	Art.play(_rig, "Attack", 0.08)
	var got: Dictionary = gather.strike(i)
	if got.is_empty():
		return got
	for k in got.keys():
		state.inv[str(k)] = int(state.inv.get(str(k), 0)) + int(got[k])
	fly_from_world(target + Vector3.UP * 1.2, got)
	return got


func fly_from_world(at: Vector3, got: Dictionary) -> void:
	var screen := _camera.unproject_position(at) if not _camera.is_position_behind(at) else get_viewport().get_visible_rect().size * 0.5
	for kind in got.keys():
		if _hud:
			_hud.fly(screen, str(kind), int(got[kind]))


func camera_kick(amount: float) -> void:
	_kick = maxf(_kick, amount)


## Tap or action on a site: collect if stocked, otherwise build/upgrade.
func interact(id: String) -> void:
	if id != "camp" and not state.ready_amount(id).is_empty():
		collect(id)
		return
	on_build(id)


func on_build(id: String) -> void:
	if id.begins_with("train_"):
		var kind := id.substr(6)
		var why0: String = state.train(kind)
		_toast(why0 if why0 != "" else "Training a %s" % str(raid.unit_row(kind).get("title", kind)))
		return
	var why: String = state.block_reason(id)
	if why != "":
		_toast("%s: %s" % [state.title(id), why])
		return
	var lv: int = state.camp_level if id == "camp" else state.level_of(id)
	state.start(id)
	if _hud:
		_hud.close_menu()
	_toast(("Building the %s" if lv == 0 else "Upgrading the %s") % state.title(id))
	_refresh_sites()
	state.save()


func collect(id: String) -> Dictionary:
	var got: Dictionary = state.collect(id)
	if got.is_empty():
		return got
	fly_from_world((_sites[id]["plot"] as Vector3) + Vector3.UP * 2.0, got)
	state.save()
	return got


func on_tap(screen: Vector2) -> void:
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	var best := ""
	var best_d := 3.2
	for id in _sites.keys():
		if id != "camp" and not state.is_unlocked(id):
			continue
		var p: Vector3 = (_sites[id]["plot"] as Vector3) + Vector3.UP * 1.2
		var d := (p - from).cross(dir).length()
		if d < best_d:
			best_d = d
			best = id
	if best != "":
		interact(best)


func _on_done(id: String, lv: int) -> void:
	_toast("%s %s" % [state.title(id), "built" if lv == 1 else "upgraded to L%d" % lv])
	_refresh_sites()


func _toast(text: String) -> void:
	if _hud and text != "":
		_hud.toast(text)


func _menu_rows() -> Dictionary:
	var rows := {}
	for id in ["camp"] + state.data.get("buildings", {}).keys():
		var nl: int = state.next_level(id)
		var lv: int = state.camp_level if id == "camp" else state.level_of(id)
		var why: String = state.block_reason(id)
		var text := state.title(id) if id != "camp" else "Camp: " + state.camp_title()
		if nl == 0:
			text += "  ·  max"
		elif state.is_building(id):
			text += "  ·  building %ds" % int(ceil(state.time_left(id)))
		else:
			text += "  ·  %s  ·  %ds" % [State.cost_text(state.cost(id, nl)), int(state.level_row(id, nl).get("seconds", 0))]
			if why != "" and not why.begins_with("Need "):
				text += "  ·  " + why
		rows[id] = {"text": text, "can": why == "", "button": "Build" if lv == 0 else "L%d" % nl}
	for kind in state.m2().get("crew_train", {}).keys():
		var tr: Dictionary = state.m2()["crew_train"][kind]
		var queued := 0
		for q in state.crew_queue:
			if q["kind"] == kind:
				queued += 1
		rows["train_" + kind] = {"text": "Train %s  ·  %s  ·  %ds%s" % [raid.unit_row(kind).get("title", kind), State.cost_text(tr.get("cost", {})), int(tr.get("seconds", 20)), "  ·  %d queued" % queued if queued else ""],
			"can": state.level_of("barracks") > 0, "button": "Train"}
	return rows


func _push() -> void:
	if _hud == null:
		return
	_hud.push({
		"inv": state.inv,
		"camp_line": "%s  ·  Camp L%d%s" % [state.camp_title(), state.camp_level, _raid_line()],
		"objective": state.objective(),
		"action": _action_text(),
		"menu": _menu_rows(),
		"tags": _screen_tags(),
		"hp": player_hp / maxf(player_max, 1.0),
		"combat": raid != null and raid.active(),
	})


## World labels as HUD text: focused / ready plots, plus the pet's name only
## when you stand still beside it and nothing else is labelled.
func _raid_line() -> String:
	if raid == null:
		return ""
	if raid.active():
		return "  ·  RAID wave %d  ·  %d raiders" % [maxi(raid.wave, 1), raid.enemies_alive()]
	if raid.eta() > 0.0:
		return "  ·  next raid %d:%02d" % [int(raid.eta()) / 60, int(raid.eta()) % 60]
	return ""


func _screen_tags() -> Array:
	var out: Array = []
	for id in _sites.keys():
		var site: Dictionary = _sites[id]
		if not bool(site.get("show_tag", false)):
			continue
		var at: Vector3 = (site["plot"] as Vector3) + Vector3.UP * 3.6
		if _camera.is_position_behind(at):
			continue
		var sp := _camera.unproject_position(at)
		var vr := get_viewport().get_visible_rect().size
		if sp.x < -40.0 or sp.x > vr.x + 40.0 or sp.y < 0.0 or sp.y > vr.y:
			continue
		out.append({"text": _tag_text(id), "pos": sp, "focus": id == _focus})
	var stick_v: Vector2 = _hud.stick() if _hud else Vector2.ZERO
	var idle: bool = stick_v.length() < 0.08
	if out.is_empty() and idle and _pet.global_position.distance_to(_player.global_position) < 2.5:
		var pa := _pet.global_position + Vector3.UP * 0.9
		if not _camera.is_position_behind(pa):
			out.append({"text": state.pet_name, "pos": _camera.unproject_position(pa), "focus": false})
	return out


# --- Milestone 2: combat -----------------------------------------------------

func player_alive() -> bool:
	return _dead_t < 0.0


## Cutlass swing at the nearest raider: hit-stop, knockback, flash, number.
func strike_enemy() -> bool:
	if _strike_cd > 0.0 or not player_alive():
		return false
	var pc: Dictionary = state.m2().get("player", {})
	var u: Dictionary = raid.nearest_enemy(_player.global_position, float(pc.get("range", 2.2)) + 1.0)
	Art.play(_rig, "Attack", 0.06)
	_strike_cd = float(pc.get("cooldown", 0.42))
	raid._play(Raid.SWING, -8.0, randf_range(0.95, 1.1))
	if u.is_empty():
		return false
	var at: Vector3 = (u["node"] as Node3D).global_position
	_player.look_at(Vector3(at.x, _player.global_position.y, at.z), Vector3.UP)
	raid.hurt(u, float(pc.get("damage", 26)), _player.global_position, float(pc.get("knockback", 2.2)))
	raid.freeze = 0.07
	camera_kick(0.12)
	Input.vibrate_handheld(40, 0.7)
	return true


func on_dodge() -> void:
	if not player_alive() or _dodge_t > 0.0:
		return
	var input: Vector2 = _hud.stick() if _hud else Vector2.ZERO
	var fwd := Vector3(-sin(_cam_yaw), 0, -cos(_cam_yaw))
	var right := Vector3(cos(_cam_yaw), 0, -sin(_cam_yaw))
	_dodge_dir = (right * input.x - fwd * input.y).normalized() if input.length() > 0.2 else -_player.global_transform.basis.z
	_dodge_t = float(state.m2().get("player", {}).get("dodge_seconds", 0.35))
	Art.play(_rig, "Dodge", 0.05, 1.4)


func hurt_player(dmg: float, from: Vector3) -> void:
	if not player_alive() or _dodge_t > 0.0:
		return
	player_hp -= dmg
	damage_number(_player.global_position + Vector3.UP * 2.1, int(dmg), false, _player)
	camera_kick(0.1)
	if player_hp <= 0.0:
		player_hp = 0.0
		_dead_t = float(state.m2().get("player", {}).get("respawn_seconds", 3.0))
		Art.play(_rig, "Death", 0.05)
		banner("You fell", "Back on your feet at the camp")
	else:
		Art.play(_rig, "Hit", 0.05)


func _respawn() -> void:
	player_hp = player_max
	var at := site_pos("camp") + Vector3(0, 0, -3.5)
	if respawn_override != Vector3.INF:
		at = respawn_override
	at.y = ground_y(at.x, at.z)
	_player.global_position = at
	Art.play(_rig, "Idle")
	snap_camera()


## Tide-Puck darts at the nearest raider, bites (small damage) and stuns.
func _pet_bite(delta: float) -> bool:
	_pet_cd = maxf(_pet_cd - delta, 0.0)
	if raid == null or not raid.active():
		return false
	var pcfg: Dictionary = state.m2().get("pet", {})
	if _pet_target.is_empty() or float(_pet_target.get("dead", 0.0)) >= 0.0:
		_pet_target = raid.nearest_enemy(_pet.global_position, float(pcfg.get("range", 7.0)))
	if _pet_target.is_empty():
		return false
	var at: Vector3 = (_pet_target["node"] as Node3D).global_position
	var to := at - _pet.global_position
	to.y = 0
	if to.length() > 1.1:
		var p := _pet.global_position + to.normalized() * 4.5 * delta
		p.y = ground_y(p.x, p.z)
		_pet.global_position = p
		_pet.look_at(Vector3(at.x, p.y, at.z), Vector3.UP)
	elif _pet_cd <= 0.0:
		_pet_cd = float(pcfg.get("cooldown", 3.0))
		raid.hurt(_pet_target, float(pcfg.get("damage", 6)), _pet.global_position, 0.3)
		_pet_lunge(at)
		raid.stun(_pet_target, float(pcfg.get("stun", 1.2)))
		pet_bites += 1
	return true


var pet_bites := 0


## Bite lunge: the pup springs forward, squashes on the bite, settles back.
func _pet_lunge(at: Vector3) -> void:
	var body := _pet.get_node_or_null("Body") as Node3D
	if body == null:
		return
	var rest := body.position
	var dir := _pet.global_transform.basis.inverse() * (at - _pet.global_position)
	dir.y = 0
	dir = dir.normalized() * 0.55
	var base := body.scale
	var t := body.create_tween()
	t.tween_property(body, "position", rest + dir + Vector3(0, 0.18, 0), 0.09).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(body, "scale", base * Vector3(0.9, 1.15, 1.1), 0.09)
	t.tween_property(body, "position", rest + dir, 0.05)
	t.parallel().tween_property(body, "scale", base * Vector3(1.12, 0.85, 1.0), 0.05)
	t.tween_property(body, "position", rest, 0.22).set_trans(Tween.TRANS_BACK)
	t.parallel().tween_property(body, "scale", base, 0.22)
var rescue: Node3D
var respawn_override := Vector3.INF
var _extra_terrain: Array = []   # [Transform3D] more copies of the terrain kit


func site_pos(id: String) -> Vector3:
	return _sites[id]["plot"]


func site_ids() -> Array:
	return _sites.keys()


func site_hit(id: String) -> void:
	var body: Node3D = _sites[id].get("body")
	if body and is_instance_valid(body):
		var t := body.create_tween()
		t.tween_property(body, "rotation_degrees:z", 1.5, 0.05)
		t.tween_property(body, "rotation_degrees:z", 0.0, 0.15)
	if state.is_damaged(id) and not bool(_sites[id].get("wrecked", false)):
		_sites[id]["wrecked"] = true
		_toast("%s wrecked! Repair it with wood" % state.title(id))
		if id == "palisade":
			_sites[id]["shown"] = ""


var _numbers := {}   # instance id -> {lab, n, t}
var _num_side := 1.0


## Floating damage numbers. Rapid hits on the same target merge into one
## number; new numbers alternate left/right so they don't stack.
func damage_number(at: Vector3, n: int, enemy: bool, key: Object = null) -> void:
	var kid := key.get_instance_id() if key else 0
	var now := Time.get_ticks_msec() / 1000.0 + _age
	if kid != 0 and _numbers.has(kid):
		var e: Dictionary = _numbers[kid]
		if is_instance_valid(e["lab"]) and _age - float(e["t"]) < 0.45:
			e["n"] = int(e["n"]) + n
			e["t"] = _age
			(e["lab"] as Label3D).text = str(e["n"])
			(e["lab"] as Label3D).modulate.a = 1.0
			return
	_num_side = -_num_side
	var lab := Label3D.new()
	lab.text = str(n)
	lab.font = _font
	lab.font_size = 72
	lab.pixel_size = 0.0009
	lab.fixed_size = true
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.outline_size = 12
	lab.outline_modulate = Color(0.05, 0.03, 0.02, 0.9)
	lab.modulate = Color(1.0, 0.93, 0.7) if enemy else Color(0.95, 0.35, 0.3)
	add_child(lab)
	var right := _camera.global_transform.basis.x
	lab.global_position = at + right * (0.35 * _num_side)
	if kid != 0:
		_numbers[kid] = {"lab": lab, "n": n, "t": _age}
	var t := lab.create_tween()
	t.tween_property(lab, "global_position", lab.global_position + Vector3.UP * 0.9 + right * 0.25 * _num_side, 0.9)
	t.parallel().tween_property(lab, "modulate:a", 0.0, 0.5).set_delay(0.5)
	t.tween_callback(lab.queue_free)


func banner(title: String, sub: String) -> void:
	if _hud and _hud.has_method("banner"):
		_hud.banner(title, sub)


func place_player(at: Vector3, snap: bool = true) -> void:
	if snap:
		at.y = ground_y(at.x, at.z)
	_player.global_position = at
	if snap:
		_pet.global_position = at + Vector3(1.0, 0, 0.6)
		_pet.global_position.y = ground_y(_pet.global_position.x, _pet.global_position.z)
		snap_camera()


func knock_player(v: Vector3) -> void:
	var p := _player.global_position + v * 0.35
	p.y = ground_y(p.x, p.z)
	if p.y > _water_y + 0.1:
		_player.global_position = p


func subtitle(who: String, text: String) -> void:
	if _hud and _hud.has_method("subtitle"):
		_hud.subtitle(who, text)


func on_log() -> void:
	if _hud and _hud.has_method("show_log"):
		_hud.show_log(state.journal)


## Bot/test helper: walk instantly beside a site.
func stand_at(id: String) -> void:
	var p: Vector3 = _sites[id]["plot"]
	var at := p + Vector3(0, 0, -3.2)
	at.y = ground_y(at.x, at.z)
	_player.global_position = at
	snap_camera()


func _exit_tree() -> void:
	state.save()
