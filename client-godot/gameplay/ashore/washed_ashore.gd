extends Node3D
## Local washed-ashore island. The opening battle hands its in-memory session
## here. Nothing on this screen is the server debug slice.
##
## Mobile budget for a Galaxy S23 Ultra class device: one shadowed sun,
## a 32x32 lagoon grid, depth fog, and no shadow casting on small props.
## Pickups use albedo only. Flame and the distant volcano are the only glow.

const CATALOG_PATH := "res://gameplay/ashore/data/catalog.json"
const SAVE_PATH := "user://washed_ashore.cfg"
const OFFSHORE_WARNING := "Too dangerous: sharks/storm"
const PET_DEFENCE_LINE := "Needs Pet Defence research and training"

const KENNEY := "res://assets/opening/kenney/"
const SHIP_SCENE := "res://assets/external/polyhaven/dutch_ship_medium/dutch_ship_medium_1k.gltf"
const CLIFF_SCENE := "res://assets/external/polyhaven/coastal_cliff_01/coastal_cliff_01_1k.gltf"
const TREE_A := "res://assets/external/polyhaven/island_tree_01/island_tree_01_1k.gltf"
const TREE_B := "res://assets/external/polyhaven/island_tree_02/island_tree_02_1k.gltf"
const SAND_ALBEDO := "res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_diff_1k.jpg"
const SAND_NORMAL := "res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_nor_gl_1k.jpg"
const SAND_ROUGH := "res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_rough_1k.jpg"
const CLIFF_ALBEDO := "res://assets/external/polyhaven/coastal_cliff_01/textures/coastal_cliff_01_diff_1k.jpg"
const CLIFF_NORMAL := "res://assets/external/polyhaven/coastal_cliff_01/textures/coastal_cliff_01_nor_gl_1k.jpg"
const MODELS := "res://assets/ashore/models/"
const FONT_PATH := "res://assets/fonts/PirataOne-Regular.ttf"

const AUDIO := "res://assets/ashore/audio/"
const OCEAN := "res://assets/opening/audio/ocean.ogg"
const SWING := "res://assets/opening/audio/swing.ogg"
const ROAR := "res://assets/opening/audio/roar.ogg"
const CHEER := "res://assets/opening/audio/cheer.ogg"

const FOOD_IDS := ["food", "fish", "meat", "cooked"]
const RAW_IDS := ["food", "fish", "meat"]
const TOOL_IDS := ["axe", "knife", "club", "pick"]
const WRECK_IDS := ["hull", "rigging", "cargo_cloth"]

var _endpoint := ""
var _token := ""
var _refresh := ""
var _client: Node
var _catalog: Dictionary = {}
var _tuning: Dictionary = {}
var _research: Array = []
var _nodes: Array = []
var _inv := {"planks": 0, "rope": 0, "cloth": 0, "wood": 0, "food": 0, "meat": 0, "flint": 0, "fish": 0, "cooked": 0}
var _tools := {"axe": false, "pick": false, "knife": false, "club": false}
var _running := ""
var _research_left := 0.0
var _research_open := false
var _pet_open := false

var _step := "wake"
var _line := "Cold."
var _hint := ""
var _hint_t := 0.0
var _pointer_id := "wreck"
var _cinematic := ""
var _cine_age := 0.0
var _age := 0.0
var _warmth := 58.0
var _hunger := 78.0
var _health := 5
var _fire_lit := false
var _shelter := false
var _dusk_active := false
var _alerted := false
var _fork := false
var _qte := false
var _stagger := false
var _naming := false
var _gatherer := false
var _rare := false
var _choice := ""
var _collect_ready := false
var _collect_taken := false
var _end_open := false
var _end_dismissed := false
var _guard_down := false
var _creature_hostile := false
var _creature_hp := 4
var _creature_max := 4
var _attack_cd := 0.0
var _beast_cd := 0.0
var _swing := 0.0
var _spot := -1
var _building := false
var _build_left := 0.0
var _build_total := 12.0
var _hut_stage := 0
var _step_time := 0.0
var _squeak_t := 1.2
var _sniff_t := 0.0
var _heralds := 0
var _tame_left := 0.0
var _tame_total := 12.0
var _tame_hits := 0
var _tame_misses := 0
var _tame_phase := 0.0
var _cine_left := 0.0
var _kill_rewarded := false
var _save_clock := 0.0
var _loading := false
var _move_goal := Vector3(INF, INF, INF)
var _move_node: Dictionary = {}
var _gather_cd := 1.2
var _pet_freed := false
var _cam_yaw := 0.0
var _pet_anim: AnimationPlayer
var _beast_anim: AnimationPlayer
var _prompt: Label3D
var _pet_stats := {"name": "Tide-Puck", "level": 1, "xp": 0, "hunger": 70, "mood": 65}

var _camera: Camera3D
var _player: Node3D
var _anim: AnimationPlayer
var _skin: Array[StandardMaterial3D] = []
var _pet: Node3D
var _pet_head: Node3D
var _beast: Node3D
var _beast_mats: Array[StandardMaterial3D] = []
var _sack: Node3D
var _hut: Node3D
var _flame: Node3D
var _camp_flame: MeshInstance3D
var _ring: MeshInstance3D
var _hud: CanvasLayer
var _ocean: AudioStreamPlayer
var _fire_loop: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _voice_i := 0
var _font: Font
var _env: Environment
var _sky: ShaderMaterial
var _sun: DirectionalLight3D
var _nodes_root: Node3D
var _sharks: Array[Node3D] = []
var _saved: Dictionary = {}


func begin_authenticated_session(endpoint: String, token: String, refresh_token: String = "") -> void:
	_endpoint = endpoint
	_token = token
	_refresh = refresh_token
	if _client and _client.has_method("configure"):
		_client.configure(endpoint, token)


func quest_line() -> String:
	return _line


func offshore_warning() -> String:
	return OFFSHORE_WARNING


func pet_can_fight() -> bool:
	return false


func creature_bold() -> bool:
	return _dusk_active and not _fire_lit


func tame_window() -> float:
	return float(_tuning.get("tame_seconds", 12.0))


func research_ids() -> Array:
	var ids: Array = []
	for row in _research:
		ids.append(str(row.get("id", "")))
	return ids


func _ready() -> void:
	_client = ShoreSession.new()
	_client.name = "Session"
	_client.configure(_endpoint, _token)
	add_child(_client)
	_font = load(FONT_PATH)
	_load_catalog()
	_warmth = float(_tuning.get("warmth_start", 58.0))
	_hunger = float(_tuning.get("hunger_start", 78.0))
	_tame_total = tame_window()
	_read_save()
	_build_audio()
	_build_world()
	_build_player()
	_build_pet()
	_build_beast()
	_build_props()
	_build_nodes()
	_scatter()
	_hud = CanvasLayer.new()
	_hud.set_script(load("res://gameplay/ashore/ashore_hud.gd"))
	_hud.world = self
	add_child(_hud)
	if _saved.is_empty():
		_enter("wake")
	else:
		_apply_save(_saved)
	_push_hud()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	_age += delta
	if _hint_t > 0.0:
		_hint_t = maxf(_hint_t - delta, 0.0)
		if _hint_t == 0.0 and not (_dusk_active and _alerted and _choice == ""):
			_hint = ""
	_tick_warmth(delta)
	_tick_hunger(delta)
	_tick_pet_needs(delta)
	if _cinematic != "":
		_tick_cine(delta)
	elif _qte:
		_tick_qte(delta)
	elif _fork:
		_tick_fork(delta)
	elif not _naming:
		_tick_play(delta)
	_tick_pile(delta)
	_tick_sharks(delta)
	_tick_ring()
	_refresh_locks()
	_push_hud()
	_save_clock += delta
	if _save_clock > 5.0 and _cinematic == "":
		_save_clock = 0.0
		_save()


func skip_cinematic() -> void:
	if _cinematic == "wake":
		_finish_wake()
	elif _cinematic == "kill":
		_end_kill()
	elif _cinematic == "tame":
		_end_tame_cine()


func on_action() -> void:
	if _cinematic != "" or _naming or _fork or _qte:
		return
	if _collect_ready and _near(_sack.global_position, 3.4):
		_take_collect()
		return
	var node := _nearest_node(3.5)
	if not node.is_empty():
		_act_on_node(node)
		return
	if _step == "clearing":
		var pad := _nearest_pad(3.4)
		if pad >= 0:
			_choose_pad(pad)
			return
	if _step == "build" and _spot >= 0 and _near(_pad_position(_spot), 4.2):
		_try_start_build()
		return
	if _near(_pit_position(), 3.4) or (_step == "cook" and _fire_lit):
		if not _fire_lit and _research_done("fire"):
			_try_craft_fire()
			return
		if _fire_lit and _research_done("cooking") and _cook_possible():
			_cook()
			return
	if _food_total() > 0 and _hunger < 97.0:
		_eat()
		return
	if _pet_freed and _near(_pet.global_position, 2.4):
		on_pet()


func on_attack() -> void:
	if _cinematic != "" or _fork or _qte or _naming or _swing > 0.0:
		return
	if not _has_weapon():
		_show_hint("Axe.")
		return
	if _beast == null or not _beast.visible:
		return
	var dist := _flat(_player.global_position, _beast.global_position)
	if dist > 2.8:
		_move_goal = _beast.global_position
		return
	if not _creature_hostile:
		_creature_hostile = true
		if not _dusk_active:
			_creature_max = 4
			_creature_hp = 4
	if _attack_cd > 0.0:
		return
	_attack_cd = 0.48
	_swing = 0.42
	_play_clip("Jump")
	_play(SWING, -6.0, 1.0)
	_hurt_beast(1)


func on_tame() -> void:
	if _fork:
		_try_begin_tame()


func on_kill() -> void:
	if _fork:
		_begin_kill()


func on_qte_tap() -> void:
	if not _qte:
		return
	var period := float(_tuning.get("tame_period", 2.0))
	var marker := fposmod(_tame_phase, period) / period
	if marker >= 0.68 and marker <= 0.84:
		_tame_hits += 1
		_play(AUDIO + "crunch.ogg", -5.0, 1.0)
	else:
		_tame_misses += 1
		_play(AUDIO + "squeak.ogg", -8.0, 1.0)
		if _tame_misses >= int(_tuning.get("tame_misses", 3)):
			_fail_tame()


func on_name(text: String) -> void:
	var cleaned := text.strip_edges()
	if cleaned == "":
		cleaned = "Tide-Puck"
	_pet_stats["name"] = cleaned.substr(0, 16)
	_naming = false
	_note_burst(str(_pet_stats["name"]))
	_enter("eat")


func on_end_closed() -> void:
	_end_open = false
	_end_dismissed = true
	_save()


func on_research_toggle() -> void:
	_research_open = not _research_open


func on_pet_toggle() -> void:
	_pet_open = not _pet_open


func on_research(id: String) -> void:
	_start_research(id)


func on_feed_pet() -> void:
	if not _pet_freed:
		return
	if _food_total() < 1:
		_show_hint("Food.")
		_pointer_id = "bush"
		return
	_consume_one()
	_pet_stats["hunger"] = mini(100, int(_pet_stats["hunger"]) + 28)
	_pet_stats["mood"] = mini(100, int(_pet_stats["mood"]) + 12)
	_gain_xp(3)
	_play(AUDIO + "crunch.ogg", -6.0, 1.0)
	_play(AUDIO + "bark.ogg", -8.0, 1.0)
	_bounce(_pet)


func on_pet() -> void:
	if not _pet_freed:
		return
	_pet_stats["mood"] = mini(100, int(_pet_stats["mood"]) + 14)
	_gain_xp(1)
	_play(AUDIO + "bark.ogg", -8.0, 1.0)
	_bounce(_pet)


