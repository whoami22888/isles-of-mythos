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

const State := preload("res://gameplay/outpost/outpost_state.gd")
const OutpostArt := preload("res://gameplay/outpost/outpost_art.gd")
const Art := preload("res://gameplay/opening/opening_art.gd")
const SLICE_SCENE := preload("res://scenes/realistic_coastal_slice.tscn")
const FONT_PATH := "res://assets/fonts/PirataOne-Regular.ttf"
const HIDDEN_DRESSING := ["TropicalBayDressing/BeachSettlement", "TropicalBayDressing/BeachWreckage"]
const SPEED := 4.6
const CAM_BACK := 9.5
const CAM_UP := 7.5
const REACH := 4.8

var state = State.new()
var art = OutpostArt.new()
var raid_director: Node = null
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
var _cam_yaw := deg_to_rad(15.0)
var _age := 0.0


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
	_build_player()
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
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 52.0
	_camera.near = 0.15
	_camera.far = 420.0
	add_child(_camera)
	_camera.make_current()


func ground_y(x: float, z: float) -> float:
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
	_pet.global_position = _player.global_position + Vector3(1.2, 0, 0.6)


## Rebuild a site's mesh when its level or build state changes.
func _refresh_sites(force: bool = false) -> void:
	for id in _sites.keys():
		var site: Dictionary = _sites[id]
		var lv: int = state.camp_level if id == "camp" else state.level_of(id)
		var key := "%d:%s:%s" % [lv, state.is_building(id), state.is_unlocked(id) if id != "camp" else true]
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
				site["body"] = art.building(root, id, show_lv)
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
		tag.visible = id == "camp" or state.is_unlocked(id)
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
	_move(delta)
	_follow_pet(delta)
	_follow_camera(delta, false)
	_refresh_sites()
	_focus = _nearest_site(REACH)
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


func on_action() -> void:
	if _focus == "":
		return
	interact(_focus)


## Tap or action on a site: collect if stocked, otherwise build/upgrade.
func interact(id: String) -> void:
	if id != "camp" and not state.ready_amount(id).is_empty():
		collect(id)
		return
	on_build(id)


func on_build(id: String) -> void:
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
	var at := (_sites[id]["plot"] as Vector3) + Vector3.UP * 2.0
	var screen := _camera.unproject_position(at) if not _camera.is_position_behind(at) else get_viewport().get_visible_rect().size * 0.5
	for kind in got.keys():
		if _hud:
			_hud.fly(screen, str(kind), int(got[kind]))
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
	return rows


func _push() -> void:
	if _hud == null:
		return
	_hud.push({
		"inv": state.inv,
		"camp_line": "%s  ·  Camp L%d" % [state.camp_title(), state.camp_level],
		"objective": state.objective(),
		"action": _action_text(),
		"menu": _menu_rows(),
	})


## Bot/test helper: walk instantly beside a site.
func stand_at(id: String) -> void:
	var p: Vector3 = _sites[id]["plot"]
	var at := p + Vector3(0, 0, -3.0)
	at.y = ground_y(at.x, at.z)
	_player.global_position = at
	snap_camera()


func _exit_tree() -> void:
	state.save()