func _do_pet_alert() -> void:
	var hp := _creature_hp
	_alerted = true
	_hint = PET_DEFENCE_LINE
	_hint_t = 999.0
	_play(AUDIO + "bark.ogg", -4.0, 1.0)
	_gain_xp(2)
	_creature_hp = hp


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E, KEY_ENTER:
				if _qte:
					on_qte_tap()
				elif _naming:
					on_name(_hud._name_edit.text if _hud else "Tide-Puck")
				else:
					on_action()
			KEY_SPACE:
				if _qte:
					on_qte_tap()
				else:
					on_attack()
			KEY_J:
				on_attack()
			KEY_F:
				if _qte:
					on_qte_tap()
				else:
					on_feed_pet()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_tap(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_tap(event.position)


func _enter(step: String) -> void:
	if _loading:
		_step = step
		return
	_step = step
	_step_time = 0.0
	_line = _line_for(step)
	_pointer_id = str(_catalog.get("points", {}).get(step, _pointer_id))
	if step == "wake":
		_cinematic = "wake"
		_cine_age = 0.0
		if _player:
			_player.rotation.x = 1.05
		return
	if step == "axe" and bool(_tools.get("axe", false)):
		_note_burst("Axe")
		_enter("clearing")
		return
	if step == "fire" and _fire_lit:
		_note_burst("Warmth")
		_enter("cook")
		return
	if step == "research":
		_research_open = true
		if _research_done("building"):
			_note_burst("Basic Building")
			_enter("build")
			return
		if not _research_done("foraging"):
			_start_research("foraging")
	if step == "name_pet":
		_naming = true
	if step == "dusk":
		_begin_dusk()
	if step == "epilogue":
		_end_open = not _end_dismissed
		_pointer_id = "offshore"
	_herald(step)
	_save()


func _line_for(step: String) -> String:
	if step == "research" and _research_done("foraging") and not _research_done("building"):
		return "Build."
	if step == "fire" and _research_done("fire") and not _fire_lit:
		if int(_inv.get("flint", 0)) < 1 or int(_inv.get("wood", 0)) < 2:
			return "Flint."
		return "Pit."
	return str(_catalog.get("lines", {}).get(step, "Onward."))


func _herald(step: String) -> void:
	if step == "wake":
		return
	_heralds += 1
	_sniff_t = 1.25
	if _pet_freed:
		_play(AUDIO + "squeak.ogg", -10.0, 1.0)
	else:
		_play(AUDIO + "squeak.ogg", -8.0, 1.0)


func _finish_wake() -> void:
	_cinematic = ""
	if _player:
		_player.rotation.x = 0.0
		var wreck := _landmark_position("wreck")
		_player.look_at(Vector3(wreck.x, _player.position.y, wreck.z), Vector3.UP)
		_cam_yaw = _player.rotation.y
	_note_burst("Up")
	_enter("scavenge")


func _tick_cine(delta: float) -> void:
	_cine_age += delta
	if _cinematic == "wake":
		_wake_camera()
		if _cine_age > 8.2:
			_finish_wake()
	elif _cinematic == "kill":
		var real := delta / maxf(Engine.time_scale, 0.05)
		_cine_age += real - delta
		_kill_camera()
		_cine_left -= real
		if _cine_left <= 0.0:
			_end_kill()
	elif _cinematic == "tame":
		_tame_camera()
		_cine_left -= delta
		if _cine_left <= 0.0:
			_end_tame_cine()


func _wake_camera() -> void:
	var u := clampf(_cine_age / 8.2, 0.0, 1.0)
	if u < 0.62:
		var t := u / 0.62
		_camera.fov = 56.0
		_camera.global_position = Vector3(28, 18, 64).lerp(Vector3(-6, 8, 24), t)
		_camera.look_at(Vector3(8, 1.0, 48).lerp(_landmark_position("wreck"), t), Vector3.UP)
	else:
		_camera.fov = 38.0
		var eye := _player.global_position + Vector3(0, 1.45, 0.2)
		_camera.global_position = eye
		var look := _landmark_position("wreck") + Vector3(0, 1.2, 0) if _cine_age < 7.1 else _landmark_position("offshore")
		_camera.look_at(look, Vector3.UP)


func _kill_camera() -> void:
	_camera.fov = 42.0
	if _beast:
		_camera.global_position = _beast.global_position + Vector3(3.4, 1.15, 2.6)
		_camera.look_at(_beast.global_position + Vector3(0, 0.7, 0), Vector3.UP)


func _tame_camera() -> void:
	_camera.fov = 48.0
	if _beast:
		var orbit := _beast.global_position + Vector3(cos(_cine_age * 0.7) * 5.6, 2.3, sin(_cine_age * 0.7) * 5.6)
		_camera.global_position = orbit
		_camera.look_at(_beast.global_position + Vector3(0, 0.8, 0), Vector3.UP)


func _tick_qte(delta: float) -> void:
	_tame_phase += delta
	_tame_left -= delta
	_beast_wobble()
	_follow_camera(delta)
	if _tame_left <= 0.0:
		var need := int(_tuning.get("tame_hits", 5))
		if _tame_hits >= need:
			_complete_tame(-1.0)
		else:
			_fail_tame()


func _tick_fork(delta: float) -> void:
	_beast_wobble()
	_follow_camera(delta)


func _tick_play(delta: float) -> void:
	_step_time += delta
	_swing = maxf(_swing - delta, 0.0)
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	if _swing <= 0.0:
		_tick_move(delta)
	_tick_beast(delta)
	if _choice != "tame":
		_beast_wobble()
	_tick_gatherer(delta)
	_tick_research(delta)
	_tick_build(delta)
	_tick_respawn(delta)
	_tick_alert()
	_follow_camera(delta)
	_refresh_locks()
	if _step == "scavenge" and _step_time > 24.0:
		_note_burst("Wreck")
		_enter("free_pet")
	_wet_tint()


func _tick_move(delta: float) -> void:
	var input := _keyboard()
	if _hud and _hud.has_method("stick"):
		input += _hud.stick()
	if input.length() > 1.0:
		input = input.normalized()
	if _move_goal.is_finite():
		var to := _move_goal - _player.position
		to.y = 0.0
		if to.length() < 2.45:
			var goal := _move_node
			_move_goal = Vector3(INF, INF, INF)
			_move_node = {}
			if not goal.is_empty():
				_act_on_node(goal)
			return
		_slide(Vector3(to.x, 0, to.z).normalized(), delta, true)
		_play_clip("Run")
		return
	if input.length() < 0.12:
		_play_clip("Idle")
		_player.position.y = _ground_y(_player.position.x, _player.position.z)
		return
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, _cam_yaw)
	_slide(dir, delta, true)
	_play_clip("Run")


func _slide(dir: Vector3, delta: float, face: bool) -> void:
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var next := _player.position + dir * 5.3 * delta
	var y := _ground_y(next.x, next.z)
	if y < 0.22:
		_show_hint(OFFSHORE_WARNING)
		return
	next.y = y
	if _warmth < 42.0:
		next.y += sin(_age * 16.0) * 0.015
	_player.position = next
	if face:
		var at := _player.global_position + dir
		at.y = _player.global_position.y
		_player.look_at(at, Vector3.UP)


func _keyboard() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1.0
	return v


func _follow_camera(delta: float) -> void:
	if _camera == null or _player == null:
		return
	_camera.fov = lerpf(_camera.fov, 58.0, clampf(delta * 3.0, 0.0, 1.0))
	var back := Basis(Vector3.UP, _cam_yaw).z
	var want := _player.global_position + back * 7.0 + Vector3.UP * 4.2
	var gy := maxf(_ground_y(want.x, want.z), _ground_y(lerpf(want.x, _player.global_position.x, 0.5), lerpf(want.z, _player.global_position.z, 0.5)))
	if want.y < gy + 1.8:
		want.y = gy + 1.8
	var blend := 1.0 - exp(-delta * 4.0)
	_camera.global_position = _camera.global_position.lerp(want, blend)
	_camera.look_at(_player.global_position + Vector3.UP * 2.0, Vector3.UP)


func _tap(screen: Vector2) -> void:
	if _cinematic != "" or _naming or _fork or _qte or _camera == null:
		return
	var from := _camera.project_ray_origin(screen)
	var to := from + _camera.project_ray_normal(screen) * 90.0
	if _collect_ready and _ray_dist(from, to, _sack.global_position) < 1.6:
		if _near(_sack.global_position, 3.4):
			_take_collect()
		else:
			_move_goal = _sack.global_position
		return
	if _pet_freed and _ray_dist(from, to, _pet.global_position) < 1.1:
		on_pet()
		return
	var best: Dictionary = {}
	var best_d := 1.8
	for node in _nodes:
		if bool(node.get("depleted", false)):
			continue
		var dist := _ray_dist(from, to, (node.get("root") as Node3D).global_position)
		if dist < best_d:
			best_d = dist
			best = node
	if best.is_empty():
		return
	if _flat(_player.global_position, (best.get("root") as Node3D).global_position) < 3.5:
		_act_on_node(best)
	else:
		_move_goal = (best.get("root") as Node3D).global_position
		_move_node = best


func _act_on_node(node: Dictionary) -> void:
	if node.is_empty() or bool(node.get("depleted", false)):
		return
	var id := str(node.get("id", ""))
	if id == "pet_pile":
		if not _pet_freed:
			_free_pet()
		return
	var requires := str(node.get("requires", ""))
	if requires != "" and not _research_done(requires):
		_show_hint("Locked")
		_play(AUDIO + "squeak.ogg", -10.0, 1.0)
		return
	var tool := str(node.get("tool", ""))
	if tool != "" and not bool(_tools.get(tool, false)):
		_show_hint("Needs an axe" if tool == "axe" else "Needs a pick")
		_play(AUDIO + "squeak.ogg", -10.0, 1.0)
		return
	_swing = 0.45
	_play_clip("Jump")
	var kind := str(node.get("kind", ""))
	_play(AUDIO + ("chop.ogg" if kind == "tree" else "punch.ogg"), -4.0, 1.0)
	_shake(node.get("root"))
	var stage := int(node.get("stage", 0))
	var loot: Array = node.get("loot", [])
	if stage < loot.size() and loot[stage] is Array:
		for item in loot[stage]:
			_give(str(item.get("id", "")), int(item.get("amount", 1)), (node.get("root") as Node3D).global_position)
	node["stage"] = stage + 1
	_apply_stage(node)
	if int(node["stage"]) >= int(node.get("stages", 1)):
		node["depleted"] = true
		node["left"] = float(node.get("respawn", 42.0))
		(node.get("root") as Node3D).visible = false
	if _step == "scavenge" and id in WRECK_IDS:
		_note_burst("Planks")
		_enter("free_pet")
	elif id == "cargo_tools" and _step == "axe" and bool(_tools.get("axe", false)):
		_note_burst("Axe")
		_enter("clearing")


func _free_pet() -> void:
	_pet_freed = true
	_pet.visible = true
	_pet.global_position = _player.global_position + Vector3(-1.1, 0, 0.8)
	_pet.position.y = _ground_y(_pet.position.x, _pet.position.z)
	_note_burst("Friend")
	_enter("name_pet")


func _give(id: String, amount: int, from: Vector3) -> void:
	if id in TOOL_IDS:
		if not bool(_tools.get(id, false)):
			_tools[id] = true
			_note_burst(id.capitalize())
		_refresh_locks()
	else:
		_inv[id] = int(_inv.get(id, 0)) + amount
		_fly(id, amount, from)
	if _step == "eat" and id in FOOD_IDS:
		if int(_inv.get(id, 0)) > 0:
			_inv[id] = int(_inv[id]) - 1
		_hunger = minf(100.0, _hunger + (40.0 if id == "cooked" else 22.0))
		_play(AUDIO + "crunch.ogg", -5.0, 1.0)
		_note_burst("+Hunger")
		_enter("axe")


func _eat() -> bool:
	var id := _consume_one()
	if id == "":
		_show_hint("Food.")
		return false
	_hunger = minf(100.0, _hunger + (40.0 if id == "cooked" else 22.0))
	_play(AUDIO + "crunch.ogg", -5.0, 1.0)
	_note_burst("+Hunger")
	if _step == "eat":
		_enter("axe")
	return true


func _choose_pad(index: int) -> void:
	_spot = index
	_move_hut()
	_note_burst("Camp")
	_enter("research")


func _try_start_build() -> void:
	if _building or _hut_stage >= 3:
		return
	if not _research_done("building"):
		_show_hint("Build.")
		_research_open = true
		return
	if not _can_pay("hut"):
		_show_hint(_missing("hut").capitalize() + ".")
		_pointer_id = "wreck"
		return
	_pay("hut")
	_building = true
	_build_total = float(_catalog.get("recipes", {}).get("hut", {}).get("seconds", 12.0))
	_build_left = _build_total
	_hut_stage = 0
	_show_hut(0)


func _try_craft_fire() -> void:
	if _fire_lit:
		return
	if not _research_done("fire"):
		_show_hint("Fire.")
		_research_open = true
		return
	if not _can_pay("campfire"):
		_show_hint("Flint.")
		_pointer_id = "flint" if int(_inv.get("flint", 0)) < 1 else "drift"
		return
	_pay("campfire")
	_light_fire()
	_note_burst("Warmth")
	if _step == "fire":
		_enter("cook")


func _cook_possible() -> bool:
	if _step in ["cook", "fire"]:
		return true
	for id in RAW_IDS:
		if int(_inv.get(id, 0)) > 0:
			return true
	return false


func _cook() -> bool:
	if not _fire_lit or not _research_done("cooking"):
		_show_hint("Cook.")
		_research_open = true
		return false
	var raw := ""
	for id in RAW_IDS:
		if int(_inv.get(id, 0)) > 0:
			raw = id
			break
	if raw == "":
		_show_hint("Food.")
		_pointer_id = "bush"
		return false
	_inv[raw] = int(_inv[raw]) - 1
	_give("cooked", 1, _pit_position())
	_play(AUDIO + "fire.ogg", -8.0, 1.0)
	if _step == "cook":
		_note_burst("Cooked")
		_enter("dusk")
	return true


func _light_fire() -> void:
	_fire_lit = true
	_mark_done("fire")
	if _flame:
		_flame.visible = true
		_flame.global_position = _pit_position()
		_flame.position.y = _ground_y(_flame.position.x, _flame.position.z) + 0.2
	if _guard_down and _camp_flame:
		_camp_flame.visible = false
	if _fire_loop and not _fire_loop.playing:
		_fire_loop.play()


func _begin_dusk() -> void:
	_dusk_active = true
	_alerted = false
	_creature_hostile = true
	_creature_max = 8
	_creature_hp = 8
	_stagger = false
	_beast.visible = true
	var from := _landmark_position("camp") if not _guard_down else Vector3(-20, 0, -8)
	from.y = _ground_y(from.x, from.z)
	_beast.global_position = from
	_apply_dusk_look()
	_play(ROAR, -6.0, 1.0)


func _tick_beast(delta: float) -> void:
	if _beast == null or not _beast.visible or not _creature_hostile or _stagger:
		return
	var bold := _dusk_active and not _fire_lit
	var speed := 3.2 * (1.5 if bold else 1.0)
	var reach := 2.35 * (1.4 if bold else 1.0)
	var to := _player.global_position - _beast.global_position
	to.y = 0.0
	if to.length() > reach:
		var step := to.normalized() * speed * delta
		var next := _beast.position + step
		next.y = _ground_y(next.x, next.z)
		_beast.position = next
		var face := _beast.global_position + step
		face.y = _beast.global_position.y
		_beast.look_at(face, Vector3.UP)
	else:
		_beast_cd -= delta
		if _beast_cd <= 0.0:
			_beast_cd = 0.9 if bold else 1.45
			_hurt_player(2 if bold else 1)
	var bar := _beast.get_node_or_null("HealthBar") as MeshInstance3D
	if bar:
		bar.visible = true
		bar.scale.x = clampf(float(_creature_hp) / float(maxi(_creature_max, 1)), 0.05, 1.0)


func _hurt_player(amount: int) -> void:
	_health -= amount
	_play(AUDIO + "punch.ogg", -6.0, 0.9)
	if _health <= 0:
		_health = 5
		_warmth = maxf(_warmth, 34.0)
		var spawn := Vector3(0, 0, 9)
		spawn.y = _ground_y(spawn.x, spawn.z)
		_player.position = spawn
		_show_hint("Cold.")


func _hurt_beast(amount: int) -> void:
	if _fork or _qte or _cinematic != "" or not _creature_hostile:
		return
	if _dusk_active:
		var thresh := maxi(2, int(ceil(float(_creature_max) * float(_tuning.get("fork_hp_fraction", 0.34)))))
		if _creature_hp - amount <= thresh:
			_creature_hp = thresh
			_stagger = true
			_open_fork()
			return
	_creature_hp -= amount
	_shake(_beast)
	if _creature_hp <= 0 and not _dusk_active:
		_creature_hp = 0
		_steal_fire()


func _steal_fire() -> void:
	_creature_hostile = false
	_guard_down = true
	_stagger = false
	if _beast:
		_beast.visible = false
	_light_fire()
	_note_burst("Fire")
	if _step == "fire":
		_enter("cook")


func _open_fork() -> void:
	_fork = true
	_qte = false
	_stagger = true
	_step = "dusk"
	_line = "Choose."
	_dusk_active = true
	if _creature_max < 6:
		_creature_max = 8


func _try_begin_tame() -> bool:
	if not _fork and _cinematic == "":
		return false
	if _food_total() < 1:
		_inv["food"] = int(_inv.get("food", 0)) + 1
		if _pet:
			_fly("food", 1, _pet.global_position)
	_consume_one()
	_fork = false
	_qte = true
	_tame_total = tame_window()
	_tame_left = _tame_total
	_tame_hits = 0
	_tame_misses = 0
	_tame_phase = 0.0
	_play(AUDIO + "crunch.ogg", -8.0, 1.0)
	return true


func _fail_tame() -> void:
	_qte = false
	_fork = false
	_stagger = false
	_creature_hostile = true
	_creature_hp = maxi(_creature_hp, int(round(float(_creature_max) * 0.62)))
	_step = "dusk"
	_line = "Dusk."
	_show_hint("It fights.")


func _complete_tame(roll: float) -> void:
	_qte = false
	_fork = false
	_stagger = false
	_choice = "tame"
	_gatherer = true
	_creature_hostile = false
	_rare = _roll_rare(roll)
	_paint_beast(_rare)
	_cinematic = "tame"
	_cine_age = 0.0
	_cine_left = 4.6 if _rare else 3.2
	_note_burst("RARE!" if _rare else "Tamed")
	_play(CHEER if _rare else AUDIO + "bark.ogg", -4.0, 1.0)
	_save()


func _roll_rare(roll: float) -> bool:
	var sample := randf() if roll < 0.0 else roll
	return sample < float(_tuning.get("rare_chance", 0.12))


func _end_tame_cine() -> void:
	_cinematic = ""
	_spawn_collect()


func _begin_kill() -> void:
	_fork = false
	_stagger = false
	_choice = "kill"
	_gatherer = false
	_creature_hostile = false
	_creature_hp = 0
	_cinematic = "kill"
	_cine_age = 0.0
	_cine_left = 1.6
	_kill_rewarded = false
	Engine.time_scale = 0.3
	if _beast and _beast_anim == null:
		_beast.rotation.z = 1.15
	elif _beast_anim:
		_clip(_beast_anim, "Death")
	_save()


func _end_kill() -> void:
	Engine.time_scale = 1.0
	_cinematic = ""
	if not _kill_rewarded:
		_kill_rewarded = true
		_hunger = 100.0
		_give("meat", 8, _beast.global_position if _beast else _player.global_position)
		_note_burst("Meat")
		_play(AUDIO + "punch.ogg", -3.0, 0.85)
	if _beast:
		_beast.visible = false
	_spawn_collect()


func _spawn_collect() -> void:
	_collect_ready = true
	_collect_taken = false
	if _sack:
		_sack.visible = true
		var at := _beast.global_position + Vector3(1.4, 0, 0.6) if _choice == "tame" and _beast else _pit_position()
		at.y = _ground_y(at.x, at.z)
		_sack.global_position = at
	_step = "collect"
	_line = "Collect."
	_pointer_id = "collect"
	_herald("collect")
	_save()


func _take_collect() -> void:
	if not _collect_ready:
		return
	_collect_ready = false
	_collect_taken = true
	if _sack:
		_sack.visible = false
	var at := _sack.global_position if _sack else _player.global_position
	if _choice == "tame":
		_give("wood", 3, at)
		_give("food", 2, at)
	else:
		_give("planks", 2, at)
		_give("food", 2, at)
	_note_burst("Supplies")
	_enter("epilogue")


func _tick_gatherer(delta: float) -> void:
	if not _gatherer or _beast == null or not _beast.visible:
		return
	_gather_cd -= delta
	var target := _gather_target()
	if target.is_empty():
		_follow_player(_beast, delta, 2.4)
		return
	var root := target.get("root") as Node3D
	var to := root.global_position - _beast.global_position
	to.y = 0.0
	if to.length() > 1.8:
		var step := to.normalized() * 3.4 * delta
		var next := _beast.position + step
		next.y = _ground_y(next.x, next.z)
		_beast.position = next
		return
	if _gather_cd > 0.0:
		return
	_gather_cd = 4.2
	_shake(root)
	var stage := int(target.get("stage", 0))
	var loot: Array = target.get("loot", [])
	if stage < loot.size() and loot[stage] is Array:
		for item in loot[stage]:
			var id := str(item.get("id", ""))
			if id in ["wood", "food", "fish"]:
				_give(id, int(item.get("amount", 1)), root.global_position)
	target["stage"] = stage + 1
	_apply_stage(target)
	if int(target["stage"]) >= int(target.get("stages", 1)):
		target["depleted"] = true
		target["left"] = float(target.get("respawn", 42.0))
		root.visible = false
	_play(AUDIO + "punch.ogg", -10.0, 1.1)


func _gather_target() -> Dictionary:
	var best: Dictionary = {}
	var best_d := 80.0
	for node in _nodes:
		if bool(node.get("depleted", false)):
			continue
		var kind := str(node.get("kind", ""))
		if kind not in ["tree", "bush", "crab", "fish", "drift"]:
			continue
		var requires := str(node.get("requires", ""))
		if requires != "" and not _research_done(requires):
			continue
		var dist := _flat(_beast.global_position, (node.get("root") as Node3D).global_position)
		if dist < best_d:
			best_d = dist
			best = node
	return best


func _tick_research(delta: float) -> void:
	if _running == "":
		return
	_research_left -= delta
	if _research_left <= 0.0:
		_finish_research(_running)


func _start_research(id: String) -> void:
	if _running != "" or _research_done(id):
		return
	var row := _research_row(id)
	if row.is_empty() or bool(row.get("locked", false)):
		return
	for need in row.get("requires", []):
		if not _research_done(str(need)):
			return
	_running = id
	_research_left = float(row.get("seconds", 12.0))
	_research_open = true


func _finish_research(id: String) -> void:
	_running = ""
	_mark_done(id)
	_note_burst(str(_research_row(id).get("title", id)))
	_play(AUDIO + "punch.ogg", -6.0, 1.15)
	if id == "foraging":
		_line = "Build."
		_pointer_id = "bush_b"
		_refresh_locks()
	elif id == "building" and _step == "research":
		_enter("build")
	elif id == "fire":
		_line = _line_for("fire")
	elif id == "cooking" and _step == "cook":
		_line = "Cook."
	_save()


func _tick_build(delta: float) -> void:
	if not _building:
		return
	if not _near(_pad_position(_spot), 4.6):
		_show_hint("Hut.")
		return
	_build_left -= delta
	var elapsed := _build_total - _build_left
	var stage := clampi(int(elapsed / maxf(_build_total / 3.0, 0.1)) + 1, 1, 3)
	if stage != _hut_stage:
		_hut_stage = stage
		_show_hut(stage)
		var words := ["Frame", "Walls", "Roof"]
		_note_burst(words[stage - 1])
		_play(AUDIO + "punch.ogg", -5.0, 1.0)
	if _build_left <= 0.0:
		_building = false
		_shelter = true
		_hut_stage = 3
		_show_hut(3)
		_note_burst("Shelter")
		_enter("fire")


func _tick_respawn(delta: float) -> void:
	for node in _nodes:
		if not bool(node.get("depleted", false)):
			continue
		if str(node.get("id", "")) == "pet_pile":
			continue
		node["left"] = float(node.get("left", 0.0)) - delta
		if float(node["left"]) <= 0.0:
			node["depleted"] = false
			node["stage"] = 0
			(node.get("root") as Node3D).visible = true
			_apply_stage(node)


func _tick_alert() -> void:
	if not _dusk_active or not _pet_freed or _choice != "" or _beast == null:
		return
	if _flat(_player.global_position, _beast.global_position) > 18.0:
		return
	if not _alerted:
		_do_pet_alert()


func _tick_warmth(delta: float) -> void:
	if _fire_lit and not (_dusk_active and false):
		_warmth = minf(100.0, _warmth + 8.0 * delta)
		return
	var drain := float(_tuning.get("warmth_drain", 0.12))
	if _dusk_active and not _fire_lit:
		drain = float(_tuning.get("warmth_drain_dusk", 0.55))
	elif _shelter:
		drain = float(_tuning.get("warmth_drain_shelter", 0.03))
	_warmth -= drain * delta
	if _warmth <= 0.0:
		var late := _step in ["research", "build", "fire", "cook"]
		_warmth = 32.0
		_health = maxi(_health - 1, 1)
		_show_hint("Cold.")
		if late and not _dusk_active and _choice == "":
			_enter("dusk")


func _tick_hunger(delta: float) -> void:
	_hunger = maxf(0.0, _hunger - float(_tuning.get("hunger_drain", 0.04)) * delta)


func _tick_pet_needs(delta: float) -> void:
	if not _pet_freed:
		return
	_pet_stats["hunger"] = maxi(0, int(_pet_stats["hunger"]) - (1 if _age - floor(_age) < delta else 0))
	if _sniff_t > 0.0 and _pet_head:
		_sniff_t -= delta
		_pet_head.rotation.x = sin(_age * 9.0) * 0.45
	elif _pet_head:
		_pet_head.rotation.x = 0.0
	if _cinematic == "" and not _naming and _pet:
		_follow_player(_pet, delta, 1.35)


func _follow_player(body: Node3D, delta: float, gap: float) -> void:
	var back := _player.global_transform.basis.z * gap + _player.global_transform.basis.x * 0.7
	var goal := _player.position + back
	goal.y = _ground_y(goal.x, goal.z)
	body.position = body.position.lerp(goal, clampf(delta * 3.0, 0.0, 1.0))
	if body == _beast and _beast_anim:
		_clip(_beast_anim, "Walk" if body.position.distance_to(goal) > 0.35 else "Idle")
	if body == _pet and _pet_anim:
		_clip(_pet_anim, "Walk" if body.position.distance_to(goal) > 0.35 else ("Yes" if _sniff_t > 0.0 else "Idle"))
	if body.position.distance_to(goal) > 0.2:
		var face := body.global_position + (goal - body.position)
		face.y = body.global_position.y
		body.look_at(face, Vector3.UP)


func _tick_pile(delta: float) -> void:
	var pile := _node_by_id("pet_pile")
	if pile.is_empty() or _pet_freed:
		return
	var root := pile.get("root") as Node3D
	root.rotation.y = sin(_age * 11.0) * 0.12
	if _step == "wake":
		return
	_squeak_t -= delta
	if _squeak_t <= 0.0:
		_squeak_t = 2.6
		_play(AUDIO + "squeak.ogg", -9.0, 1.0)


func _tick_sharks(delta: float) -> void:
	var i := 0
	for fin in _sharks:
		var t := _age * 0.65 + float(i) * 2.1
		fin.position = Vector3(cos(t) * (7.0 + float(i)), 0.35, sin(t * 0.8) * 5.0)
		fin.rotation.y = t
		i += 1


func _tick_ring() -> void:
	if _ring == null:
		return
	var node := _nearest_node(3.6)
	if node.is_empty() or bool(node.get("depleted", false)) or _cinematic != "":
		_ring.visible = false
		return
	var root := node.get("root") as Node3D
	_ring.visible = true
	_ring.global_position = root.global_position + Vector3(0, 0.15, 0)
	var scale := float(node.get("scale", 2.0))
	_ring.scale = Vector3(scale * 0.55, scale * 0.55, scale * 0.55)


func _prompt_style(label: Label3D, scale: float) -> void:
	label.font_size = 40
	label.pixel_size = 0.0055 / maxf(scale, 0.4)
	label.outline_size = 10
	label.outline_modulate = Color(0.02, 0.05, 0.08, 0.85)
	label.no_depth_test = true


func _refresh_locks() -> void:
	var target := _nearest_node(3.6)
	var target_root: Node3D = target.get("root") as Node3D if not target.is_empty() else null
	for node in _nodes:
		var title_label := (node.get("root") as Node3D).get_node_or_null("Title") as Label3D
		if title_label:
			title_label.visible = target_root != null and node.get("root") == target_root and _cinematic == "" and not bool(node.get("depleted", false))
		var lock := (node.get("root") as Node3D).get_node_or_null("Lock") as Label3D
		if lock == null:
			continue
		var text := ""
		var tool := str(node.get("tool", ""))
		var requires := str(node.get("requires", ""))
		if tool == "axe" and not bool(_tools.get("axe", false)):
			text = "Needs an axe"
		elif tool == "pick" and not bool(_tools.get("pick", false)):
			text = "Needs a pick"
		elif requires != "" and not _research_done(requires):
			text = "Locked"
		lock.visible = text != "" and target_root != null and node.get("root") == target_root
		lock.text = text


func _beast_wobble() -> void:
	if _beast == null:
		return
	if _beast_anim:
		if _choice == "kill" or _creature_hp <= 0:
			_clip(_beast_anim, "Death")
		elif _stagger or _fork:
			_clip(_beast_anim, "Idle", 0.5)
		elif _creature_hostile:
			_clip(_beast_anim, "Run" if _flat(_beast.global_position, _player.global_position) > 2.2 else "Punch")
		else:
			_clip(_beast_anim, "Idle")
	else:
		_beast.rotation.z = sin(_age * 8.0) * 0.18


func _apply_dusk_look() -> void:
	if _sky:
		_sky.set_shader_parameter("storm", 0.62)
	if _sun:
		_sun.light_energy = 0.62
		_sun.light_color = Color(1.0, 0.58, 0.32)
	if _env:
		_env.fog_light_color = Color(0.45, 0.32, 0.28)
		_env.tonemap_exposure = 0.82
		_env.adjustment_saturation = 1.05


func _wet_tint() -> void:
	var wet := clampf(1.0 - _warmth / 80.0, 0.0, 1.0)
	var tint := Color(1, 1, 1).lerp(Color(0.62, 0.74, 0.84), wet)
	for mat in _skin:
		var base: Color = mat.get_meta("base", Color(1, 1, 1))
		mat.albedo_color = base * tint


func _show_hint(text: String) -> void:
	_hint = text
	_hint_t = 1.8


func _note_burst(text: String) -> void:
	if _hud and _hud.has_method("note_burst"):
		_hud.note_burst(text)


func _fly(kind: String, amount: int, from: Vector3) -> void:
	if _hud == null or _camera == null or not _hud.has_method("note_fly"):
		return
	if _camera.is_position_behind(from):
		return
	_hud.note_fly(_camera.unproject_position(from), kind, amount)


func _play(path: String, db: float, pitch: float) -> void:
	if _voices.is_empty():
		return
	var voice := _voices[_voice_i]
	_voice_i = (_voice_i + 1) % _voices.size()
	var stream = load(path)
	if stream == null:
		return
	voice.stream = stream.duplicate()
	voice.volume_db = db
	voice.pitch_scale = pitch
	voice.play()


func _play_clip(clip_name: String) -> void:
	if _anim and _anim.has_animation("ashore/" + clip_name):
		_clip(_anim, clip_name)
	elif _anim and _anim.has_animation(clip_name) and _anim.current_animation != clip_name:
		_anim.play(clip_name)


func _nearest_node(radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius
	for node in _nodes:
		if bool(node.get("depleted", false)):
			continue
		var dist := _flat(_player.global_position, (node.get("root") as Node3D).global_position)
		if dist < best_d:
			best_d = dist
			best = node
	return best


func _node_by_id(id: String) -> Dictionary:
	for node in _nodes:
		if str(node.get("id", "")) == id:
			return node
	return {}


func _near(point: Vector3, radius: float) -> bool:
	return _flat(_player.global_position, point) <= radius


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _ray_dist(from: Vector3, to: Vector3, point: Vector3) -> float:
	var dir := to - from
	var length := dir.length()
	if length < 0.001:
		return 999.0
	dir /= length
	var along := (point - from).dot(dir)
	if along < 0.0 or along > length:
		return 999.0
	return point.distance_to(from + dir * along)


func _food_total() -> int:
	var total := 0
	for id in FOOD_IDS:
		total += int(_inv.get(id, 0))
	return total


func _consume_one() -> String:
	for id in FOOD_IDS:
		if int(_inv.get(id, 0)) > 0:
			_inv[id] = int(_inv[id]) - 1
			return id
	return ""


func _has_weapon() -> bool:
	return bool(_tools.get("knife", false) or _tools.get("axe", false) or _tools.get("club", false))


func _can_pay(recipe_name: String) -> bool:
	return _missing(recipe_name) == ""


func _missing(recipe_name: String) -> String:
	var recipe: Dictionary = _catalog.get("recipes", {}).get(recipe_name, {})
	for key in recipe.keys():
		if str(key) == "seconds":
			continue
		if int(_inv.get(key, 0)) < int(recipe[key]):
			return str(key)
	return ""


func _pay(recipe_name: String) -> void:
	var recipe: Dictionary = _catalog.get("recipes", {}).get(recipe_name, {})
	for key in recipe.keys():
		if str(key) == "seconds":
			continue
		_inv[key] = int(_inv.get(key, 0)) - int(recipe[key])


func _prereq_met(row: Dictionary) -> bool:
	for need in row.get("requires", []):
		if not _research_done(str(need)):
			return false
	return true


func _research_done(id: String) -> bool:
	var row := _research_row(id)
	return not row.is_empty() and bool(row.get("done", false))


func _research_row(id: String) -> Dictionary:
	for row in _research:
		if str(row.get("id", "")) == id:
			return row
	return {}


func _mark_done(id: String) -> void:
	var row := _research_row(id)
	if not row.is_empty():
		row["done"] = true
	if _running == id:
		_running = ""


func _gain_xp(amount: int) -> void:
	_pet_stats["xp"] = int(_pet_stats.get("xp", 0)) + amount
	var need := 8 * int(_pet_stats.get("level", 1))
	if int(_pet_stats["xp"]) >= need:
		_pet_stats["xp"] = int(_pet_stats["xp"]) - need
		_pet_stats["level"] = int(_pet_stats["level"]) + 1
		_note_burst("Level %d" % int(_pet_stats["level"]))


func _landmark_position(id: String) -> Vector3:
	var pair: Array = _catalog.get("landmarks", {}).get(id, [0, 0])
	return _on_land(float(pair[0]), float(pair[1])) if id != "offshore" else Vector3(float(pair[0]), -0.6, float(pair[1]))


func _pad_position(index: int) -> Vector3:
	var clearing := _landmark_position("clearing")
	var offsets := [Vector3(-3.2, 0, 0.4), Vector3(0.2, 0, -2.4), Vector3(3.4, 0, 0.8)]
	var at: Vector3 = clearing + offsets[clampi(index, 0, 2)]
	at.y = _ground_y(at.x, at.z)
	return at


func _nearest_pad(radius: float) -> int:
	var best := -1
	var best_d := radius
	for i in 3:
		var dist := _flat(_player.global_position, _pad_position(i))
		if dist < best_d:
			best_d = dist
			best = i
	return best


func _pit_position() -> Vector3:
	if _spot >= 0:
		var at := _pad_position(_spot) + Vector3(2.4, 0, 1.6)
		at.y = _ground_y(at.x, at.z)
		return at
	var camp := _landmark_position("camp") + Vector3(-2.6, 0, 2.2)
	camp.y = _ground_y(camp.x, camp.z)
	return camp


func _point_position() -> Vector3:
	if _pointer_id == "pet" and _pet:
		return _pet.global_position
	if _pointer_id == "collect" and _sack:
		return _sack.global_position
	if _pointer_id == "clearing":
		return _landmark_position("clearing")
	if _pointer_id == "offshore":
		return _landmark_position("offshore")
	if _pointer_id in ["wreck", "grove", "camp"]:
		return _landmark_position(_pointer_id)
	var node := _node_by_id(_pointer_id)
	if not node.is_empty():
		return (node.get("root") as Node3D).global_position
	return _landmark_position("wreck")


func _on_land(x: float, z: float) -> Vector3:
	var y := _ground_y(x, z)
	var guard := 0
	while y < 0.28 and guard < 10:
		z -= 1.4
		y = _ground_y(x, z)
		guard += 1
	return Vector3(x, y, z)


func _ground_y(x: float, z: float) -> float:
	var dx := x / 36.0
	var dz := (z - 4.0) / 32.0
	var e := dx * dx + dz * dz
	if e > 1.28:
		return -2.2
	var inland := clampf((18.0 - z) / 24.0, 0.0, 1.0)
	var h := 0.22 + inland * 1.15
	var ridge := clampf((z + 2.0) / -22.0, 0.0, 1.0) * 6.5
	h += ridge * clampf(1.2 - e, 0.0, 1.0)
	var clear := Vector2(x - 1.0, z + 13.0).length()
	if clear < 10.0:
		h = lerpf(h, 1.62, clampf((10.0 - clear) / 6.0, 0.0, 1.0))
	var camp := Vector2(x - 17.0, z + 7.0).length()
	if camp < 8.0:
		h = lerpf(h, 2.55, clampf((8.0 - camp) / 5.0, 0.0, 1.0))
	if e > 0.55:
		h = lerpf(h, -1.2, clampf((e - 0.55) / 0.57, 0.0, 1.0))
	return h


func _load_catalog() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("Washed ashore catalog missing")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_catalog = parsed
	_tuning = _catalog.get("tuning", {})
	for row in _catalog.get("research", []):
		_research.append({
			"id": str(row.get("id", "")),
			"title": str(row.get("title", "")),
			"seconds": float(row.get("seconds", 12.0)),
			"requires": row.get("requires", []),
			"locked": bool(row.get("locked", false)),
			"done": false,
		})


func _read_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var raw = cfg.get_value("ashore", "state", "")
	if raw is String and raw != "":
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			_saved = parsed


func _save() -> void:
	if _loading or _player == null:
		return
	var nodes: Array = []
	for node in _nodes:
		nodes.append({
			"id": node.get("id", ""),
			"stage": node.get("stage", 0),
			"left": node.get("left", 0.0),
			"depleted": node.get("depleted", false),
		})
	var state := {
		"step": _step,
		"inv": _inv.duplicate(),
		"tools": _tools.duplicate(),
		"running": _running,
		"research_left": _research_left,
		"done": _done_ids(),
		"pet": _pet_stats.duplicate(),
		"pet_freed": _pet_freed,
		"warmth": _warmth,
		"hunger": _hunger,
		"health": _health,
		"fire": _fire_lit,
		"shelter": _shelter,
		"choice": _choice,
		"rare": _rare,
		"gatherer": _gatherer,
		"collect_taken": _collect_taken,
		"collect_ready": _collect_ready,
		"end_dismissed": _end_dismissed,
		"spot": _spot,
		"hut": _hut_stage,
		"building": _building,
		"build_left": _build_left,
		"kill_rewarded": _kill_rewarded,
		"guard_down": _guard_down,
		"dusk": _dusk_active,
		"pos": [_player.position.x, _player.position.y, _player.position.z],
		"nodes": nodes,
	}
	var cfg := ConfigFile.new()
	cfg.set_value("ashore", "state", JSON.stringify(state))
	cfg.save(SAVE_PATH)


func _done_ids() -> Array:
	var ids: Array = []
	for row in _research:
		if bool(row.get("done", false)):
			ids.append(row.get("id", ""))
	return ids


func _apply_save(state: Dictionary) -> void:
	_loading = true
	_step = str(state.get("step", "scavenge"))
	if _step == "wake":
		_step = "scavenge"
	for key in _inv.keys():
		if state.get("inv", {}).has(key):
			_inv[key] = int(state["inv"][key])
	for key in _tools.keys():
		if state.get("tools", {}).has(key):
			_tools[key] = bool(state["tools"][key])
	for id in state.get("done", []):
		_mark_done(str(id))
	_running = str(state.get("running", ""))
	_research_left = float(state.get("research_left", 0.0))
	if state.get("pet", {}) is Dictionary:
		for key in _pet_stats.keys():
			if state["pet"].has(key):
				_pet_stats[key] = state["pet"][key]
	_pet_freed = bool(state.get("pet_freed", false))
	_warmth = float(state.get("warmth", _warmth))
	_hunger = float(state.get("hunger", _hunger))
	_health = int(state.get("health", _health))
	_fire_lit = bool(state.get("fire", false))
	_shelter = bool(state.get("shelter", false))
	_choice = str(state.get("choice", ""))
	_rare = bool(state.get("rare", false))
	_gatherer = bool(state.get("gatherer", false))
	_collect_taken = bool(state.get("collect_taken", false))
	_collect_ready = bool(state.get("collect_ready", false)) and not _collect_taken
	_end_dismissed = bool(state.get("end_dismissed", false))
	_spot = int(state.get("spot", -1))
	_hut_stage = int(state.get("hut", 0))
	_building = bool(state.get("building", false)) and _hut_stage < 3 and _spot >= 0
	_build_left = float(state.get("build_left", 0.0))
	_kill_rewarded = bool(state.get("kill_rewarded", false))
	_guard_down = bool(state.get("guard_down", false))
	_dusk_active = bool(state.get("dusk", false))
	_cinematic = ""
	var pos: Array = state.get("pos", [])
	if pos.size() == 3:
		_player.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	for saved in state.get("nodes", []):
		var node := _node_by_id(str(saved.get("id", "")))
		if node.is_empty():
			continue
		node["stage"] = int(saved.get("stage", 0))
		node["left"] = float(saved.get("left", 0.0))
		node["depleted"] = bool(saved.get("depleted", false))
		(node.get("root") as Node3D).visible = not bool(node["depleted"])
		_apply_stage(node)
	if _pet_freed:
		_pet.visible = true
	if _spot >= 0:
		_move_hut()
	_show_hut(_hut_stage)
	_shelter = _hut_stage >= 3
	if _fire_lit:
		_light_fire()
	if _choice == "kill" and _beast:
		_beast.visible = false
	elif _beast:
		_beast.visible = true
		_paint_beast(_rare)
		_creature_hostile = _dusk_active and _choice == ""
	if _collect_ready and _sack:
		_sack.visible = true
	_line = _line_for(_step)
	_pointer_id = str(_catalog.get("points", {}).get(_step, "wreck"))
	_naming = _step == "name_pet"
	_end_open = _step == "epilogue" and not _end_dismissed
	_research_open = _step in ["research", "fire", "cook"]
	if _dusk_active and _choice == "":
		_apply_dusk_look()
		_creature_max = 8
	_loading = false
	if _player:
		_cam_yaw = _player.rotation.y
	if _step == "dusk" and _choice in ["kill", "tame"] and not _collect_taken:
		call_deferred("_resume_outcome")


func _resume_outcome() -> void:
	if _choice == "kill":
		_end_kill()
	elif _choice == "tame":
		if _beast:
			_beast.visible = true
		_end_tame_cine()


func _build_audio() -> void:
	for i in 4:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % i
		add_child(voice)
		_voices.append(voice)
	_ocean = AudioStreamPlayer.new()
	_ocean.name = "Ocean"
	var ocean = load(OCEAN)
	if ocean:
		ocean = ocean.duplicate()
		if ocean is AudioStreamOggVorbis:
			ocean.loop = true
		_ocean.stream = ocean
		_ocean.volume_db = -14.0
		add_child(_ocean)
		_ocean.play()
	_fire_loop = AudioStreamPlayer.new()
	_fire_loop.name = "FireLoop"
	var fire = load(AUDIO + "fire.ogg")
	if fire:
		fire = fire.duplicate()
		if fire is AudioStreamOggVorbis:
			fire.loop = true
		_fire_loop.stream = fire
		_fire_loop.volume_db = -16.0
	add_child(_fire_loop)


func _build_world() -> void:
	var world := WorldEnvironment.new()
	world.name = "World"
	_env = Environment.new()
	_sky = ShaderMaterial.new()
	_sky.shader = load("res://shaders/ashore_sky.gdshader")
	_sky.set_shader_parameter("storm", 0.0)
	_sky.set_shader_parameter("sun_direction", Vector3(0.42, 0.62, 0.28))
	var sky := Sky.new()
	sky.sky_material = _sky
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.75
	_env.ambient_light_sky_contribution = 0.75
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 0.9
	_env.tonemap_white = 6.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.22
	_env.adjustment_contrast = 1.1
	_env.adjustment_brightness = 1.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.22
	_env.glow_strength = 0.6
	_env.glow_bloom = 0.04
	_env.glow_hdr_threshold = 1.3
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_light_color = Color(0.66, 0.84, 1.0)
	_env.fog_density = 0.0009
	_env.fog_depth_begin = 55.0
	_env.fog_depth_end = 260.0
	_env.fog_depth_curve = 1.6
	_env.fog_sky_affect = 0.15
	world.environment = _env
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-48, -36, 0)
	_sun.light_color = Color(1.0, 0.86, 0.64)
	_sun.light_energy = 1.05
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 80.0
	_sun.shadow_bias = 0.08
	_sun.light_angular_distance = 0.5
	add_child(_sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-28, 140, 0)
	fill.light_color = Color(0.55, 0.75, 1.0)
	fill.light_energy = 0.28
	fill.shadow_enabled = false
	add_child(fill)
	var water := MeshInstance3D.new()
	water.name = "Ocean"
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	water.mesh = plane
	var water_mat := ShaderMaterial.new()
	water_mat.shader = load("res://shaders/ashore_water.gdshader")
	water.material_override = water_mat
	water.position = Vector3(0, -0.12, 16)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	var sand := MeshInstance3D.new()
	sand.name = "Island"
	sand.mesh = _island_mesh()
	var ground := ShaderMaterial.new()
	ground.shader = load("res://shaders/ashore_ground.gdshader")
	ground.set_shader_parameter("albedo_tex", load(SAND_ALBEDO))
	ground.set_shader_parameter("normal_tex", load(SAND_NORMAL))
	ground.set_shader_parameter("uv_scale", 9.0)
	sand.material_override = ground
	sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sand)
	water_mat.set_shader_parameter("shallow_color", Color(0.22, 0.9, 0.84))
	water_mat.set_shader_parameter("deep_color", Color(0.02, 0.2, 0.5))
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.current = true
	_camera.fov = 56.0
	_camera.near = 0.12
	_camera.far = 420.0
	add_child(_camera)
	_camera.global_position = Vector3(22, 14, 58)
	_camera.look_at(Vector3(8, 1, 40), Vector3.UP)


func _island_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 36
	var span := 78.0
	var rows: Array = []
	for z in n + 1:
		var row: Array = []
		for x in n + 1:
			var wx := lerpf(-span, span, float(x) / float(n))
			var wz := lerpf(-span * 0.78, span * 0.95, float(z) / float(n))
			row.append(Vector3(wx, _ground_y(wx, wz), wz))
		rows.append(row)
	for z in n:
		for x in n:
			var a: Vector3 = rows[z][x]
			var b: Vector3 = rows[z][x + 1]
			var c: Vector3 = rows[z + 1][x]
			var d: Vector3 = rows[z + 1][x + 1]
			if a.y < -1.5 and b.y < -1.5 and c.y < -1.5 and d.y < -1.5:
				continue
			_tri(st, a, b, c, span)
			_tri(st, b, d, c, span)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, span: float) -> void:
	for p in [a, b, c]:
		st.set_uv(Vector2(p.x / span + 0.5, p.z / span + 0.5))
		st.add_vertex(p)


func _build_props() -> void:
	_place_model(self, CLIFF_SCENE, "Cliff", Vector3(-2, _ground_y(-2, -20), -20), Vector3(0, 0.4, 0), 1.35, true)
	var falls := MeshInstance3D.new()
	falls.name = "Waterfall"
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(7.0, 12.0)
	sheet.orientation = PlaneMesh.FACE_Z
	falls.mesh = sheet
	var fall_mat := ShaderMaterial.new()
	fall_mat.shader = load("res://shaders/opening_falls.gdshader")
	falls.material_override = fall_mat
	falls.position = Vector3(-1.5, 7.2, -16.5)
	falls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(falls)
	var cone := MeshInstance3D.new()
	cone.name = "Volcano"
	var shape := CylinderMesh.new()
	shape.top_radius = 2.2
	shape.bottom_radius = 16.0
	shape.height = 28.0
	shape.radial_segments = 20
	cone.mesh = shape
	var lava := ShaderMaterial.new()
	lava.shader = load("res://shaders/opening_lava.gdshader")
	lava.set_shader_parameter("rock_tex", load(CLIFF_ALBEDO))
	lava.set_shader_parameter("rock_normal", load(CLIFF_NORMAL))
	cone.material_override = lava
	cone.position = Vector3(-16, 12.0, -34)
	add_child(cone)
	_dress_landmark("LandmarkWreck", "wreck")
	_dress_landmark("LandmarkGrove", "grove")
	_dress_landmark("LandmarkClearing", "clearing")
	_dress_landmark("LandmarkCamp", "camp")
	_build_offshore()
	_place_model(get_node("LandmarkWreck"), KENNEY + "ship-pirate-large.glb", "BeachedHull", Vector3(3.5, -0.3, 1.5), Vector3(0.25, 2.4, 0.2), 1.0, true)
	_place_model(get_node("LandmarkWreck"), KENNEY + "flag-pirate.glb", "WreckFlag", Vector3(-1.2, 0.4, -1.0), Vector3.ZERO, 2.2, false)
	_place_model(get_node("LandmarkGrove"), KENNEY + "palm-detailed-straight.glb", "GrovePalm", Vector3(-1.0, 0, -1.0), Vector3(0, 0.4, 0), 2.1, true)
	_place_model(get_node("LandmarkGrove"), KENNEY + "palm-bend.glb", "GroveBend", Vector3(2.2, 0, 1.1), Vector3(0, 1.2, 0), 1.8, true)
	_place_model(self, KENNEY + "palm-detailed-straight.glb", "PalmBeach", _on_land(-8, 12), Vector3(0, 0.8, 0), 1.7, true)
	_place_model(self, KENNEY + "palm-bend.glb", "PalmEast", _on_land(18, 8), Vector3(0, 2.0, 0), 1.6, true)
	_place_model(get_node("LandmarkClearing"), KENNEY + "flag.glb", "ClearFlag", Vector3(0, 0.2, 0), Vector3.ZERO, 2.4, false)
	for i in 3:
		var pad := MeshInstance3D.new()
		pad.name = "Pad%d" % i
		var disc := CylinderMesh.new()
		disc.top_radius = 1.55
		disc.bottom_radius = 1.7
		disc.height = 0.12
		pad.mesh = disc
		pad.material_override = _mat(Color(0.86, 0.78, 0.58), 0.9)
		pad.position = _pad_position(i) - _landmark_position("clearing")
		pad.position.y = 0.08
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_node("LandmarkClearing").add_child(pad)
	_hut = Node3D.new()
	_hut.name = "Hut"
	_hut.visible = false
	get_node("LandmarkClearing").add_child(_hut)
	_build_hut_pieces()
	_camp_flame = _flame_mesh()
	_camp_flame.name = "CampTorch"
	_camp_flame.position = Vector3(0, 2.4, 0)
	get_node("LandmarkCamp").add_child(_camp_flame)
	_flame = Node3D.new()
	_flame.name = "PlayerFire"
	_flame.visible = false
	var pit := _flame_mesh()
	_flame.add_child(pit)
	var logs := MeshInstance3D.new()
	var log := CylinderMesh.new()
	log.top_radius = 0.12
	log.bottom_radius = 0.14
	log.height = 1.4
	logs.mesh = log
	logs.rotation.z = PI * 0.5
	logs.material_override = _mat(Color(0.35, 0.2, 0.1), 0.8)
	_flame.add_child(logs)
	add_child(_flame)
	_sack = Node3D.new()
	_sack.name = "IdleSack"
	_sack.visible = false
	var bundle := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.72
	ball.height = 1.3
	bundle.mesh = ball
	bundle.material_override = _mat(Color(0.62, 0.36, 0.18), 0.85)
	_sack.add_child(bundle)
	var tag := _label3("Supplies", 1.5)
	_prompt_style(tag, 1.0)
	_sack.add_child(tag)
	add_child(_sack)
	_ring = MeshInstance3D.new()
	_ring.name = "TargetRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.05
	torus.rings = 10
	torus.ring_segments = 8
	_ring.mesh = torus
	var ring_mat := _mat(Color(0.95, 0.84, 0.42), 0.55)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(0.95, 0.84, 0.42, 0.45)
	ring_mat.emission_enabled = false
	_ring.material_override = ring_mat
	_ring.visible = false
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func _dress_landmark(node_name: String, id: String) -> void:
	var marker := Node3D.new()
	marker.name = node_name
	var at := _landmark_position(id)
	marker.position = at
	add_child(marker)


func _build_offshore() -> void:
	var root := Node3D.new()
	root.name = "LandmarkOffshore"
	var at: Array = _catalog.get("landmarks", {}).get("offshore", [8, 48])
	root.position = Vector3(float(at[0]), -0.4, float(at[1]))
	add_child(root)
	_place_model(root, SHIP_SCENE, "BrokenHull", Vector3(10, -2.2, 2), Vector3(0.28, 2.2, 0.35), 1.05, true)
	var carcass := Node3D.new()
	carcass.name = "Leviathan"
	for i in 7:
		var seg := MeshInstance3D.new()
		var body := CapsuleMesh.new()
		body.radius = lerpf(1.5, 0.45, float(i) / 6.0)
		body.height = 3.4
		seg.mesh = body
		seg.position = Vector3(-8.0 + float(i) * 2.3, -0.3, sin(float(i)) * 0.8)
		seg.rotation.z = PI * 0.5
		seg.material_override = _mat(Color(0.04, 0.07, 0.08), 0.55)
		carcass.add_child(seg)
	root.add_child(carcass)
	for i in 3:
		var fin := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.18, 0.85, 1.05)
		fin.mesh = prism
		fin.material_override = _mat(Color(0.08, 0.1, 0.12), 0.4)
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fin)
		_sharks.append(fin)
	var storm := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 16.0
	disc.bottom_radius = 16.0
	disc.height = 0.2
	storm.mesh = disc
	var shade := _mat(Color(0.05, 0.07, 0.12, 0.4), 1.0)
	shade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shade.emission_enabled = false
	storm.material_override = shade
	storm.position = Vector3(2, 6.5, 0)
	storm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(storm)
	var warning := _label3(OFFSHORE_WARNING, 4.5)
	warning.name = "Warning"
	warning.visible = false
	root.add_child(warning)
	var sign := Node3D.new()
	sign.name = "BeachSign"
	var sign_at := _on_land(0.5, 17.5)
	sign.position = sign_at
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.08
	post_mesh.bottom_radius = 0.1
	post_mesh.height = 1.8
	post.mesh = post_mesh
	post.position.y = 0.9
	post.material_override = _mat(Color(0.4, 0.26, 0.12), 0.8)
	sign.add_child(post)
	var board := _label3("Sharks!", 1.95)
	board.pixel_size = 0.006
	board.modulate = Color(0.95, 0.85, 0.6)
	sign.add_child(board)
	add_child(sign)


func _build_hut_pieces() -> void:
	var frame := Node3D.new()
	frame.name = "Frame"
	for i in 4:
		var post := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.18, 2.3, 0.18)
		post.mesh = mesh
		post.position = Vector3(-1.3 if i % 2 == 0 else 1.3, 1.15, -1.0 if i < 2 else 1.0)
		post.material_override = _mat(Color(0.5, 0.32, 0.16), 0.78)
		frame.add_child(post)
	_hut.add_child(frame)
	var walls := Node3D.new()
	walls.name = "Walls"
	for spec in [Vector3(0, 1.05, -1.0), Vector3(-1.3, 1.05, 0), Vector3(1.3, 1.05, 0)]:
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.4, 1.8, 0.12) if absf(spec.z) > 0.5 else Vector3(0.12, 1.8, 1.8)
		wall.mesh = box
		wall.position = spec
		wall.material_override = _mat(Color(0.62, 0.44, 0.24), 0.84)
		walls.add_child(wall)
	_hut.add_child(walls)
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var prism := PrismMesh.new()
	prism.size = Vector3(3.1, 1.15, 2.8)
	roof.mesh = prism
	roof.position = Vector3(0, 2.55, 0)
	roof.material_override = _mat(Color(0.18, 0.45, 0.22), 0.7)
	_hut.add_child(roof)
	frame.visible = false
	walls.visible = false
	roof.visible = false


func _show_hut(stage: int) -> void:
	if _hut == null:
		return
	_hut.visible = stage > 0
	var frame := _hut.get_node_or_null("Frame")
	var walls := _hut.get_node_or_null("Walls")
	var roof := _hut.get_node_or_null("Roof")
	if frame:
		frame.visible = stage >= 1
	if walls:
		walls.visible = stage >= 2
	if roof:
		roof.visible = stage >= 3


func _move_hut() -> void:
	if _hut == null or _spot < 0:
		return
	var at := _pad_position(_spot)
	_hut.global_position = at


func _build_nodes() -> void:
	_nodes_root = Node3D.new()
	_nodes_root.name = "Nodes"
	add_child(_nodes_root)
	for spec in _catalog.get("nodes", []):
		var node := {
			"id": str(spec.get("id", "")),
			"kind": str(spec.get("kind", "")),
			"title": str(spec.get("title", "")),
			"scale": float(spec.get("scale", 2.0)),
			"stages": maxi(int(spec.get("stages", 3)), 1),
			"stage": 0,
			"tool": str(spec.get("tool", "")),
			"requires": str(spec.get("requires", "")),
			"respawn": float(spec.get("respawn", 42.0)),
			"left": 0.0,
			"depleted": false,
			"loot": spec.get("loot", []),
		}
		var at: Array = spec.get("at", [0, 0])
		var pos := _on_land(float(at[0]), float(at[1]))
		var root := Node3D.new()
		root.name = node["id"]
		root.position = pos
		root.scale = Vector3.ONE * float(node["scale"])
		_nodes_root.add_child(root)
		_visual_for(str(node["kind"]), root)
		var title := _label3(str(node["title"]), 1.15)
		title.name = "Title"
		title.visible = false
		_prompt_style(title, float(node["scale"]))
		root.add_child(title)
		var lock := _label3("", 0.85)
		lock.name = "Lock"
		lock.visible = false
		_prompt_style(lock, float(node["scale"]))
		lock.modulate = Color(0.98, 0.78, 0.35)
		root.add_child(lock)
		_no_glow(root)
		node["root"] = root
		_nodes.append(node)


func _visual_for(kind: String, root: Node3D) -> void:
	match kind:
		"hull":
			_prop(root, MODELS + "dock_broken.glb", "Planks", Vector3(0, 0, 0), 0.55, 0.4, 1.6)
			_prop(root, MODELS + "wood.glb", "Beam", Vector3(0.5, 0, 0.3), 0.22, 1.3, 0.0)
		"rigging":
			_prop(root, MODELS + "wood.glb", "Spar", Vector3(0, 0, 0), 0.25, 0.3, 0.0)
			_chunk(root, Vector3(0.09, 1.2, 0.09), Color(0.42, 0.27, 0.14), Vector3(0.1, 0.5, 0.1))
			_chunk(root, Vector3(0.9, 0.06, 0.06), Color(0.78, 0.66, 0.42), Vector3(0, 0.9, 0.1))
		"cargo":
			_prop(root, MODELS + "chest.glb", "Chest", Vector3(0, 0, 0), 0.38, 0.5, 0.0)
			_prop(root, MODELS + "barrel.glb", "Barrel", Vector3(0.55, 0, 0.3), 0.42, 0.2, 0.0)
		"pile":
			_prop(root, MODELS + "barrel.glb", "BarrelA", Vector3(-0.35, 0, 0), 0.4, 0.2, 0.0)
			_prop(root, MODELS + "dock_broken.glb", "Planks", Vector3(0.3, 0, 0.1), 0.3, 1.1, 1.2)
			_chunk(root, Vector3(0.8, 0.25, 0.4), Color(0.4, 0.26, 0.14), Vector3(0, 0.45, -0.2))
		"bush":
			_prop(root, MODELS + "bush_flowers.glb", "Bush", Vector3.ZERO, 0.65, 0.0, 1.5)
			_fruit(root, Vector3(0.25, 0.5, 0.2))
			_fruit(root, Vector3(-0.3, 0.6, -0.1))
		"crab":
			_chunk(root, Vector3(0.7, 0.22, 0.5), Color(0.72, 0.22, 0.16), Vector3(0, 0.2, 0))
			_chunk(root, Vector3(0.45, 0.16, 0.32), Color(0.8, 0.3, 0.18), Vector3(0.45, 0.16, 0.2))
		"tree":
			_prop(root, MODELS + ("palm_a.glb" if root.name.ends_with("a") else "palm_b.glb"), "Tree", Vector3.ZERO, 3.2, 0.6, 0.0)
		"rock":
			_prop(root, MODELS + "rock_med_a.glb", "Rocks", Vector3.ZERO, 0.6, 0.3, 1.3)
		"flint":
			_prop(root, MODELS + "rocks_a.glb", "Rocks", Vector3.ZERO, 0.35, 0.9, 0.0)
		"fish":
			_chunk(root, Vector3(0.7, 0.18, 0.28), Color(0.2, 0.55, 0.62), Vector3(0, 0.2, 0))
			_chunk(root, Vector3(0.45, 0.14, 0.2), Color(0.85, 0.55, 0.2), Vector3(0.35, 0.18, 0.1))
		"drift":
			_prop(root, MODELS + "wood.glb", "Drift", Vector3.ZERO, 0.2, 0.7, 0.0)
		_:
			_chunk(root, Vector3(0.8, 0.8, 0.8), Color(0.7, 0.6, 0.4), Vector3(0, 0.4, 0))


func _prop(parent: Node3D, path: String, node_name: String, at: Vector3, height: float, yaw: float, width: float) -> Node3D:
	var packed = load(path)
	if packed == null:
		return null
	var model = packed.instantiate() as Node3D
	if model == null:
		return null
	model.name = node_name
	model.position = at
	model.rotation.y = yaw
	parent.add_child(model)
	var box := _merged_aabb(model)
	if box.size.y > 0.001:
		var sy := parent.global_transform.basis.get_scale().y
		var k := height * sy / box.size.y
		if width > 0.0:
			k = minf(k, width * sy / maxf(maxf(box.size.x, box.size.z), 0.001))
		model.scale = Vector3.ONE * k
		var fitted := _merged_aabb(model)
		var bottom := (parent.global_transform * at).y
		model.global_position.y += bottom - fitted.position.y
	return model


func _scatter() -> void:
	var root := Node3D.new()
	root.name = "Foliage"
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7341
	var avoid: Array = []
	for id in ["wreck", "grove", "clearing", "camp"]:
		avoid.append([_landmark_position(id), 8.0])
	for node in _nodes:
		avoid.append([(node.get("root") as Node3D).global_position, 3.2])
	avoid.append([Vector3(0.2, 0, 9.0), 5.0])
	var palms := ["palm_a.glb", "palm_b.glb", "palm_c.glb"]
	var green := ["plant_big_b.glb", "fern.glb", "plant_a.glb", "bush_flowers.glb", "fern.glb", "flowers_a.glb", "plant_big_b.glb", "flowers_b.glb", "bush.glb"]
	var stones := ["rocks_b.glb", "rocks_c.glb", "rock_a.glb", "rock_b.glb", "rock_med_b.glb"]
	var x := -36.0
	while x <= 36.0:
		var z := -30.0
		while z <= 34.0:
			var px := x + rng.randf_range(-1.4, 1.4)
			var pz := z + rng.randf_range(-1.4, 1.4)
			var e := pow(px / 36.0, 2) + pow((pz - 4.0) / 32.0, 2)
			var y := _ground_y(px, pz)
			var ok := y > 0.25
			for a in avoid:
				if Vector2(px - a[0].x, pz - a[0].z).length() < a[1]:
					ok = false
			if ok:
				var at := Vector3(px, y - 0.05, pz)
				var roll := rng.randf()
				if e > 0.5 and e < 0.75 and roll < 0.28:
					_prop(root, MODELS + stones[rng.randi() % stones.size()], "Stone", at, rng.randf_range(0.8, 2.6), rng.randf() * TAU, 0.0)
				elif y > 0.9 and roll < 0.42:
					_prop(root, MODELS + palms[rng.randi() % palms.size()], "Palm", at, rng.randf_range(5.5, 8.5), rng.randf() * TAU, 0.0)
				elif y > 1.25 and roll < 0.95:
					_prop(root, MODELS + green[rng.randi() % green.size()], "Green", at, rng.randf_range(0.7, 1.6), rng.randf() * TAU, 0.0)
			z += 3.4
		x += 3.4
	for mesh in _meshes(root):
		if mesh.get_aabb().size.y * mesh.global_transform.basis.get_scale().y < 2.0:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _chunk(root: Node3D, size: Vector3, color: Color, at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = _mat(color, 0.78)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)


func _fruit(root: Node3D, at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	mesh.mesh = sphere
	mesh.position = at
	mesh.material_override = _mat(Color(0.86, 0.16, 0.12), 0.45)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)


func _flame_mesh() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.28
	cone.height = 0.9
	mesh.mesh = cone
	var mat := _mat(Color(1.0, 0.55, 0.12), 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.08)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


func _build_player() -> void:
	_player = Node3D.new()
	_player.name = "Player"
	var at := _on_land(0.2, 9.0)
	_player.position = at
	add_child(_player)
	var rig := _instance_rig()
	if rig:
		rig.name = "Rig"
		_player.add_child(rig)
		_fit(rig, 1.72)
		if rig.has_meta("clips"):
			_collect_skin(rig)
		else:
			_paint_actor(rig)
	else:
		var cap := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.32
		mesh.height = 1.7
		cap.mesh = mesh
		cap.position.y = 0.85
		cap.material_override = _mat(Color(0.85, 0.7, 0.45), 0.6)
		_player.add_child(cap)
	var wreck := _landmark_position("wreck")
	_player.look_at(Vector3(wreck.x, _player.position.y, wreck.z), Vector3.UP)


func _build_pet() -> void:
	_pet = Node3D.new()
	_pet.name = "Pet"
	_pet.visible = false
	add_child(_pet)
	var cat := _rig(MODELS + "cat.glb", {"Idle": "|Idle", "Walk": "|Walk", "Yes": "|Yes", "Jump": "|Jump"})
	if cat:
		cat.name = "Body"
		_pet.add_child(cat)
		_fit(cat, 0.78)
		_pet_anim = cat.get_meta("clips") as AnimationPlayer
	_pet_head = Node3D.new()
	_pet_head.name = "Head"
	_pet_head.position = Vector3(0, 0.55, -0.2)
	_pet.add_child(_pet_head)
	var name_label := _label3("Tide-Puck", 1.05)
	name_label.name = "Name"
	name_label.pixel_size = 0.0035
	name_label.modulate = Color(1, 0.95, 0.8, 0.9)
	_pet.add_child(name_label)


func _build_beast() -> void:
	_beast = Node3D.new()
	_beast.name = "Creature"
	var camp := _landmark_position("camp")
	_beast.position = camp + Vector3(0.4, 0, 0.6)
	_beast.position.y = _ground_y(_beast.position.x, _beast.position.z)
	var home := get_node_or_null("Creatures")
	if home == null:
		home = Node3D.new()
		home.name = "Creatures"
		add_child(home)
	home.add_child(_beast)
	var dino := _rig(MODELS + "dino.glb", {"Idle": "|Idle", "Walk": "|Walk", "Run": "|Run", "Punch": "|Punch", "Death": "|Death", "Yes": "|Yes"})
	if dino:
		dino.name = "Body"
		_beast.add_child(dino)
		_fit(dino, 1.7)
		_beast_anim = dino.get_meta("clips") as AnimationPlayer
	var bar := MeshInstance3D.new()
	bar.name = "HealthBar"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 0.12)
	bar.mesh = quad
	bar.position = Vector3(0, 2.05, 0)
	bar.material_override = _mat(Color(0.75, 0.18, 0.16), 0.4)
	bar.visible = false
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beast.add_child(bar)
	_paint_beast(false)


func _paint_beast(rare: bool) -> void:
	var tint := Color(1.25, 0.95, 0.35) if rare else Color(1, 1, 1)
	_beast_mats.clear()
	for mesh in _meshes(_beast):
		if str(mesh.name) == "HealthBar" or mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var base := mesh.get_active_material(i)
			if not (base is StandardMaterial3D):
				continue
			var mat := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			var orig: Color = base.get_meta("base", (base as StandardMaterial3D).albedo_color)
			mat.set_meta("base", orig)
			mat.albedo_color = orig * tint
			if rare:
				mat.emission_enabled = true
				mat.emission = Color(0.35, 0.25, 0.05)
			mesh.set_surface_override_material(i, mat)
			_beast_mats.append(mat)


func _apply_stage(node: Dictionary) -> void:
	var root := node.get("root") as Node3D
	if root == null:
		return
	var t := 1.0 - float(int(node.get("stage", 0))) / float(maxi(int(node.get("stages", 1)), 1))
	var base := float(node.get("scale", 2.0))
	root.scale = Vector3.ONE * base * (0.5 + 0.5 * t)
	var chunks := _meshes(root)
	var stage := int(node.get("stage", 0))
	var i := 0
	for mesh in chunks:
		if mesh.get_parent() == root and mesh.mesh is BoxMesh:
			mesh.visible = i >= stage
			i += 1


func _instance_rig() -> Node3D:
	var captain := _rig(MODELS + "captain.glb", {"Idle": "|Idle", "Run": "|Run", "Jump": "|Sword", "Walk": "|Walk"})
	if captain:
		_anim = captain.get_meta("clips") as AnimationPlayer
		return captain
	var packed = load("res://assets/opening/kenney/characterMedium.fbx")
	if packed == null:
		return null
	var node = packed.instantiate()
	if not (node is Node3D):
		return null
	var player := AnimationPlayer.new()
	player.name = "Clips"
	node.add_child(player)
	var library := AnimationLibrary.new()
	player.add_animation_library("", library)
	_copy_longest(library, "res://assets/opening/kenney/idle.fbx", "Idle")
	_copy_longest(library, "res://assets/opening/kenney/run.fbx", "Run")
	_copy_longest(library, "res://assets/opening/kenney/jump.fbx", "Jump")
	_anim = player
	if player.has_animation("Idle"):
		player.play("Idle")
	return node


func _rig(path: String, clips: Dictionary) -> Node3D:
	var packed = load(path)
	if packed == null:
		return null
	var model = packed.instantiate()
	if not (model is Node3D):
		return null
	var holder := Node3D.new()
	var inner := model as Node3D
	inner.rotation.y = PI
	holder.add_child(inner)
	var source := inner.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source:
		var library := AnimationLibrary.new()
		for alias in clips.keys():
			for anim_name in source.get_animation_list():
				var key := str(clips[alias])
				var nm := str(anim_name)
				if nm.ends_with(key) or nm.contains(key + "|") or nm == key.trim_prefix("|"):
					var anim := source.get_animation(anim_name).duplicate() as Animation
					anim.loop_mode = Animation.LOOP_NONE if alias in ["Jump", "Death", "Bite", "Punch"] else Animation.LOOP_LINEAR
					library.add_animation(alias, anim)
					break
		source.add_animation_library("ashore", library)
		holder.set_meta("clips", source)
		holder.set_meta("prefix", "ashore/")
		if source.has_animation("ashore/Idle"):
			source.play("ashore/Idle")
	return holder


func _clip(player: AnimationPlayer, clip_name: String, speed: float = 1.0) -> void:
	if player == null:
		return
	var full := "ashore/" + clip_name
	if player.has_animation(full) and player.current_animation != full:
		player.play(full, 0.18, speed)


func _collect_skin(actor: Node) -> void:
	for mesh in _meshes(actor):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var base := mesh.get_active_material(i)
			if base is StandardMaterial3D:
				var mat := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				mat.set_meta("base", mat.albedo_color)
				mesh.set_surface_override_material(i, mat)
				_skin.append(mat)


func _copy_longest(library: AnimationLibrary, path: String, alias: String) -> void:
	var packed = load(path)
	if packed == null:
		return
	var temp = packed.instantiate()
	var source := temp.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var best: Animation = null
	var best_length := -1.0
	if source:
		for anim_name in source.get_animation_list():
			var anim := source.get_animation(anim_name)
			if anim != null and anim.length >= best_length:
				best = anim
				best_length = anim.length
	if best != null:
		library.add_animation(alias, best.duplicate())
	temp.free()


func _fit(actor: Node3D, meters: float) -> void:
	var box := _merged_aabb(actor)
	if box.size.y < 0.05:
		return
	actor.scale = Vector3.ONE * (meters / box.size.y)
	var fitted := _merged_aabb(actor)
	var base_y := 0.0
	if actor.get_parent() is Node3D and actor.is_inside_tree():
		base_y = (actor.get_parent() as Node3D).global_position.y
	actor.position.y -= fitted.position.y - base_y


func _paint_actor(actor: Node) -> void:
	var skin = load("res://assets/opening/kenney/criminalMaleA.png")
	for mesh in _meshes(actor):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = skin
		mat.albedo_color = Color(1, 1, 1)
		mat.roughness = 0.62
		mat.metallic = 0.0
		mat.emission_enabled = false
		mesh.material_override = mat
		_skin.append(mat)


func _place_model(parent: Node, path: String, node_name: String, at: Vector3, rotation: Vector3, scale: float, shadows: bool) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = at
	holder.rotation = rotation
	holder.scale = Vector3.ONE * scale
	parent.add_child(holder)
	var packed = load(path)
	if packed != null:
		var model = packed.instantiate()
		holder.add_child(model)
		if not shadows:
			for mesh in _meshes(model):
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return holder


func _no_glow(node: Node) -> void:
	for mesh in _meshes(node):
		var mat := mesh.material_override
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).emission_enabled = false


func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = 0.0
	mat.emission_enabled = false
	return mat


func _label3(text: String, y: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	if _font:
		label.font = _font
	label.font_size = 56
	label.pixel_size = 0.012
	label.outline_size = 14
	label.modulate = Color(0.98, 0.93, 0.82)
	label.outline_modulate = Color(0.08, 0.05, 0.03)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, y, 0)
	label.no_depth_test = true
	label.double_sided = true
	return label


func _shake(node: Node3D) -> void:
	if node == null:
		return
	var base := node.rotation.z
	var tween := create_tween()
	tween.tween_property(node, "rotation:z", base + 0.14, 0.06)
	tween.tween_property(node, "rotation:z", base - 0.1, 0.07)
	tween.tween_property(node, "rotation:z", base, 0.06)


func _bounce(node: Node3D) -> void:
	if node == null:
		return
	var base := node.scale
	var tween := create_tween()
	tween.tween_property(node, "scale", base * 1.15, 0.08)
	tween.tween_property(node, "scale", base, 0.12)


func _merged_aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mesh in _meshes(node):
		var local := mesh.get_aabb()
		for i in 8:
			var corner := local.position
			if i & 1:
				corner.x += local.size.x
			if i & 2:
				corner.y += local.size.y
			if i & 4:
				corner.z += local.size.z
			var point: Vector3 = mesh.global_transform * corner
			if first:
				box = AABB(point, Vector3.ZERO)
				first = false
			else:
				box = box.expand(point)
	return box


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found


func _push_hud() -> void:
	if _hud == null or not _hud.has_method("push_state"):
		return
	var pointer_on := false
	var pointer_at := Vector2.ZERO
	if _camera and _cinematic == "":
		var point := _point_position()
		var behind := _camera.is_position_behind(point)
		var screen := _camera.unproject_position(point)
		var rect := get_viewport().get_visible_rect()
		var inside := Rect2(rect.position + Vector2(70, 70), rect.size - Vector2(140, 140)).has_point(screen)
		pointer_on = behind or not inside
		pointer_at = screen
	var rows: Array = []
	for row in _research:
		var state := "locked"
		if bool(row.get("done", false)):
			state = "done"
		elif str(row.get("id", "")) == _running:
			state = "run"
		elif not bool(row.get("locked", false)) and _prereq_met(row):
			state = "ready"
		var ratio := 0.0
		if state == "run" and float(row.get("seconds", 1.0)) > 0.0:
			ratio = 1.0 - _research_left / float(row.get("seconds", 1.0))
		rows.append({
			"id": row.get("id", ""),
			"title": row.get("title", ""),
			"state": state,
			"ratio": clampf(ratio, 0.0, 1.0),
		})
	var pet_name := str(_pet_stats.get("name", "Tide-Puck"))
	if _pet:
		var name_label := _pet.get_node_or_null("Name") as Label3D
		if name_label:
			name_label.text = pet_name
	_hud.push_state({
		"line": _line,
		"hint": _hint,
		"warmth": _warmth,
		"hunger": _hunger,
		"health": _health,
		"show_health": _creature_hostile or _health < 5,
		"counts": _inv,
		"action": _action_caption(),
		"attack": _has_weapon() and _beast != null and _beast.visible and _choice != "kill",
		"skip": _cinematic != "",
		"fork": _fork,
		"qte": _qte,
		"qte_marker": fposmod(_tame_phase, float(_tuning.get("tame_period", 2.0))) / float(_tuning.get("tame_period", 2.0)),
		"qte_a": 0.68,
		"qte_b": 0.84,
		"qte_ratio": clampf(_tame_left / maxf(_tame_total, 0.1), 0.0, 1.0),
		"research_open": _research_open,
		"research": rows,
		"name_open": _naming,
		"name_default": "Tide-Puck",
		"end_open": _end_open,
		"end_lines": _end_lines(),
		"pet_freed": _pet_freed,
		"pet_name": pet_name,
		"pet_level": int(_pet_stats.get("level", 1)),
		"pet_mood": int(_pet_stats.get("mood", 0)),
		"pet_hunger": int(_pet_stats.get("hunger", 0)),
		"pet_open": _pet_open,
		"pet_cards": [
			{"t": "Find food", "on": true},
			{"t": "Track", "on": true},
			{"t": "Alert", "on": true},
			{"t": "Gathering", "on": false},
			{"t": "Fighting", "on": false},
		],
		"spyglass": _cinematic == "wake" and _cine_age > 5.1,
		"letterbox": _cinematic != "",
		"alert": _alerted and _choice == "",
		"build_on": _building,
		"build_ratio": 0.0 if _build_total <= 0.0 else clampf(1.0 - _build_left / _build_total, 0.0, 1.0),
		"pointer": pointer_on,
		"pointer_at": pointer_at,
	})


func _action_caption() -> String:
	if _collect_ready and _sack and _near(_sack.global_position, 3.4):
		return "Take"
	var node := _nearest_node(3.5)
	if not node.is_empty():
		if str(node.get("id", "")) == "pet_pile":
			return "Free"
		return "Gather"
	if _step == "clearing" and _nearest_pad(3.4) >= 0:
		return "Camp"
	if _step == "build":
		return "Build"
	if _step == "fire" or (_near(_pit_position(), 3.4) and _research_done("fire")):
		return "Light" if not _fire_lit else "Cook"
	if _step == "cook":
		return "Cook"
	if _food_total() > 0 and _hunger < 97.0:
		return "Eat"
	return "Act"


func _end_lines() -> Array:
	var lure := ["The leviathan wreck.", OFFSHORE_WARNING, "To be continued."]
	if _choice == "tame":
		var lines: Array = []
		if _rare:
			lines.append("RARE!")
		lines.append("It gathers.")
		lines.append("Mount / Transport")
		lines.append("Creature Riding")
		lines.append("Carry capacity")
		lines.append_array(lure)
		return lines
	if _choice == "kill":
		return ["Meat for the fire.", "No gatherer yet.", "Next creature comes later." ] + lure
	return lure


class ShoreSession extends Node:
	var _url := ""
	var _token := ""

	func configure(url: String, token: String) -> void:
		_url = url
		_token = token
