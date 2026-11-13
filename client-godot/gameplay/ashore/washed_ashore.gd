extends Node3D
## Local washed-ashore island. The opening battle hands its in-memory session
## here. Nothing on this screen is the server debug slice.
##
## The island is the realistic coastal slice (same terrain, water, sky and
## foliage as the bay); the castaway lands on its south beach.
##
## Mobile budget for a Galaxy S23 Ultra class device: the slice's one shadowed
## sun and water plane, 1K textures, joined hull halves, and no shadow
## casting on small props. Pickups use albedo only; fire is the only light.

const CATALOG_PATH := "res://gameplay/ashore/data/catalog.json"
const SAVE_PATH := "user://washed_ashore.cfg"
const OFFSHORE_WARNING := "Too dangerous: sharks/storm"
const PET_DEFENCE_LINE := "Needs Pet Defence research and training"

const Art := preload("res://gameplay/opening/opening_art.gd")
const SLICE_SCENE := preload("res://scenes/realistic_coastal_slice.tscn")
const HUT := preload("res://assets/ashore/library/hut_hy3d/hut_hy3d.glb")
const FIRE_PIT := preload("res://assets/ashore/library/stone_fire_pit/stone_fire_pit.glb")
const DEAD_LOG := preload("res://assets/ashore/library/log_dead_trunk_02/log_dead_trunk_02.glb")
const ASHORE_STONE := preload("res://assets/ashore/library/stone_01/stone_01.glb")
const MODELS := "res://assets/ashore/models/"
## Landing spot on the slice's south beach. The beach is a narrow strip
## (z 2..7) under the jungle slope, so the castaway wakes facing east along
## it: sea on screen left, jungle slope on screen right, wreck ahead.
const START := Vector3(-10.0, 0.0, 4.5)
const INTRO_FACING := Vector3(0.94, 0.0, 0.34)
## Bay dressing hidden for the landing: shore rock piles, the settlement dock
## and stock wreckage would read as a pier next to the wreck.
const HIDDEN_DRESSING := ["coast_rocks_05_1k", "@Node3D@3", "CoastalPBRDepthLayer/coast_rocks_05_1k",
	"VerifiedTropicalContentLayer/rock_moss_set_01_1k", "TropicalBayDressing/ShoreBoulders",
	"TropicalBayDressing/ShoreRocks07", "TropicalBayDressing/ShoreMossRocks", "TropicalBayDressing/BeachScatterRocks",
	"TropicalBayDressing/BeachWreckage", "TropicalBayDressing/BeachSettlement", "TropicalBayDressing/BeachDriftwood"]
const LAND_MARGIN := 0.22
const FOLLOW_BACK := 7.0
const FOLLOW_UP := 4.2
const INTRO_BACK := 4.4
const INTRO_UP := 2.3
const INTRO_LOOK_UP := 1.15
const INTRO_FOV := 52.0
## Intro layout in (ahead, right) metres from START.
const PET_REST := Vector2(-0.6, 1.1)
## Holder yaw (model faces +Z, inner flip PI): three-quarter to the camera
## with the bandaged front flipper (model +X) toward it.
const PET_REST_YAW := 50.0
const PET_SCALE := 1.1
const CUTLASS_AT := Vector2(-0.3, -1.1)
const FONT_PATH := "res://assets/fonts/PirataOne-Regular.ttf"

const AUDIO := "res://assets/ashore/audio/"
const OCEAN := "res://assets/opening/audio/ocean.ogg"
const SWING := "res://assets/opening/audio/swing.ogg"
const ROAR := "res://assets/opening/audio/roar.ogg"
const CHEER := "res://assets/opening/audio/cheer.ogg"

const FOOD_IDS := ["food", "fish", "meat", "cooked"]
const RAW_IDS := ["food", "fish", "meat"]
const TOOL_IDS := ["axe", "knife", "club", "pick"]
const WRECK_IDS := ["hull", "rigging", "cargo_cloth", "cargo_tools"]
## Walkable slope: rise/run above tan(40 deg) is a wall; above tan(45 deg) you slide.
const SLOPE_MAX := 0.84
const SLIDE_SLOPE := 1.0
const STORM_SECONDS := 120.0
const WAKE_SECONDS := 4.5
const BUILD_IDS := ["campfire", "lean_to", "storage"]
const BUILD_TITLES := {"campfire": "Campfire", "lean_to": "Lean-to", "storage": "Storage"}
const BUILD_RADIUS := {"campfire": 0.9, "lean_to": 1.8, "storage": 0.8}
const DYNAMIC_STEPS := ["scavenge", "gather", "fire", "cook", "shelter"]
const FOLIAGE_WORDS := ["Palm", "Canopy", "Shrub", "Cover", "Understory", "Calathea"]
const GATHER_WOOD := 12
const GATHER_STONE := 10
const COOK_FISH := 2
const BOND_STEPS := [0, 20, 50]
const BOND_REWARDS := {2: "Fetch", 3: "Keen Nose"}
const NEAR_FADE_MIN := 0.9
const NEAR_FADE_MAX := 2.8

var _endpoint := ""
var _token := ""
var _refresh := ""
var _client: Node
var _catalog: Dictionary = {}
var _tuning: Dictionary = {}
var _research: Array = []
var _nodes: Array = []
var _inv := {"planks": 0, "rope": 0, "cloth": 0, "wood": 0, "stone": 0, "fibre": 0, "food": 0, "meat": 0, "flint": 0, "fish": 0, "cooked": 0}
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
var _defeat_path := ""
var _outcome_applied := false
var _silas_shown := false
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
var _pet_stats := {"name": "Tide-Puck", "level": 1, "xp": 0, "hunger": 70, "mood": 65, "bond": 0}
var _scavenged := 0
var _gather_lock := 0.0
var _placing := ""
var _ghost: Node3D
var _ghost_mat: StandardMaterial3D
var _ghost_ok := false
var _ghost_why := ""
var _ghost_pin := Vector3(INF, INF, INF)
var _build_open := false
var _fire_at := Vector3(INF, INF, INF)
var _structures: Array = []
var _storage: Node3D
var _storm_left := -1.0
var _storm_warned := false
var _pet_mode := "follow"
var _pet_goal := Vector3.ZERO
var _pet_target: Dictionary = {}
var _pet_carry := ""
var _pet_timer := 0.0
var _pet_hop := 0.0
var _sniff_left := 6.0
var _fetch_left := 24.0
var _pet_finds := 0
var _pet_fetches := 0
var _fish_cooked := 0
var _pet_pet_cd := 0.0
var _dig_serial := 0
var _steep_t := 0.0
var _foliage_boxes: Array = []
var _cam_pull := 1.0
var _cam_probe_t := 0.0
var _cam_yaw_goal := 0.0
var _cam_lift := 0.0
var _cam_lift_goal := 0.0
var _cam_orbit_hold := 0.0
var _foliage_mats: Array = []
var _fade_mats: Array = []
var _occluding: Dictionary = {}
var _foliage_links: Array = []
var _drag_id := -2
var _drag_from := Vector2.ZERO
var _drag_moved := false
var _haptics: Array = []
var _sfx_log: Array = []

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
var _slice: Node3D
var _water_y := -0.35
var _base_exposure := 1.0
var _terrain_tm: TriangleMesh
var _terrain_xf := Transform3D.IDENTITY
var _intro_k := 1.0
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
	_prepare_foliage()
	_hud = CanvasLayer.new()
	_hud.set_script(load("res://gameplay/ashore/ashore_hud.gd"))
	_hud.world = self
	add_child(_hud)
	if _saved.is_empty():
		_read_opening_outcome()
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
	if _cinematic == "" and not _fork and not _qte and _step in DYNAMIC_STEPS:
		_line = _line_for(_step)
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
	if _placing != "":
		on_build_place()
		return
	if not _pet_freed:
		var pile := _node_by_id("pet_pile")
		if not pile.is_empty() and _near((pile.get("root") as Node3D).global_position, 3.5):
			_free_pet()
			return
	if _step == "cook" and _fish_cooked >= COOK_FISH and _pet_freed and _near(_pet.global_position, 2.8) and int(_inv.get("cooked", 0)) > 0:
		_feed_cooked_fish()
		return
	var node := _nearest_node(3.5)
	if not node.is_empty():
		_act_on_node(node)
		return
	if _fire_lit and _near(_pit_position(), 3.4) and _raw_food() != "":
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
	_sniff_left = 6.0
	_fetch_left = 24.0
	_enter("gather")


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
	_bond(12)
	_play(AUDIO + "crunch.ogg", -6.0, 1.0)
	_play(AUDIO + "bark.ogg", -10.0, 1.25)
	_pet_hop = 0.5
	_popup("Bond +12", _pet.global_position + Vector3.UP * 0.9, Color(1.0, 0.72, 0.78))


func on_pet() -> void:
	if not _pet_freed:
		return
	_pet_stats["mood"] = mini(100, int(_pet_stats["mood"]) + 14)
	_pet_hop = 0.45
	if _pet_pet_cd <= 0.0:
		_pet_pet_cd = 6.0
		_gain_xp(1)
		_bond(3)
		_play(AUDIO + "squeak.ogg", -12.0, 1.35)
		_popup("♥", _pet.global_position + Vector3.UP * 0.9, Color(1.0, 0.6, 0.66))


func _do_pet_alert() -> void:
	var hp := _creature_hp
	_alerted = true
	_hint = PET_DEFENCE_LINE
	_hint_t = 999.0
	# A low growl (the bark pitched down) and a stiff stare at the threat.
	_play(AUDIO + "bark.ogg", -4.0, 0.62)
	_pet_mode = "warn"
	_pet_timer = 0.0
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
			KEY_B:
				on_build_toggle()
			KEY_Q:
				_cam_yaw += 0.4
			KEY_R:
				_cam_yaw -= 0.4
	# Right-side drag orbits the camera; a press-release without much travel is a tap.
	elif event is InputEventScreenTouch:
		if event.pressed and _drag_id == -2:
			_drag_id = event.index
			_drag_from = event.position
			_drag_moved = false
		elif not event.pressed and event.index == _drag_id:
			_drag_id = -2
			if not _drag_moved:
				_tap(event.position)
	elif event is InputEventScreenDrag and event.index == _drag_id:
		_orbit_drag(event.position, event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_id = -1
			_drag_from = event.position
			_drag_moved = false
		elif _drag_id == -1:
			_drag_id = -2
			if not _drag_moved:
				_tap(event.position)
	elif event is InputEventMouseMotion and _drag_id == -1 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_orbit_drag(event.position, event.relative)


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
			_play_clip("Kneel")
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
	if step == "fire":
		_build_open = _can_pay("campfire")
	if step == "shelter":
		_storm_left = STORM_SECONDS
		_storm_warned = false
		_build_open = _can_pay("lean_to")
	if step == "dusk":
		_storm_left = -1.0
		_build_open = false
		_begin_dusk()
	if step == "epilogue":
		_end_open = not _end_dismissed
		_pointer_id = "offshore"
	_herald(step)
	_save()


func _line_for(step: String) -> String:
	match step:
		"scavenge":
			return "Search the wreck  %d/3" % mini(_scavenged, 3)
		"gather":
			return "Gather  Wood %d/%d  ·  Stone %d/%d" % [mini(int(_inv.get("wood", 0)), GATHER_WOOD), GATHER_WOOD, mini(int(_inv.get("stone", 0)), GATHER_STONE), GATHER_STONE]
		"fire":
			if _placing == "campfire":
				return "Place the campfire on flat sand"
			if _can_pay("campfire"):
				return "Build a campfire  (tap Build)"
			return "Campfire needs " + _shortfall_text("campfire")
		"cook":
			if _fish_cooked >= COOK_FISH:
				return "Feed %s a cooked fish  (tap him)" % str(_pet_stats.get("name", "Tide-Puck"))
			return "Catch and cook fish  %d/%d" % [_fish_cooked, COOK_FISH]
		"shelter":
			var clock := "%d:%02d" % [int(maxf(_storm_left, 0.0)) / 60, int(maxf(_storm_left, 0.0)) % 60]
			if _building:
				return "Building the lean-to...  storm in " + clock
			if _placing == "lean_to":
				return "Place the lean-to  ·  storm in " + clock
			if _can_pay("lean_to"):
				return "Build a lean-to  ·  storm in " + clock
			return "Lean-to needs %s  ·  %s" % [_shortfall_text("lean_to"), clock]
	return str(_catalog.get("lines", {}).get(step, "Onward."))


func _herald(step: String) -> void:
	if step == "wake":
		return
	_heralds += 1
	_sniff_t = 1.25
	if _pet_freed:
		_pet_hop = 0.45
	else:
		_play(AUDIO + "squeak.ogg", -8.0, 1.0)


func _finish_wake() -> void:
	_cinematic = ""
	if _player:
		_player.rotation.x = 0.0
		# Stand facing east along the beach toward the wreck.
		_player.look_at(_player.position + INTRO_FACING, Vector3.UP)
		_cam_yaw = _player.rotation.y
		_play_clip("Idle")
	_intro_k = 1.0
	snap_intro_camera()
	_note_burst("Up")
	_enter("scavenge")


func _tick_cine(delta: float) -> void:
	_cine_age += delta
	if _cinematic == "wake":
		_wake_camera()
		if _cine_age > WAKE_SECONDS:
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


## Wake: drift in from over the surf to the close intro framing on the
## castaway, who kneels in the wet sand and then stands.
func _wake_camera() -> void:
	var u := clampf(_cine_age / WAKE_SECONDS, 0.0, 1.0)
	var close := _intro_eye(1.0)
	var target := _player.global_position + Vector3.UP * INTRO_LOOK_UP
	if u < 0.62:
		var t := u / 0.62
		t = t * t * (3.0 - 2.0 * t)
		_camera.fov = lerpf(50.0, INTRO_FOV, t)
		_camera.global_position = Vector3(START.x - 12.0, 14.0, START.z - 22.0).lerp(close, t)
		_camera.look_at(target.lerp(target, t), Vector3.UP)
	else:
		_camera.fov = INTRO_FOV
		_camera.global_position = close
		_camera.look_at(target, Vector3.UP)


## Follow-camera eye at intro closeness `k` (1 close intro, 0 regular follow).
func _intro_eye(k: float) -> Vector3:
	var back := Basis(Vector3.UP, _cam_yaw).z
	var dist := lerpf(FOLLOW_BACK, INTRO_BACK, k)
	var up := lerpf(FOLLOW_UP, INTRO_UP, k)
	return _player.global_position + back * dist + Vector3.UP * up


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
	_tick_silas_hint()
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
	_tick_quest(delta)
	_tick_ghost()
	_gather_lock = maxf(_gather_lock - delta, 0.0)
	_follow_camera(delta)
	_refresh_locks()
	if _step == "scavenge" and _step_time > 40.0:
		_note_burst("Squeak!")
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
		if input.length() > 0.2:
			_move_goal = Vector3(INF, INF, INF)
			_move_node = {}
		elif not _slide(Vector3(to.x, 0, to.z).normalized(), delta, true):
			_move_goal = Vector3(INF, INF, INF)
			_move_node = {}
		else:
			_play_clip("Run")
			return
	if _slide_down(delta):
		return
	if input.length() < 0.12:
		_play_clip("Idle")
		_player.position.y = _ground_y(_player.position.x, _player.position.z)
		return
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, _cam_yaw)
	if _slide(dir, delta, true):
		_play_clip("Run")
	else:
		_play_clip("Idle")


## Ground movement with a 40 degree walk limit. Tries the wanted direction,
## then deflects 35 and 70 degrees either way so the castaway slides along a
## cliff foot instead of sticking or climbing it. Returns false when blocked.
func _slide(dir: Vector3, delta: float, face: bool) -> bool:
	if dir.length() < 0.01:
		return false
	dir = dir.normalized()
	var pos := _player.position
	var here := _ground_y(pos.x, pos.z)
	var step := 5.3 * delta
	var wet := false
	for ang in [0.0, 0.61, -0.61, 1.22, -1.22]:
		var d := dir.rotated(Vector3.UP, ang)
		var s := step * (1.0 if ang == 0.0 else cos(ang))
		var next := pos + d * s
		var y := _ground_y(next.x, next.z)
		if y < _water_y + LAND_MARGIN:
			wet = wet or ang == 0.0
			continue
		var probe := pos + d * 0.45
		var ahead := _ground_y(probe.x, probe.z)
		if (y - here) / maxf(s, 0.001) > SLOPE_MAX or (ahead - here) / 0.45 > SLOPE_MAX:
			continue
		next.y = y
		if _warmth < 42.0:
			next.y += sin(_age * 16.0) * 0.015
		_player.position = next
		if face:
			var at := _player.global_position + d
			at.y = _player.global_position.y
			_player.look_at(at, Vector3.UP)
		return true
	if wet:
		_show_hint(OFFSHORE_WARNING)
	elif _age - _steep_t > 2.5:
		_steep_t = _age
		_show_hint("Too steep to climb")
	return false


## Standing on a slope steeper than 45 degrees slides you back down.
func _slide_down(delta: float) -> bool:
	var p := _player.position
	var gx := _ground_y(p.x + 0.3, p.z) - _ground_y(p.x - 0.3, p.z)
	var gz := _ground_y(p.x, p.z + 0.3) - _ground_y(p.x, p.z - 0.3)
	var grad := Vector2(gx, gz) / 0.6
	if grad.length() <= SLIDE_SLOPE:
		return false
	var down := Vector3(-grad.x, 0, -grad.y).normalized()
	var next := p + down * 3.2 * delta
	next.y = _ground_y(next.x, next.z)
	if next.y < _water_y + LAND_MARGIN:
		return false
	_player.position = next
	return true


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
	# Intro beat: stay close until the castaway walks off the landing spot.
	if _intro_k > 0.0 and (_step != "scavenge" or _flat(_player.global_position, START) > 2.5):
		_intro_k = maxf(_intro_k - delta / 1.6, 0.0)
	_camera.fov = lerpf(_camera.fov, lerpf(58.0, INTRO_FOV, _intro_k), clampf(delta * 3.0, 0.0, 1.0))
	var want := _intro_eye(_intro_k)
	# The south beach is a narrow strip under a steep jungle slope. Pull the
	# camera in when the ground behind rises, so it stays on the sand instead
	# of climbing into the palm canopy.
	var pull := 1.0
	while pull > 0.4 and _ground_y(want.x, want.z) > _player.global_position.y + 1.1:
		pull -= 0.15
		want = _player.global_position + (want - _player.global_position) * (pull / (pull + 0.15))
	# Foliage between the castaway and the lens: first swing/raise the
	# camera toward a clear view (eased), then pull in (fast) for whatever
	# still blocks, easing back out (slow) once the line of sight is clear.
	var head := _player.global_position + Vector3.UP * 1.5
	_cam_probe_t -= delta
	if _cam_probe_t <= 0.0:
		_cam_probe_t = 0.12
		_probe_clear_view(head)
	if _cam_orbit_hold > 0.0:
		_cam_orbit_hold -= delta
		_cam_yaw_goal = 0.0
	if absf(_cam_yaw_goal) > 0.001:
		var turn := clampf(_cam_yaw_goal, -delta * 2.2, delta * 2.2)
		_cam_yaw += turn
		_cam_yaw_goal -= turn
	_cam_lift = lerpf(_cam_lift, _cam_lift_goal, 1.0 - exp(-delta * 3.0))
	want = _intro_eye(_intro_k) + Vector3.UP * _cam_lift
	pull = 1.0
	while pull > 0.4 and _ground_y(want.x, want.z) > _player.global_position.y + 1.1:
		pull -= 0.15
		want = _player.global_position + (want - _player.global_position) * (pull / (pull + 0.15))
	var full := head.distance_to(want)
	var hit := _foliage_hit(head, want)
	var target := 1.0
	if hit < 1.0 and full > 0.1:
		target = clampf((hit * full - 0.4) / full, 2.0 / full, 1.0)
	if target < _cam_pull:
		_cam_pull = lerpf(_cam_pull, target, 1.0 - exp(-delta * 14.0))
	else:
		_cam_pull = lerpf(_cam_pull, target, 1.0 - exp(-delta * 1.4))
	want = head + (want - head) * _cam_pull
	var gy := maxf(_ground_y(want.x, want.z), _ground_y(lerpf(want.x, _player.global_position.x, 0.5), lerpf(want.z, _player.global_position.z, 0.5)))
	gy = maxf(gy, _water_y)
	if want.y < gy + 1.8:
		want.y = gy + 1.8
	var rate := 4.0 if _cam_pull > 0.98 else 10.0
	var blend := 1.0 - exp(-delta * rate)
	var eye := _camera.global_position.lerp(want, blend)
	var tries := 0
	while _foliage_inside(eye) and tries < 12 and eye.distance_to(head) > 1.3:
		eye = head + (eye - head) * 0.85
		tries += 1
	_camera.global_position = eye
	_camera.look_at(_player.global_position + Vector3.UP * lerpf(2.0, INTRO_LOOK_UP, _intro_k), Vector3.UP)
	_fade_occluders(eye, head, delta)


## Snap straight to the post-wake intro framing (skip button and captures).
func snap_intro_camera() -> void:
	if _camera == null or _player == null:
		return
	_camera.fov = INTRO_FOV
	_camera.global_position = _intro_eye(_intro_k)
	_camera.look_at(_player.global_position + Vector3.UP * INTRO_LOOK_UP, Vector3.UP)


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
	if _placing != "":
		var spot := _terrain_hit(from, to)
		if spot.is_finite() and _flat(spot, _player.global_position) < 10.0:
			_ghost_pin = spot
		return
	if _pet_freed and _ray_dist(from, to, _pet.global_position + Vector3.UP * 0.35) < 0.9:
		on_pet()
		return
	var best: Dictionary = {}
	var best_d := 99.0
	for node in _nodes:
		if bool(node.get("depleted", false)) or not (node.get("root") as Node3D).visible:
			continue
		var dist := _ray_dist(from, to, _node_aim(node)) / float(node.get("radius", 1.4))
		if dist < 1.0 and dist < best_d:
			best_d = dist
			best = node
	if best.is_empty():
		# Tap the ground to walk there.
		var ground := _terrain_hit(from, to)
		if ground.is_finite() and ground.y > _water_y + LAND_MARGIN:
			_move_goal = ground
			_move_node = {}
		return
	if _flat(_player.global_position, (best.get("root") as Node3D).global_position) < 3.5:
		_act_on_node(best)
	else:
		_move_goal = (best.get("root") as Node3D).global_position
		_move_node = best


## One tap or one Act press = one hit: swing, sound, chips and a shake.
## Trees and rocks take a few hits per piece (chop, chop, crack: +N popup and
## the HUD count ticking up). A found tool means one hit fewer per piece and
## an extra piece on the felling hit; tools are never a lock.
func _act_on_node(node: Dictionary) -> void:
	if node.is_empty() or bool(node.get("depleted", false)):
		return
	var id := str(node.get("id", ""))
	if id == "pet_pile":
		if not _pet_freed:
			_free_pet()
		return
	if _gather_lock > 0.0:
		return
	_gather_lock = 0.5
	var root := node.get("root") as Node3D
	var aim := _node_aim(node)
	var kind := str(node.get("kind", ""))
	var bonus := str(node.get("tool", ""))
	# A found tool adds one extra piece on the final, felling/splitting hit.
	var tool_bonus := 1 if bonus != "" and bool(_tools.get(bonus, false)) and int(node.get("stage", 0)) == int(node.get("stages", 1)) - 1 else 0
	_swing = 0.3
	var face := root.global_position
	face.y = _player.global_position.y
	if _flat(face, _player.global_position) > 0.2:
		_player.look_at(face, Vector3.UP)
	_play_clip("Jump" if kind in ["tree", "rock", "stones", "hull", "rigging"] else "Gather")
	_play(_hit_sound(kind), -3.0, randf_range(0.92, 1.08))
	_shake(root)
	_chips(aim, _chip_color(kind), 14)
	_vibrate(18, 0.4)
	var need_hits := _hits_for(node)
	node["hits"] = int(node.get("hits", 0)) + 1
	if int(node["hits"]) < need_hits:
		_crack_progress(node, aim, float(node["hits"]) / float(need_hits))
		return
	node["hits"] = 0
	var stage := int(node.get("stage", 0))
	var loot: Array = node.get("loot", [])
	if stage < loot.size() and loot[stage] is Array:
		for item in loot[stage]:
			var item_id := str(item.get("id", ""))
			var amount := int(item.get("amount", 1))
			if item_id not in TOOL_IDS:
				amount += tool_bonus
				tool_bonus = 0
			_give(item_id, amount, aim)
	node["stage"] = stage + 1
	_apply_stage(node)
	if int(node["stage"]) >= int(node.get("stages", 1)):
		node["depleted"] = true
		node["left"] = float(node.get("respawn", 42.0))
		root.visible = false
		if float(node.get("respawn", 42.0)) < 0.0:
			_nodes.erase(node)
			root.queue_free()
	if kind == "dig":
		_on_dug(node)
	if id in WRECK_IDS:
		_scavenged += 1
		if _step == "scavenge" and _scavenged >= 3:
			_note_burst("Squeak!")
			_enter("free_pet")


const HITS_PER_PIECE := {"tree": 3, "rock": 3, "stones": 2, "hull": 2, "rigging": 2, "drift": 2}


func _hits_for(node: Dictionary) -> int:
	var hits := int(HITS_PER_PIECE.get(str(node.get("kind", "")), 1))
	var tool := str(node.get("tool", ""))
	if tool != "" and bool(_tools.get(tool, false)):
		hits -= 1
	return maxi(hits, 1)


## In-between hit: a small "crack" tick so every tap still reads as progress.
func _crack_progress(node: Dictionary, aim: Vector3, k: float) -> void:
	var dots := "•".repeat(int(round(k * float(_hits_for(node)))))
	_popup(dots, aim + Vector3.UP * 0.35, Color(0.95, 0.9, 0.75, 0.85))


func _free_pet() -> void:
	_pet_freed = true
	_pet.visible = true
	_pet.global_position = _player.global_position + Vector3(-1.1, 0, 0.8)
	_pet.position.y = _ground_y(_pet.position.x, _pet.position.z)
	var pile := _node_by_id("pet_pile")
	if not pile.is_empty():
		pile["depleted"] = true
		pile["left"] = 0.0
		var pile_root := pile.get("root") as Node3D
		_chips(pile_root.global_position + Vector3.UP * 0.4, Color(0.55, 0.42, 0.28), 22)
		pile_root.visible = false
	_play(AUDIO + "punch.ogg", -4.0, 0.9)
	_play(AUDIO + "bark.ogg", -6.0, 1.2)
	_pet_hop = 0.6
	_vibrate(60, 0.6)
	_note_burst("Friend")
	_enter("name_pet")


func _give(id: String, amount: int, from: Vector3) -> void:
	if id in TOOL_IDS:
		if not bool(_tools.get(id, false)):
			_tools[id] = true
			_note_burst(id.capitalize())
		_refresh_locks()
		if id in ["axe", "pick"]:
			_popup("Axe! Double wood" if id == "axe" else "Pick! Double stone", from + Vector3.UP * (0.4 if id == "axe" else 0.9), Color(1.0, 0.86, 0.45))
	else:
		_inv[id] = int(_inv.get(id, 0)) + amount
		_fly(id, amount, from)
		_popup("+%d %s" % [amount, _item_word(id)], from, _item_color(id))


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
	for id in (["fish", "meat", "food"] if _step == "cook" else RAW_IDS):
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
	_popup("+1 Meal", _pit_position() + Vector3.UP * 0.6, _item_color("cooked"))
	if raw == "fish" and _step == "cook":
		_fish_cooked += 1
		_chips(_pit_position() + Vector3.UP * 0.4, Color(0.9, 0.55, 0.25), 10)
		_line = _line_for("cook")
		if _fish_cooked >= COOK_FISH:
			_note_burst("Meal ready")
			_pointer_id = "pet"
	return true


func _light_fire() -> void:
	_fire_lit = true
	_mark_done("fire")
	if _flame:
		_flame.visible = true
		_flame.global_position = _pit_position()
		_flame.position.y = _ground_y(_flame.position.x, _flame.position.z) + (0.02 if _fire_at.is_finite() else 0.2)
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
	var from := _dusk_spawn()
	_beast.global_position = from
	var look := from - _player.global_position
	look.y = 0.0
	if look.length() > 0.5:
		look = look.normalized()
		_cam_yaw = atan2(-look.x, -look.z)
		_player.look_at(_player.global_position + look, Vector3.UP)
	_apply_dusk_look()
	_play(ROAR, -2.0, 1.0)
	_vibrate(220, 0.8)


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
		var spawn := Vector3(START.x, 0, START.z)
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
	_line = "It's beaten. Tame it or finish it?"
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
	_line = "Something stalks the beach. Fight it off!"
	_show_hint("It shakes free and fights on!")


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
		# Never drop the supplies on a slope, in the surf or up the bank.
		if _player and (at.y < _water_y + 0.2 or absf(at.y - _player.global_position.y) > 0.9 or _slope_at(at.x, at.z, 0.6) > 0.5):
			at = _player.global_position - _player.global_transform.basis.z * 1.4
			at.y = _ground_y(at.x, at.z)
		_sack.global_position = at
	_step = "collect"
	_line = "Collect the supplies"
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
	_build_left -= delta
	var elapsed := _build_total - _build_left
	var stage := clampi(int(elapsed / maxf(_build_total / 3.0, 0.1)) + 1, 1, 3)
	if stage != _hut_stage:
		_hut_stage = stage
		_show_hut(stage)
		var words := ["Frame", "Walls", "Roof"]
		_popup(words[stage - 1], _hut.global_position + Vector3.UP * 2.6, Color(1.0, 0.9, 0.7))
		_play(AUDIO + "build_place.ogg", -6.0, 1.1)
		_chips(_hut.global_position + Vector3.UP * 0.5, Color(0.6, 0.5, 0.36), 16)
	if _build_left <= 0.0:
		_building = false
		_shelter = true
		_hut_stage = 3
		_show_hut(3)
		_pop(_hut)
		_note_burst("Shelter!")
		_vibrate(70, 0.7)
		if _step == "shelter":
			_enter("dusk")


func _tick_respawn(delta: float) -> void:
	for node in _nodes:
		if not bool(node.get("depleted", false)):
			continue
		if str(node.get("id", "")) == "pet_pile" or float(node.get("respawn", 42.0)) < 0.0:
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
	_pet_stats["hunger"] = maxi(0, int(_pet_stats["hunger"]) - (1 if fmod(_age, 6.0) < delta else 0))
	if _sniff_t > 0.0 and _pet_head:
		_sniff_t -= delta
		_pet_head.rotation.x = sin(_age * 9.0) * 0.45
	elif _pet_head:
		_pet_head.rotation.x = 0.0
	if _cinematic == "" and not _naming and _pet:
		_tick_pet(delta)


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
	if _step != "free_pet":
		return
	_squeak_t -= delta
	if _squeak_t <= 0.0:
		_squeak_t = 5.0
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
	_ring.global_position = Vector3(root.global_position.x, _ground_y(root.global_position.x, root.global_position.z) + 0.12, root.global_position.z)
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
		if tool == "axe" and bool(_tools.get("axe", false)):
			text = "Axe: x2"
		elif tool == "pick" and bool(_tools.get("pick", false)):
			text = "Pick: x2"
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
	if _sun:
		_sun.light_energy = 0.62
		_sun.light_color = Color(1.0, 0.62, 0.4)
	if _env:
		_env.fog_light_color = Color(0.45, 0.34, 0.3)
		_env.tonemap_exposure = _base_exposure * 0.85
		_env.adjustment_saturation = 0.86


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
		# The spot Tide-Puck is pointing at wins over a rock or tree beside it.
		if str(node.get("kind", "")) == "dig":
			dist = maxf(dist - 1.2, 0.0)
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


## Fists and a driftwood stick always work; found tools just hit harder.
func _has_weapon() -> bool:
	return true


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


func _landmark_position(id: String) -> Vector3:
	var pair: Array = _catalog.get("landmarks", {}).get(id, [0, 0])
	return _on_land(float(pair[0]), float(pair[1])) if id != "offshore" else Vector3(float(pair[0]), _water_y - 0.25, float(pair[1]))


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
	if _fire_at.is_finite():
		return _fire_at
	if _spot >= 0:
		var at := _pad_position(_spot) + Vector3(2.4, 0, 1.6)
		at.y = _ground_y(at.x, at.z)
		return at
	var camp := _landmark_position("camp") + Vector3(-2.6, 0, 2.2)
	camp.y = _ground_y(camp.x, camp.z)
	return camp


func _point_position() -> Vector3:
	if _placing != "":
		return _ghost.global_position if _ghost and _ghost_ok else _build_spot()
	if _step == "cook":
		var dig0 := _nearest_dig()
		if not dig0.is_empty() and _pet_mode == "point":
			return (dig0.get("root") as Node3D).global_position
		if _fish_cooked >= COOK_FISH:
			return _pet.global_position
		if int(_inv.get("fish", 0)) > 0:
			return _pit_position()
		var fish := _needed_node()
		if not fish.is_empty():
			return (fish.get("root") as Node3D).global_position
		return _pit_position()
	if _step in ["gather", "fire", "shelter"]:
		var dig := _nearest_dig()
		if not dig.is_empty() and _pet_mode == "point":
			return (dig.get("root") as Node3D).global_position
		var need := _needed_node()
		if not need.is_empty():
			return (need.get("root") as Node3D).global_position
		if _building:
			return _hut.global_position
		return _player.global_position
	if _step == "dusk" and _beast and _beast.visible:
		return _beast.global_position
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


## Nudge a point inland (+z, away from the south sea) until it is dry sand.
func _on_land(x: float, z: float) -> Vector3:
	var y := _ground_y(x, z)
	var guard := 0
	while y < _water_y + LAND_MARGIN and guard < 12:
		z += 1.0
		y = _ground_y(x, z)
		guard += 1
	return Vector3(x, y, z)


func _ground_y(x: float, z: float) -> float:
	if _terrain_tm:
		var inv := _terrain_xf.affine_inverse()
		var hit := _terrain_tm.intersect_ray(inv * Vector3(x, 80.0, z), (inv.basis * Vector3.DOWN).normalized())
		if not hit.is_empty():
			return (_terrain_xf * (hit["position"] as Vector3)).y
	if _slice and _slice.has_method("terrain_height_at"):
		return float(_slice.terrain_height_at(x, z))
	return 0.0


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
			"done": bool(row.get("done", false)),
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
		"defeat_path": _defeat_path,
		"silas_shown": _silas_shown,
		"scavenged": _scavenged,
		"storm_left": _storm_left,
		"fish_cooked": _fish_cooked,
		"structures": _structures_state(),
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
	_defeat_path = str(state.get("defeat_path", _defeat_path))
	_silas_shown = bool(state.get("silas_shown", _silas_shown))
	if _defeat_path != "":
		apply_opening_outcome(_defeat_path)
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
	_scavenged = int(state.get("scavenged", 0))
	_storm_left = float(state.get("storm_left", -1.0))
	_fish_cooked = int(state.get("fish_cooked", 0))
	for row in state.get("structures", []):
		if row is Array and row.size() == 5:
			_place_structure(str(row[0]), Vector3(float(row[1]), float(row[2]), float(row[3])), float(row[4]), false)
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
	if _spot >= 0 and not _has_structure("lean_to"):
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
	_research_open = false
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


## The realistic coastal slice is the island. Mount it at the origin, keep its
## own sky, water, terrain and foliage, and hide the bay dressing that would
## crowd the south-beach landing (shore rock piles, the settlement dock and
## its stock wreckage). The slice's ship and debug cameras stay off.
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
		var dressing := _slice.get_node_or_null(NodePath(path)) as Node3D
		if dressing:
			dressing.visible = false
			dressing.process_mode = Node.PROCESS_MODE_DISABLED
	var world := _slice.get_node_or_null("CoastalAtmosphere") as WorldEnvironment
	if world and world.environment:
		world.environment = world.environment.duplicate() as Environment
		_env = world.environment
		_base_exposure = _env.tonemap_exposure
	_sun = _slice.get_node_or_null("WarmSun") as DirectionalLight3D
	if _slice.has_method("water_level"):
		_water_y = float(_slice.water_level())
	var terrain := _slice.get_node_or_null("IrregularCoastalTerrain") as MeshInstance3D
	if terrain and terrain.mesh:
		_terrain_tm = terrain.mesh.generate_triangle_mesh()
		_terrain_xf = terrain.global_transform
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 56.0
	_camera.near = 0.12
	_camera.far = 420.0
	add_child(_camera)
	_camera.make_current()
	_camera.global_position = Vector3(-4, 14, -30)
	_camera.look_at(START + Vector3(0, 1, 0), Vector3.UP)


func _build_props() -> void:
	_dress_landmark("LandmarkWreck", "wreck")
	_dress_landmark("LandmarkGrove", "grove")
	_dress_landmark("LandmarkClearing", "clearing")
	_dress_landmark("LandmarkCamp", "camp")
	_build_offshore()
	_build_landing()
	var clearing := get_node("LandmarkClearing")
	for i in 3:
		var pad := MeshInstance3D.new()
		pad.name = "Pad%d" % i
		var disc := CylinderMesh.new()
		disc.top_radius = 1.55
		disc.bottom_radius = 1.7
		disc.height = 0.12
		pad.mesh = disc
		var dirt := _mat(Color(0.5, 0.42, 0.3, 0.55), 1.0)
		dirt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pad.material_override = dirt
		var at := _pad_position(i)
		pad.position = at - _landmark_position("clearing")
		pad.position.y = at.y - _landmark_position("clearing").y + 0.02
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pad.visible = false
		clearing.add_child(pad)
	_hut = Node3D.new()
	_hut.name = "Hut"
	_hut.visible = false
	clearing.add_child(_hut)
	_build_hut_pieces()
	# Camp: a cold stone ring with a low torch flame (fire is the only light).
	var camp := get_node("LandmarkCamp") as Node3D
	var ring := Art.put(camp, FIRE_PIT, "CampStones", Vector3(0, 0, 0), Vector3(0, 30, 0), 1.0)
	Art.fit_height(ring, 0.5)
	_sit(ring)
	_camp_flame = _flame_mesh()
	_camp_flame.name = "CampTorch"
	_camp_flame.position = Vector3(0, 0.45, 0)
	_camp_flame.scale = Vector3.ONE * 0.7
	camp.add_child(_camp_flame)
	_flame = Node3D.new()
	_flame.name = "PlayerFire"
	_flame.visible = false
	add_child(_flame)
	var pit := Art.put(_flame, FIRE_PIT, "Stones", Vector3.ZERO, Vector3.ZERO, 1.0)
	Art.fit_height(pit, 0.55)
	var logs := Art.put(_flame, DEAD_LOG, "Logs", Vector3(0, 0.05, 0), Vector3(0, 40, 0), 1.0)
	_fit_long(logs, 1.1)
	var fire := _flame_mesh()
	fire.position = Vector3(0, 0.35, 0)
	_flame.add_child(fire)
	_sack = Node3D.new()
	_sack.name = "IdleSack"
	_sack.visible = false
	add_child(_sack)
	var bundle := Art.put(_sack, Art.CRATE_B, "Bundle", Vector3.ZERO, Vector3(0, 20, 0), 1.0)
	Art.fit_height(bundle, 0.7)
	var tag := _label3("Supplies", 1.5)
	_prompt_style(tag, 1.0)
	_sack.add_child(tag)
	_ring = MeshInstance3D.new()
	_ring.name = "TargetRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 6
	_ring.mesh = torus
	var ring_mat := _mat(Color(0.95, 0.9, 0.72, 0.35), 0.9)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = ring_mat
	_ring.visible = false
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


## The approved stills-v2 landing, laid out around START facing inland (+z):
## both hull halves of the player's galleon, cargo, driftwood and jungle edge.
## Nothing here is a dock: the bow half lies rolled onto its side so it reads
## as broken hull, not as a deck of planks.
func _build_landing() -> void:
	var root := Node3D.new()
	root.name = "Landing"
	add_child(root)
	# Bow half lies at the waterline ahead (clear of the walk east), rolled seaward so its keel faces the
	# path and its deck does not read as a jetty. Mesh centre is local z +4.3.
	var yaw := rad_to_deg(atan2(INTRO_FACING.x, INTRO_FACING.z))
	var bow := _on_sand(root, Art.HULL_BOW, "BowHalf", _intro_at(7.5, -4.4) - INTRO_FACING * 4.3, Vector3(0, yaw, -42), 0.46, 0.9)
	_tone_wreck(bow)
	# Stern half heeled over in the surf behind, sails furled and wet.
	var stern_yaw := yaw + 150.0
	var stern_dir := Vector3(sin(deg_to_rad(stern_yaw)), 0, cos(deg_to_rad(stern_yaw)))
	var stern := _on_sand(root, Art.HULL_STERN, "SternHalf", _intro_at(7.0, -9.0) + stern_dir * 2.0, Vector3(0, stern_yaw, -18), 0.46, 1.3)
	_tone_wreck(stern)
	for item in [[Art.CRATE_A, 4.2, -1.6, Vector3(0, 25, 0)], [Art.WINE_BARREL, 3.0, -2.6, Vector3(90, 40, 0)],
			[Art.BARRELS, 5.4, 2.2, Vector3(0, 70, 0)], [Art.DRIFT_TRUNK, -1.0, 2.2, Vector3(0, 100, 0)],
			[Art.DRIFT_BRANCHES, 3.4, 3.0, Vector3(0, 30, 0)], [Art.CHEST, 6.2, -0.6, Vector3(0, -40, 0)]]:
		_on_sand(root, item[0], "Cargo", _intro_at(item[1], item[2]), item[3], 1.0, 0.06)
	var sail := _on_sand(root, Art.TORN_SAIL, "TornSail", _intro_at(2.4, -3.6), Vector3(0, 30, 0), 0.4, 0.0)
	Art.tone(sail, Color(0.5, 0.46, 0.4))
	for clump in [[4.0, 3.6, 2.4], [7.0, 4.2, 2.6], [10.0, 4.0, 2.4], [1.0, 3.8, 2.2]]:
		var bush := _on_sand(root, Art.JUNGLE_CLUMP, "JungleEdge", _intro_at(clump[0], clump[1]), Vector3(0, clump[0] * 37.0, 0), clump[2], 0.05)
		for mesh in Art.meshes(bush):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## START + INTRO_FACING * ahead + player-right * right (right is inland).
func _intro_at(ahead: float, right: float) -> Vector3:
	var side := Vector3(-INTRO_FACING.z, 0.0, INTRO_FACING.x)
	var at := START + INTRO_FACING * ahead + side * right
	at.y = 0.0
	return at


## Wet, sun-bleached wreck: tone the torn sails and rigging down so the
## halves read as hull, not as bright sheets.
func _tone_wreck(node: Node) -> void:
	# The beached halves keep only their hulls: their standing masts and
	# furled sails rendered as black silhouettes against the sky (backlit
	# alpha-scissor rigging), so they are snapped off here.
	for mesh in Art.meshes(node):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var tag := Art.surface_tag(mesh, i)
			if "rigging" in tag or "sail" in tag:
				mesh.visible = false
	Art.tone_matching(node, "sail", Color(0.36, 0.33, 0.29), 1.0)
	Art.tone_matching(node, "plane", Color(0.36, 0.33, 0.29), 1.0)
	Art.tone_matching(node, "rigging", Color(0.46, 0.43, 0.38), 1.0)


func _on_sand(parent: Node, scene: PackedScene, node_name: String, at: Vector3, rot_deg: Vector3, scale: float, sink: float) -> Node3D:
	at.y = _ground_y(at.x, at.z) - sink
	return Art.put(parent, scene, node_name, at, rot_deg, scale)


func _fit_long(node: Node3D, meters: float) -> void:
	var box := Art.world_aabb(node)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest > 0.001:
		node.scale *= meters / longest


## Drop `node` so the bottom of its mesh bounds sits at its parent's origin.
func _sit(node: Node3D) -> void:
	var parent := node.get_parent() as Node3D
	if parent == null:
		return
	var box := Art.world_aabb(node)
	node.global_position.y += parent.global_position.y - box.position.y


func _dress_landmark(node_name: String, id: String) -> void:
	var marker := Node3D.new()
	marker.name = node_name
	var at := _landmark_position(id)
	marker.position = at
	add_child(marker)


func _build_offshore() -> void:
	var root := Node3D.new()
	root.name = "LandmarkOffshore"
	var at: Array = _catalog.get("landmarks", {}).get("offshore", [-6, -32])
	root.position = Vector3(float(at[0]), _water_y, float(at[1]))
	add_child(root)
	# The enemy galleon's stern half, settled on the reef past the surf.
	var hull := Art.put(root, Art.HULL_STERN, "BrokenHull", Vector3(9, -1.6, 3), Vector3(-8, 120, 24), 0.42)
	Art.tone_matching(hull, "sail", Color(0.42, 0.39, 0.34), 1.0)
	Art.tone_matching(hull, "rigging", Color(0.5, 0.47, 0.42), 1.0)
	# The leviathan's severed tentacle drifting awash, in the approved creature grade.
	var carcass := Node3D.new()
	carcass.name = "Leviathan"
	root.add_child(carcass)
	var limb := Art.put(carcass, Art.LEVIATHAN_TENTACLE, "Tentacle", Vector3(-6, -0.5, 0), Vector3(84, 30, 0), 1.0)
	_fit_long(limb, 13.0)
	Art.grade_creature(limb)
	Art.foam_ring(self, root.position + Vector3(-6, 0, 0), 4.0, _water_y)
	var fin_mat := _mat(Color(0.16, 0.18, 0.19), 0.55)
	for i in 3:
		var fin := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.08, 0.62, 0.7)
		prism.left_to_right = 0.2
		fin.mesh = prism
		fin.material_override = fin_mat
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fin)
		_sharks.append(fin)
	var warning := _label3(OFFSHORE_WARNING, 4.5)
	warning.name = "Warning"
	warning.visible = false
	root.add_child(warning)
	var sign := Node3D.new()
	sign.name = "BeachSign"
	sign.position = _on_land(-3.0, 0.5)
	add_child(sign)
	var post := Art.put(sign, Art.DRIFT_TRUNK, "Post", Vector3.ZERO, Vector3(0, 0, 90), 1.0)
	_fit_long(post, 1.7)
	post.position.y = 0.85
	var board := _label3("Sharks!", 1.95)
	board.pixel_size = 0.006
	board.modulate = Color(0.95, 0.85, 0.6)
	sign.add_child(board)


## Hut stages: 1 frame of driftwood posts, 2 plank walls going up, 3 the
## finished thatched hut (Hunyuan3D mesh, see assets/ashore/PROVENANCE.md).
func _build_hut_pieces() -> void:
	var frame := Node3D.new()
	frame.name = "Frame"
	_hut.add_child(frame)
	for i in 4:
		var post := Art.put(frame, Art.DRIFT_TRUNK, "Post%d" % i, Vector3(-1.3 if i % 2 == 0 else 1.3, 1.1, -1.0 if i < 2 else 1.0), Vector3(0, float(i) * 50.0, 90), 1.0)
		_fit_long(post, 2.3)
	var walls := Node3D.new()
	walls.name = "Walls"
	_hut.add_child(walls)
	for spec in [[Vector3(0, 0, -1.0), 0.0], [Vector3(-1.3, 0, 0), 90.0], [Vector3(1.3, 0, 0), -90.0]]:
		var stack := Art.put(walls, Art.PLANKS, "Planks", spec[0], Vector3(0, spec[1], 0), 1.0)
		_fit_long(stack, 2.4)
	var roof := Art.put(_hut, HUT, "Roof", Vector3.ZERO, Vector3(0, 180, 0), 1.0)
	Art.fit_height(roof, 3.0)
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
		frame.visible = stage >= 1 and stage < 3
	if walls:
		walls.visible = stage == 2
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
		_measure_node(node)
		_nodes.append(node)


## Resource-node visuals: real-scale library meshes (CC0 Poly Haven and
## Quaternius, plus the provenance-tracked Hunyuan3D clumps). Sizes are world
## metres; _prop undoes the node root's gameplay scale.
func _visual_for(kind: String, root: Node3D) -> void:
	match kind:
		"hull":
			_prop(root, Art.PLANKS, "Planks", Vector3.ZERO, 0.5, 0.4, 2.0)
			_prop(root, Art.SNAPPED_MAST, "Beam", Vector3(0.45, 0, 0.3), 0.35, 1.3, 2.6)
		"rigging":
			_prop(root, Art.ROPE, "Rope", Vector3.ZERO, 0.12, 0.3, 1.0)
			_prop(root, Art.DRIFT_TRUNK, "Spar", Vector3(0.1, 0, 0.35), 0.25, 1.1, 2.4)
		"cargo":
			_prop(root, Art.CRATE_A, "Chest", Vector3.ZERO, 0.55, 0.5, 0.0)
			_prop(root, Art.WINE_BARREL, "Barrel", Vector3(0.5, 0, 0.3), 0.8, 0.2, 0.0)
		"pile":
			_prop(root, Art.CRATE_B, "Crate", Vector3(-0.3, 0, 0.1), 0.45, 0.4, 0.0)
			_prop(root, Art.ROPE, "Rope", Vector3(0.25, 0, -0.2), 0.1, 1.1, 0.9)
			_prop(root, Art.DRIFT_BRANCHES, "Branches", Vector3(0.1, 0, 0.3), 0.35, 2.0, 1.8)
		"bush":
			_prop(root, Art.JUNGLE_CLUMP, "Bush", Vector3.ZERO, 1.4, 0.0, 0.0)
			_fruit(root, Vector3(0.12, 0.42, 0.1))
			_fruit(root, Vector3(-0.14, 0.48, -0.06))
		"crab":
			_prop(root, ASHORE_STONE, "Stones", Vector3.ZERO, 0.12, 0.6, 0.0)
			_crab(root)
		"tree":
			if not _palm(root, 6.5 if root.name.ends_with("a") else 5.2):
				_prop(root, DEAD_LOG, "Tree", Vector3.ZERO, 0.9, 0.6, 0.0)
		"rock":
			_prop(root, Art.DARK_BOULDER, "Rocks", Vector3.ZERO, 0.9, 0.3, 1.6)
		"flint":
			_prop(root, ASHORE_STONE, "Rocks", Vector3.ZERO, 0.14, 0.9, 0.0)
			_prop(root, ASHORE_STONE, "RocksB", Vector3(0.12, 0, 0.08), 0.1, 2.1, 0.0)
		"fish":
			_fish(root)
		"drift":
			_prop(root, Art.DRIFT_TRUNK, "Drift", Vector3.ZERO, 0.26, 0.7, 2.6)
		"stones":
			_prop(root, ASHORE_STONE, "Rocks", Vector3.ZERO, 0.22, 0.4, 0.0)
			_prop(root, ASHORE_STONE, "RocksB", Vector3(0.16, 0, 0.1), 0.16, 2.1, 0.0)
			_prop(root, ASHORE_STONE, "RocksC", Vector3(-0.12, 0, 0.14), 0.12, 4.0, 0.0)
		"fibre":
			_prop(root, Art.JUNGLE_CLUMP, "Fibre", Vector3.ZERO, 0.75, 0.0, 0.0)
		_:
			_prop(root, Art.CRATE_A, "Crate", Vector3.ZERO, 0.6, 0.0, 0.0)


func _crab(root: Node3D) -> void:
	var shell := _mat(Color(0.55, 0.24, 0.16), 0.62)
	var body := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.16
	dome.height = 0.14
	dome.radial_segments = 16
	dome.rings = 8
	body.mesh = dome
	body.material_override = shell
	_unscaled(root, body, Vector3(0.18, 0.06, 0.1))
	for side in [-1.0, 1.0]:
		var claw := MeshInstance3D.new()
		var pincer := SphereMesh.new()
		pincer.radius = 0.06
		pincer.height = 0.09
		pincer.radial_segments = 10
		pincer.rings = 5
		claw.mesh = pincer
		claw.material_override = shell
		_unscaled(root, claw, Vector3(0.18 + side * 0.14, 0.05, -0.05))


func _fish(root: Node3D) -> void:
	var skin := _mat(Color(0.42, 0.5, 0.52), 0.42)
	for i in 2:
		var fish := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.06
		capsule.height = 0.42
		capsule.radial_segments = 12
		capsule.rings = 4
		fish.mesh = capsule
		fish.material_override = skin
		fish.rotation_degrees = Vector3(0, 30.0 + float(i) * 70.0, 90)
		_unscaled(root, fish, Vector3(float(i) * 0.22 - 0.1, 0.05, float(i) * 0.12))


## Add a small hand-sized mesh under a scaled node root at true world size.
func _unscaled(root: Node3D, mesh: MeshInstance3D, at_world: Vector3) -> void:
	var k := 1.0 / maxf(root.global_transform.basis.get_scale().y, 0.001)
	mesh.position = at_world * k
	mesh.scale = Vector3.ONE * k
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)


## Choppable palms reuse the island grove's own palm mesh so they match it.
func _palm(root: Node3D, height: float) -> bool:
	var grove := _slice.get_node_or_null("TropicalBayDressing/TropicalPalmGrove") as MultiMeshInstance3D if _slice else null
	if grove == null or grove.multimesh == null or grove.multimesh.mesh == null:
		return false
	var tree := MeshInstance3D.new()
	tree.name = "Tree"
	tree.mesh = grove.multimesh.mesh
	tree.material_override = grove.material_override
	var box := tree.mesh.get_aabb()
	var k := height / maxf(box.size.y, 0.01) / maxf(root.global_transform.basis.get_scale().y, 0.001)
	tree.scale = Vector3.ONE * k
	tree.position.y = -box.position.y * k
	tree.rotation.y = 0.6
	root.add_child(tree)
	return true


func _prop(parent: Node3D, path: Variant, node_name: String, at: Vector3, height: float, yaw: float, width: float) -> Node3D:
	var packed = load(path) if path is String else path
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
		var k := height / box.size.y
		if width > 0.0:
			k = minf(k, width / maxf(maxf(box.size.x, box.size.z), 0.001))
		model.scale *= k
		var fitted := _merged_aabb(model)
		var bottom := (parent.global_transform * at).y
		model.global_position.y += bottom - fitted.position.y
	return model


func _fruit(root: Node3D, at_world: Vector3) -> void:
	for i in 3:
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.035
		sphere.height = 0.07
		sphere.radial_segments = 8
		sphere.rings = 4
		mesh.mesh = sphere
		mesh.material_override = _mat(Color(0.48, 0.12, 0.16), 0.5)
		_unscaled(root, mesh, at_world + Vector3(float(i) * 0.05, float(i % 2) * 0.04, 0.0))


## Small low fire: two crossed soft flame cards over the stones. Fire is the
## only emissive surface on the island.
func _flame_mesh() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var card := QuadMesh.new()
	card.size = Vector2(0.55, 0.75)
	mesh.mesh = card
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_texture = Art.SOFT
	mat.albedo_color = Color(1.0, 0.5, 0.16, 0.85)
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 1.2
	light.omni_range = 5.0
	light.light_specular = 0.0
	mesh.add_child(light)
	return mesh


## Castaway: rigged Quaternius UBC body with UAL clips (CC0), wet linen shirt.
func _build_player() -> void:
	_player = Node3D.new()
	_player.name = "Player"
	_player.position = _on_land(START.x, START.z)
	add_child(_player)
	var rig := _rig(Art.CASTAWAY, {"Idle": "|Idle", "Walk": "|Walk", "Run": "|Run", "Jump": "|Attack", "Gather": "|Interact", "Kneel": "|Kneel"})
	if rig:
		rig.name = "Rig"
		_player.add_child(rig)
		_fit(rig, 1.78)
		_anim = rig.get_meta("clips") as AnimationPlayer
		_collect_skin(rig)
	_player.look_at(_player.position + INTRO_FACING, Vector3.UP)
	_cam_yaw = _player.rotation.y


## Tide-Puck: Hunyuan3D seal pup with the bandaged front flipper (model +X).
## Visible from the first frame, pinned beside the wreck pile.
func _build_pet() -> void:
	_pet = Node3D.new()
	_pet.name = "Pet"
	add_child(_pet)
	var body := Art.spawn(Art.TIDEPUCK, "Body")
	body.rotation.y = PI
	body.scale = Vector3.ONE * PET_SCALE
	_pet.add_child(body)
	_pet_head = Node3D.new()
	_pet_head.name = "Head"
	_pet_head.position = Vector3(0, 0.3, -0.45)
	_pet.add_child(_pet_head)
	var name_label := _label3("Tide-Puck", 0.75)
	name_label.name = "Name"
	name_label.pixel_size = 0.0032
	name_label.modulate = Color(1, 0.95, 0.8, 0.9)
	_pet.add_child(name_label)
	_pet.position = _pet_rest()
	# Face the camera three-quarter so the bandage reads (see PROVENANCE.md render).
	_pet.rotation_degrees.y = PET_REST_YAW


func _pet_rest() -> Vector3:
	var at := _intro_at(PET_REST.x, PET_REST.y)
	at.y = _ground_y(at.x, at.z)
	return at


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
	return _rig(Art.CASTAWAY, {"Idle": "|Idle", "Run": "|Run", "Jump": "|Attack", "Walk": "|Walk"})


func _rig(path: Variant, clips: Dictionary) -> Node3D:
	var packed = load(path) if path is String else path
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
					anim.loop_mode = Animation.LOOP_NONE if alias in ["Jump", "Death", "Bite", "Punch", "Gather"] else Animation.LOOP_LINEAR
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
		"attack": _beast != null and _beast.visible and _creature_hostile and _choice != "kill" and _flat(_player.global_position, _beast.global_position) < 16.0,
		"skip": _cinematic != "",
		"fork": _fork,
		"qte": _qte,
		"qte_marker": fposmod(_tame_phase, float(_tuning.get("tame_period", 2.0))) / float(_tuning.get("tame_period", 2.0)),
		"qte_a": 0.68,
		"qte_b": 0.84,
		"qte_ratio": clampf(_tame_left / maxf(_tame_total, 0.1), 0.0, 1.0),
		"research_open": false,
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
			{"t": "Sniffs out buried loot", "on": true},
			{"t": "Fetches wood and food", "on": true},
			{"t": "Warns of danger", "on": true},
			{"t": "Fighting", "on": false},
		],
		"spyglass": false,
		"letterbox": _cinematic != "",
		"alert": _alerted and _choice == "",
		"build_on": _building,
		"build_ratio": 0.0 if _build_total <= 0.0 else clampf(1.0 - _build_left / _build_total, 0.0, 1.0),
		"pointer": pointer_on,
		"pointer_at": pointer_at,
		"build_open": _build_open,
		"build_rows": _build_rows(),
		"placing": _placing != "",
		"place_ok": _ghost_ok,
		"build_hint": (_step == "fire" and not _fire_lit and _can_pay("campfire")) or (_step == "shelter" and _hut_stage == 0 and not _building and _can_pay("lean_to")),
		"pet_bond": int(_pet_stats.get("bond", 0)),
		"pet_finds": _pet_finds,
		"pet_fetches": _pet_fetches,
		"pet_mode": _pet_mode,
	})


func _action_caption() -> String:
	if _placing != "":
		return "Place"
	if _collect_ready and _sack and _near(_sack.global_position, 3.4):
		return "Take"
	if not _pet_freed:
		var pile := _node_by_id("pet_pile")
		if not pile.is_empty() and _near((pile.get("root") as Node3D).global_position, 3.5):
			return "Free"
	var node := _nearest_node(3.5)
	if not node.is_empty():
		match str(node.get("kind", "")):
			"tree", "drift":
				return "Chop"
			"rock", "stones", "flint":
				return "Mine"
			"dig":
				return "Dig"
			"fibre":
				return "Cut"
			"bush", "crab":
				return "Forage"
			"fish":
				return "Fish"
		return "Search"
	if _fire_lit and _near(_pit_position(), 3.4) and _raw_food() != "":
		return "Cook"
	if _food_total() > 0 and _hunger < 97.0:
		return "Eat"
	if _pet_freed and _near(_pet.global_position, 2.4):
		return "Pet"
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


func defeat_path() -> String:
	return _defeat_path


func _read_opening_outcome() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://opening_battle.cfg") != OK:
		return
	var path := str(cfg.get_value("opening", "defeat_path", ""))
	if path != "":
		apply_opening_outcome(path)


func apply_opening_outcome(path: String) -> void:
	if path != "mast" and path != "hull":
		return
	_defeat_path = path
	if not _outcome_applied:
		_outcome_applied = true
		if path == "mast":
			_boost_node_loot("hull", "planks", 2)
			_boost_node_loot("rigging", "rope", 2)
		else:
			_boost_node_loot("cargo_cloth", "cloth", 2)
			_boost_node_loot("cargo_tools", "cloth", 1)
	if path == "mast" and get_node_or_null("MastPlank0") == null:
		_place_outcome_props(true)
	elif path == "hull" and get_node_or_null("SinkCargo0") == null:
		_place_outcome_props(false)
	_place_silas_cutlass()


func _boost_node_loot(node_id: String, item_id: String, extra: int) -> void:
	var node := _node_by_id(node_id)
	if node.is_empty():
		return
	var loot: Array = node.get("loot", [])
	if loot.is_empty():
		node["loot"] = [[{"id": item_id, "amount": extra}]]
		return
	var first = loot[0]
	if first is Array:
		var found := false
		for entry in first:
			if entry is Dictionary and str(entry.get("id", "")) == item_id:
				entry["amount"] = int(entry.get("amount", 1)) + extra
				found = true
				break
		if not found:
			first.append({"id": item_id, "amount": extra})


## Path-dependent flotsam. Mast ending: the reef wreck's spars and planks wash
## up. Hull ending: the sunk ship's cargo floats in. Both sit on the open sand
## left of the landing (player's left, toward the bow half), clear of nodes.
func _place_outcome_props(mast: bool) -> void:
	if mast:
		for i in 3:
			var at := _intro_at(4.6 + float(i) * 1.5, -1.0 - float(i % 2) * 1.1)
			var plank := _on_sand(self, Art.PLANKS if i != 1 else Art.DRIFT_TRUNK, "MastPlank%d" % i, at, Vector3(0, float(i) * 55.0, 0), 1.0, 0.04)
			_fit_long(plank, 1.9 if i != 1 else 2.6)
		var spar := _on_sand(self, Art.SNAPPED_MAST, "MastRopeSpar", _intro_at(9.4, 0.6), Vector3(0, 80, 82), 1.0, 0.1)
		_fit_long(spar, 3.4)
	else:
		for i in 3:
			var at := _intro_at(4.4 + float(i) * 1.4, -0.8 - float(i % 2) * 1.2)
			var scene: PackedScene = [Art.CRATE_B, Art.WINE_BARREL, Art.CRATE_A][i]
			var rot := Vector3(90, 0, float(i) * 40.0) if i == 1 else Vector3(0, float(i) * 35.0, 0)
			_on_sand(self, scene, "SinkCargo%d" % i, at, rot, 1.0, 0.05)


## Silas's cutlass, driven point-down into the sand beside the landing: the
## Quaternius-style saber mesh at real size, a third of the blade buried.
func _place_silas_cutlass() -> void:
	if get_node_or_null("SilasCutlass"):
		return
	var at := _intro_at(CUTLASS_AT.x, CUTLASS_AT.y)
	at.y = _ground_y(at.x, at.z)
	var holder := Node3D.new()
	holder.name = "SilasCutlass"
	holder.position = at
	add_child(holder)
	# Native saber stands 0.94 m on +Y, grip at the origin. Flip it point-down,
	# lean it 14 degrees and sink 0.3 m of blade into the sand.
	var blade := Art.put(holder, Art.CUTLASS, "Blade", Vector3.ZERO, Vector3(180 + 12, 60, -10), 1.3)
	blade.position.y = 0.84 * 1.3 - 0.32
	var mound := Art.soft_disc(holder, at + Vector3(0, 0.02, 0), 0.7, Color(0.42, 0.34, 0.24, 0.6), false)
	mound.name = "WetSand"
	var label := _label3("Silas's cutlass", 0.95)
	label.name = "Title"
	label.pixel_size = 0.003
	label.modulate = Color(1, 0.95, 0.8, 0.9)
	holder.add_child(label)


func _tick_silas_hint() -> void:
	if _silas_shown or _player == null:
		return
	var blade := get_node_or_null("SilasCutlass") as Node3D
	if blade == null:
		return
	if _flat(_player.global_position, blade.global_position) < 3.2:
		_silas_shown = true
		# A hint, not the quest tracker: the tracker stays one short goal.
		_show_hint("Silas's cutlass... no sign of him")
		_push_hud()



# ---------------------------------------------------------------------------
# Rescue v2: quest pacing, building, pet behaviour, camera, feedback.
# ---------------------------------------------------------------------------

func _tick_quest(delta: float) -> void:
	if _step == "gather":
		if int(_inv.get("wood", 0)) >= GATHER_WOOD and int(_inv.get("stone", 0)) >= GATHER_STONE:
			_note_burst("Ready to build!")
			_play(AUDIO + "build_place.ogg", -8.0, 1.2)
			_enter("fire")
	elif _step == "fire" and _fire_lit:
		_enter("shelter")
	elif _step == "shelter" and _storm_left >= 0.0 and not _building:
		_storm_left -= delta
		if _storm_left < 40.0 and not _storm_warned:
			_storm_warned = true
			_show_hint("%s senses the storm. Hurry!" % str(_pet_stats.get("name", "Tide-Puck")))
			_hint_t = 4.0
			if _pet_freed:
				_play(AUDIO + "bark.ogg", -6.0, 0.7)
				_pet_hop = 0.5
		if _storm_left <= 0.0:
			_storm_left = -1.0
			_show_hint("The storm hits. No shelter!")
			_hint_t = 4.0
			_warmth = maxf(_warmth - 20.0, 10.0)
			_enter("dusk")
	elif _step == "shelter" and _building:
		_storm_left = maxf(_storm_left - delta * 0.25, 1.0)


func _raw_food() -> String:
	for id in RAW_IDS:
		if int(_inv.get(id, 0)) > 0:
			return id
	return ""


func _shortfall_text(recipe_name: String) -> String:
	var recipe: Dictionary = _catalog.get("recipes", {}).get(recipe_name, {})
	var parts: Array = []
	for key in recipe.keys():
		if str(key) == "seconds":
			continue
		var short := int(recipe[key]) - int(_inv.get(key, 0))
		if short > 0:
			parts.append("%d %s" % [short, _item_word(str(key)).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _cost_text(recipe_name: String) -> String:
	var recipe: Dictionary = _catalog.get("recipes", {}).get(recipe_name, {})
	var parts: Array = []
	for key in recipe.keys():
		if str(key) == "seconds":
			continue
		parts.append("%d %s" % [int(recipe[key]), _item_word(str(key))])
	return " · ".join(parts)


func _item_word(id: String) -> String:
	match id:
		"planks":
			return "Planks"
		"fibre":
			return "Fibre"
		"cooked":
			return "Meal"
	return id.capitalize()


func _item_color(id: String) -> Color:
	match id:
		"wood":
			return Color(0.95, 0.72, 0.45)
		"stone", "flint":
			return Color(0.85, 0.88, 0.92)
		"fibre":
			return Color(0.7, 0.95, 0.45)
		"food", "fish", "meat", "cooked":
			return Color(1.0, 0.6, 0.5)
		"planks", "rope", "cloth":
			return Color(1.0, 0.86, 0.6)
	return Color(1, 0.95, 0.8)


func _hit_sound(kind: String) -> String:
	match kind:
		"tree", "drift":
			return AUDIO + "chop.ogg"
		"rock", "stones", "flint":
			return AUDIO + "stone_hit.ogg"
		"dig":
			return AUDIO + "dig.ogg"
		"bush", "fibre", "crab", "fish":
			return AUDIO + "crunch.ogg"
	return AUDIO + "punch.ogg"


func _chip_color(kind: String) -> Color:
	match kind:
		"tree", "drift", "hull", "rigging", "cargo":
			return Color(0.55, 0.38, 0.22)
		"rock", "stones", "flint":
			return Color(0.6, 0.6, 0.58)
		"dig":
			return Color(0.78, 0.68, 0.5)
		"bush", "fibre":
			return Color(0.35, 0.55, 0.2)
	return Color(0.7, 0.6, 0.45)


## Rising "+1 Wood" label in the world, fades out over a second.
func _popup(text: String, at: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	if _font:
		label.font = _font
	label.font_size = 48
	label.pixel_size = 0.0065
	label.outline_size = 12
	label.modulate = color
	label.outline_modulate = Color(0.06, 0.04, 0.02, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	add_child(label)
	label.global_position = at + Vector3(randf_range(-0.15, 0.15), 0.9, 0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y + 1.1, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.6)
	tween.chain().tween_callback(label.queue_free)


## Small shaded chips flying off a hit (wood splinters, stone grit, sand).
func _chips(at: Vector3, color: Color, amount: int) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = amount
	particles.lifetime = 0.7
	particles.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	add_child(particles)
	particles.global_position = at
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 70.0
	process.initial_velocity_min = 1.6
	process.initial_velocity_max = 3.6
	process.gravity = Vector3(0, -11, 0)
	process.angular_velocity_min = -360.0
	process.angular_velocity_max = 360.0
	process.scale_min = 0.6
	process.scale_max = 1.3
	particles.process_material = process
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.05, 0.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	box.material = mat
	particles.draw_pass_1 = box
	particles.emitting = true
	get_tree().create_timer(1.2).timeout.connect(particles.queue_free)


func _vibrate(ms: int, strength: float) -> void:
	_haptics.append([snappedf(_age, 0.01), ms])
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, strength)


func _pop(node: Node3D) -> void:
	if node == null:
		return
	var base := node.scale
	node.scale = base * 0.2
	var tween := create_tween()
	tween.tween_property(node, "scale", base * 1.08, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", base, 0.12)


## Node interaction centre: the middle of its visible model, not its foot.
func _node_aim(node: Dictionary) -> Vector3:
	var root := node.get("root") as Node3D
	var off: Vector3 = node.get("aim_off", Vector3(0, 0.5, 0))
	var k := root.scale.x / maxf(float(node.get("scale", 1.0)), 0.01)
	return root.global_position + off * k


func _measure_node(node: Dictionary) -> void:
	var root := node.get("root") as Node3D
	var box := _merged_aabb(root)
	var labels_free := box
	if box.size.length() < 0.01:
		node["aim_off"] = Vector3(0, 0.5, 0)
		node["radius"] = 1.2
		return
	var centre := labels_free.position + labels_free.size * 0.5
	node["aim_off"] = centre - root.global_position
	var half := maxf(box.size.x, box.size.z) * 0.5
	node["radius"] = clampf(maxf(half, box.size.y * 0.5) + 0.35, 0.9, 2.6)


func _terrain_hit(from: Vector3, to: Vector3) -> Vector3:
	if _terrain_tm == null:
		return Vector3(INF, INF, INF)
	var inv := _terrain_xf.affine_inverse()
	var dir := (to - from).normalized()
	var hit := _terrain_tm.intersect_ray(inv * from, (inv.basis * dir).normalized())
	if hit.is_empty():
		return Vector3(INF, INF, INF)
	return _terrain_xf * (hit["position"] as Vector3)


func _orbit_drag(pos: Vector2, relative: Vector2) -> void:
	if pos.distance_to(_drag_from) > 14.0:
		_drag_moved = true
	if _drag_moved and _cinematic == "" and not _fork and not _qte:
		_cam_yaw -= relative.x * 0.0065
		_cam_orbit_hold = 2.0


func _slope_at(x: float, z: float, r: float) -> float:
	var gx := _ground_y(x + r, z) - _ground_y(x - r, z)
	var gz := _ground_y(x, z + r) - _ground_y(x, z - r)
	return Vector2(gx, gz).length() / (2.0 * r)


# --- building --------------------------------------------------------------

func on_build_toggle() -> void:
	if _cinematic != "" or _fork or _qte or _naming:
		return
	if _placing != "":
		on_build_cancel()
		return
	_build_open = not _build_open


func on_build_pick(id: String) -> void:
	if id == "campfire" and _fire_lit:
		_show_hint("The campfire is already burning")
		return
	if id == "lean_to" and (_hut_stage > 0 or _building):
		_show_hint("You already have a lean-to")
		return
	if id == "storage" and _has_structure("storage"):
		_show_hint("You already have a storage crate")
		return
	if not _can_pay(id):
		_show_hint("%s needs %s more" % [BUILD_TITLES.get(id, id), _shortfall_text(id)])
		_hint_t = 2.6
		_play(AUDIO + "punch.ogg", -12.0, 0.7)
		return
	_build_open = false
	_placing = id
	_ghost_pin = Vector3(INF, INF, INF)
	_make_ghost(id)
	_show_hint("Green = OK. Tap the ground to move it, then Place")
	_hint_t = 3.0


func on_build_place() -> void:
	if _placing == "" or _ghost == null:
		return
	if not _ghost_ok:
		# Snap to the nearest good ground within a few metres of the ghost.
		var alt := _nearest_site(_placing, _ghost.global_position, 4.5)
		if not alt.is_finite():
			_show_hint(_ghost_why)
			_play(AUDIO + "punch.ogg", -12.0, 0.7)
			return
		_ghost.global_position = alt
	if not _can_pay(_placing):
		_show_hint("Need " + _shortfall_text(_placing))
		on_build_cancel()
		return
	_pay(_placing)
	var at := _ghost.global_position
	var yaw := _ghost.rotation.y
	var id := _placing
	on_build_cancel()
	_place_structure(id, at, yaw, true)


func on_build_cancel() -> void:
	_placing = ""
	_ghost_pin = Vector3(INF, INF, INF)
	if _ghost:
		_ghost.queue_free()
		_ghost = null


func _has_structure(id: String) -> bool:
	for row in _structures:
		if str(row.get("id", "")) == id:
			return true
	return false


func _structures_state() -> Array:
	var rows: Array = []
	for row in _structures:
		var at: Vector3 = row.get("at", Vector3.ZERO)
		rows.append([str(row.get("id", "")), at.x, at.y, at.z, float(row.get("yaw", 0.0))])
	return rows


func _build_rows() -> Array:
	var rows: Array = []
	for id in BUILD_IDS:
		var built: bool = (id == "campfire" and _fire_lit) or (id == "lean_to" and (_hut_stage > 0 or _building)) or (id == "storage" and _has_structure("storage"))
		rows.append({"id": id, "title": BUILD_TITLES[id], "cost": _cost_text(id), "ok": _can_pay(id) and not built, "built": built})
	return rows


func _make_ghost(id: String) -> void:
	if _ghost:
		_ghost.queue_free()
	_ghost = Node3D.new()
	_ghost.name = "BuildGhost"
	add_child(_ghost)
	_ghost.global_position = _player.global_position
	match id:
		"campfire":
			var pit := Art.put(_ghost, FIRE_PIT, "Stones", Vector3.ZERO, Vector3.ZERO, 1.0)
			Art.fit_height(pit, 0.55)
			var logs := Art.put(_ghost, DEAD_LOG, "Logs", Vector3(0, 0.05, 0), Vector3(0, 40, 0), 1.0)
			_fit_long(logs, 1.1)
		"lean_to":
			var roof := Art.put(_ghost, HUT, "Roof", Vector3.ZERO, Vector3(0, 180, 0), 1.0)
			Art.fit_height(roof, 3.0)
		"storage":
			var chest := Art.put(_ghost, Art.CHEST, "Chest", Vector3.ZERO, Vector3.ZERO, 1.0)
			Art.fit_height(chest, 0.75)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = Color(0.45, 0.95, 0.5, 0.45)
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mesh in _meshes(_ghost):
		mesh.material_override = _ghost_mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = float(BUILD_RADIUS.get(id, 1.0))
	disc.bottom_radius = disc.top_radius
	disc.height = 0.04
	ring.mesh = disc
	ring.material_override = _ghost_mat
	ring.position.y = 0.03
	_ghost.add_child(ring)


func _tick_ghost() -> void:
	if _ghost == null:
		return
	var fwd := -_player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var r := float(BUILD_RADIUS.get(_placing, 1.0))
	var at := _ghost_pin if _ghost_pin.is_finite() else _player.global_position + fwd * (r + 1.3)
	at.y = _ground_y(at.x, at.z)
	_ghost.global_position = at
	var face := _player.global_position - at
	face.y = 0.0
	if face.length() > 0.1:
		_ghost.rotation.y = atan2(face.x, face.z)
	_ghost_why = _site_problem(_placing, at)
	_ghost_ok = _ghost_why == ""
	_ghost_mat.albedo_color = Color(0.45, 0.95, 0.5, 0.45) if _ghost_ok else Color(1.0, 0.36, 0.3, 0.45)


## Why a structure cannot go at `at` ("" when the site is fine).
func _site_problem(id: String, at: Vector3) -> String:
	var r := float(BUILD_RADIUS.get(id, 1.0))
	if at.y < _water_y + 0.3:
		return "Too wet. Build on dry sand"
	var lo := INF
	var hi := -INF
	for k in 6:
		var a := TAU * float(k) / 6.0
		var y := _ground_y(at.x + cos(a) * r, at.z + sin(a) * r)
		if y < _water_y + 0.05:
			return "Too close to the water"
		lo = minf(lo, y)
		hi = maxf(hi, y)
	if (hi - lo) / (2.0 * r) > 0.62:
		return "Too steep here. Find flat ground"
	for row in _structures:
		var other: Vector3 = row.get("at", Vector3.ZERO)
		if _flat(other, at) < r + float(BUILD_RADIUS.get(str(row.get("id", "")), 1.0)) + 0.4:
			return "Too close to your %s" % str(BUILD_TITLES.get(str(row.get("id", "")), "camp")).to_lower()
	for node in _nodes:
		if bool(node.get("depleted", false)):
			continue
		if _flat((node.get("root") as Node3D).global_position, at) < r + 0.5:
			return "Something is in the way"
	if _flat(_player.global_position, at) < r * 0.7:
		return "Step back a little"
	return ""


func _nearest_site(id: String, around: Vector3, reach: float) -> Vector3:
	var ring := 0.6
	while ring <= reach:
		for k in 12:
			var a := TAU * float(k) / 12.0
			var p := around + Vector3(cos(a), 0, sin(a)) * ring
			p.y = _ground_y(p.x, p.z)
			if _site_problem(id, p) == "":
				return p
		ring += 0.6
	return Vector3(INF, INF, INF)


## Nearest good build site around the player (bot and pointer fallback).
func _build_spot() -> Vector3:
	var id := _placing if _placing != "" else "lean_to"
	var best := _player.global_position
	var best_d := INF
	for ring in [3.0, 5.0, 7.0, 9.0]:
		for k in 12:
			var a := TAU * float(k) / 12.0
			var p: Vector3 = _player.global_position + Vector3(cos(a), 0, sin(a)) * ring
			p.y = _ground_y(p.x, p.z)
			if _site_problem(id, p) == "" and ring < best_d:
				best_d = ring
				best = p
		if best_d < INF:
			break
	return best


func _place_structure(id: String, at: Vector3, yaw: float, fresh: bool) -> void:
	_structures.append({"id": id, "at": at, "yaw": yaw})
	var shown: Node3D = null
	match id:
		"campfire":
			_fire_at = at
			_light_fire()
			shown = _flame
		"lean_to":
			_hut.global_position = at
			_hut.rotation.y = yaw
			shown = _hut
			if fresh:
				_building = true
				_build_total = float(_catalog.get("recipes", {}).get("lean_to", {}).get("seconds", 4.0))
				_build_left = _build_total
				_hut_stage = 1
				_show_hut(1)
		"storage":
			if _storage == null:
				_storage = Node3D.new()
				_storage.name = "Storage"
				add_child(_storage)
				var chest := Art.put(_storage, Art.CHEST, "Chest", Vector3.ZERO, Vector3.ZERO, 1.0)
				Art.fit_height(chest, 0.75)
				var tag := _label3("Storage", 1.2)
				_prompt_style(tag, 1.0)
				_storage.add_child(tag)
			_storage.global_position = at
			_storage.rotation.y = yaw
			shown = _storage
	if not fresh:
		return
	_pop(shown)
	_chips(at + Vector3.UP * 0.2, Color(0.72, 0.62, 0.45), 26)
	_play(AUDIO + "build_place.ogg", -2.0, 1.0)
	_vibrate(45, 0.6)
	_popup("%s built!" % BUILD_TITLES.get(id, id), at + Vector3.UP * 1.2, Color(1.0, 0.9, 0.6))
	_note_burst(str(BUILD_TITLES.get(id, id)))
	if id == "campfire" and _step == "fire":
		_enter("cook")


# --- the pet ---------------------------------------------------------------

func _bond_level(bond: int = -1) -> int:
	if bond < 0:
		bond = int(_pet_stats.get("bond", 0))
	var level := 1
	for k in BOND_STEPS.size():
		if bond >= int(BOND_STEPS[k]):
			level = k + 1
	return level


## Bond levels each teach Tide-Puck something real: Lv2 fetches wood, fibre
## and berries; Lv3 sniffs more often and digs up double.
func _bond(amount: int) -> void:
	var before := _bond_level()
	_pet_stats["bond"] = int(_pet_stats.get("bond", 0)) + amount
	var level := _bond_level()
	_pet_stats["level"] = level
	if level > before:
		var reward := str(BOND_REWARDS.get(level, ""))
		var name := str(_pet_stats.get("name", "Tide-Puck"))
		_note_burst("Bond Lv %d" % level)
		if reward != "":
			_show_hint("%s learned %s!" % [name, reward])
			_hint_t = 4.5
		_play(AUDIO + "bark.ogg", -6.0, 1.3)
		if _pet:
			_pet_hop = 0.6
			_popup("Bond Lv %d!" % level, _pet.global_position + Vector3.UP * 1.0, Color(1.0, 0.65, 0.75))
		if level >= 2:
			_fetch_left = minf(_fetch_left, 4.0)


func _feed_cooked_fish() -> void:
	_inv["cooked"] = int(_inv.get("cooked", 0)) - 1
	_pet_stats["hunger"] = 100
	_pet_stats["mood"] = mini(100, int(_pet_stats["mood"]) + 20)
	_play(AUDIO + "crunch.ogg", -4.0, 1.0)
	_popup("Bond +20", _pet.global_position + Vector3.UP * 0.9, Color(1.0, 0.72, 0.78))
	_bond(20)
	_vibrate(30, 0.5)
	_enter("shelter")


func _pet_busy_ok() -> bool:
	return _step in ["gather", "fire", "cook", "shelter", "collect", "epilogue"] and not _fork and not _qte


func _tick_pet(delta: float) -> void:
	_pet_pet_cd = maxf(_pet_pet_cd - delta, 0.0)
	_pet_hop = maxf(_pet_hop - delta, 0.0)
	var moving := false
	match _pet_mode:
		"follow":
			moving = _pet_follow(delta)
			if _pet_busy_ok():
				_sniff_left -= delta
				_fetch_left -= delta
				if _sniff_left <= 0.0:
					_start_sniff()
				elif _fetch_left <= 0.0 and _bond_level() >= 2:
					_start_fetch()
		"sniff":
			moving = not _pet_walk(_pet_goal, 4.6, delta, 0.35)
			if not moving:
				_pet_mode = "point"
				_pet_timer = 0.0
				_play(AUDIO + "bark.ogg", -6.0, 1.15)
				_show_hint("%s found something! Dig where he points" % str(_pet_stats.get("name", "Tide-Puck")))
				_hint_t = 4.0
				var dig := _nearest_dig()
				if not dig.is_empty():
					var mark := (dig.get("root") as Node3D).get_node_or_null("Mark") as Label3D
					if mark:
						mark.visible = true
		"point":
			_pet_timer += delta
			var dig := _nearest_dig()
			if dig.is_empty() or _pet_timer > 30.0:
				_pet_mode = "follow"
			else:
				_pet_face((dig.get("root") as Node3D).global_position)
		"fetch":
			if _pet_target.is_empty() or bool(_pet_target.get("depleted", false)):
				_pet_mode = "follow"
			else:
				moving = not _pet_walk((_pet_target.get("root") as Node3D).global_position, 5.0, delta, 1.2)
				if not moving:
					_shake(_pet_target.get("root"))
					_play(_hit_sound(str(_pet_target.get("kind", ""))), -12.0, 1.2)
					_pet_mode = "return"
		"return":
			moving = not _pet_walk(_player.global_position, 5.4, delta, 1.6)
			if not moving:
				_pet_fetches += 1
				_give(_pet_carry, 1, _pet.global_position + Vector3.UP * 0.3)
				_bond(1)
				_pet_hop = 0.45
				_pet_mode = "follow"
				_fetch_left = 22.0
		"warn":
			_pet_timer += delta
			if _beast and _beast.visible:
				_pet_face(_beast.global_position)
			if _pet_timer > 2.0:
				_pet_mode = "follow"
	_pet_animate(moving)


func _pet_follow(delta: float) -> bool:
	var back := _player.global_transform.basis.z * 1.5 + _player.global_transform.basis.x * 0.9
	var goal := _player.position + back
	if _pet.position.distance_to(goal) < 0.5:
		return false
	var far := _flat(_pet.position, _player.position)
	return not _pet_walk(goal, clampf(far * 1.2, 2.0, 6.5), delta, 0.3)


## Walk the pet toward `goal`; true once within `stop` metres.
func _pet_walk(goal: Vector3, speed: float, delta: float, stop: float) -> bool:
	var to := goal - _pet.position
	to.y = 0.0
	if to.length() <= stop:
		return true
	var step := to.normalized() * minf(speed * delta, to.length())
	var next := _pet.position + step
	next.y = _ground_y(next.x, next.z)
	_pet.position = next
	_pet_face(_pet.global_position + step)
	return false


func _pet_face(at: Vector3) -> void:
	at.y = _pet.global_position.y
	if _flat(at, _pet.global_position) > 0.05:
		_pet.look_at(at, Vector3.UP)


## Procedural life on the static seal model: waddle, breathing, hops,
## and a nose-up point at buried loot.
func _pet_animate(moving: bool) -> void:
	var body := _pet.get_node_or_null("Body") as Node3D
	if body == null:
		return
	var t := _age
	var lift := 0.0
	var roll := 0.0
	var pitch := 0.0
	var yaw := PI
	var breathe := 1.0
	if moving:
		lift = absf(sin(t * 11.0)) * 0.07
		roll = sin(t * 11.0) * 0.13
	elif _pet_mode == "point":
		pitch = -0.32 + sin(t * 3.0) * 0.04
		yaw = PI + sin(t * 13.0) * 0.1
		lift = absf(sin(t * 6.0)) * 0.03
	elif _pet_mode == "warn":
		pitch = 0.12
		roll = sin(t * 30.0) * 0.03
	else:
		breathe = 1.0 + sin(t * 2.3) * 0.025
		yaw = PI + sin(t * 0.6) * 0.25
	if _pet_hop > 0.0:
		lift += sin(clampf(_pet_hop / 0.5, 0.0, 1.0) * PI) * 0.32
	body.position.y = lift
	body.rotation = Vector3(pitch, yaw, roll)
	body.scale = Vector3(PET_SCALE, PET_SCALE * breathe, PET_SCALE)


func _start_sniff() -> void:
	_sniff_left = 14.0 if _bond_level() >= 3 else 24.0
	var old := _nearest_dig()
	if not old.is_empty():
		if _flat((old.get("root") as Node3D).global_position, _player.global_position) < 12.0:
			return
		# A spot left far behind: let it sink back into the sand.
		_nodes.erase(old)
		(old.get("root") as Node3D).queue_free()
	var spots: Array = []
	for ring in [3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 10.0]:
		for k in 24:
			var a := TAU * float(k) / 24.0
			var p: Vector3 = _player.global_position + Vector3(cos(a), 0, sin(a)) * ring
			p.y = _ground_y(p.x, p.z)
			if p.y < _water_y + 0.25 or p.y - _player.global_position.y > 2.2 or _slope_at(p.x, p.z, 0.6) > 0.55:
				continue
			var clear := true
			for node in _nodes:
				if _flat((node.get("root") as Node3D).global_position, p) < 1.6:
					clear = false
					break
			for row in _structures:
				if _flat(row.get("at", Vector3.ZERO), p) < 2.4:
					clear = false
			if clear:
				spots.append(p)
	var spot := Vector3(INF, INF, INF)
	if not spots.is_empty():
		spot = spots[randi() % spots.size()]
	if not spot.is_finite():
		_sniff_left = 5.0
		return
	_spawn_dig(spot)
	_pet_goal = spot + (_player.global_position - spot).normalized() * 0.7
	_pet_mode = "sniff"
	_sniff_t = 1.5


func _dig_loot() -> Array:
	var want := ""
	if _step == "gather":
		want = "wood" if int(_inv.get("wood", 0)) < GATHER_WOOD else ("stone" if int(_inv.get("stone", 0)) < GATHER_STONE else "")
	elif _step == "fire":
		for key in ["stone", "wood"]:
			if int(_inv.get(key, 0)) < int(_catalog.get("recipes", {}).get("campfire", {}).get(key, 0)):
				want = key
				break
	elif _step == "cook" and _fish_cooked + int(_inv.get("fish", 0)) < COOK_FISH:
		want = "fish"
	elif _step == "shelter":
		for key in ["planks", "fibre", "rope", "wood"]:
			var need := int(_catalog.get("recipes", {}).get("lean_to", {}).get(key, 0))
			if int(_inv.get(key, 0)) < need:
				want = key
				break
	var loot: Array = []
	if want != "":
		loot.append({"id": want, "amount": 1 if want == "fish" else 2})
	else:
		var pick: String = ["food", "rope", "flint"][_dig_serial % 3]
		loot.append({"id": pick, "amount": 2 if pick == "food" else 1})
	if randf() < 0.35:
		loot.append({"id": "food", "amount": 1})
	if _bond_level() >= 3:
		for item in loot:
			item["amount"] = int(item["amount"]) * 2
	return loot


func _spawn_dig(at: Vector3) -> void:
	_dig_serial += 1
	var root := Node3D.new()
	root.name = "dig_%d" % _dig_serial
	_nodes_root.add_child(root)
	root.global_position = at
	var mound := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.42
	dome.height = 0.26
	dome.radial_segments = 18
	dome.rings = 6
	mound.mesh = dome
	mound.material_override = _mat(Color(0.6, 0.5, 0.34), 0.95)
	mound.position.y = 0.02
	root.add_child(mound)
	var stone := Art.put(root, ASHORE_STONE, "Pebble", Vector3(0.22, 0.05, 0.1), Vector3(0, 30, 0), 1.0)
	_fit_long(stone, 0.18)
	var title := _label3("Dig", 0.9)
	title.name = "Title"
	title.visible = false
	_prompt_style(title, 1.0)
	root.add_child(title)
	var mark := _label3("!", 1.35)
	mark.name = "Mark"
	mark.modulate = Color(1.0, 0.85, 0.3)
	mark.visible = false
	root.add_child(mark)
	var node := {
		"id": root.name, "kind": "dig", "title": "Dig", "scale": 1.0, "stages": 1, "stage": 0,
		"tool": "", "requires": "", "respawn": -1.0, "left": 0.0, "depleted": false,
		"loot": [_dig_loot()], "root": root,
	}
	_measure_node(node)
	node["radius"] = 1.1
	_nodes.append(node)


func _on_dug(_node: Dictionary) -> void:
	_pet_finds += 1
	_bond(3)
	_pet_hop = 0.5
	if _pet_mode == "point":
		_pet_mode = "follow"
	if _pet:
		_popup("Good find!", _pet.global_position + Vector3.UP * 0.9, Color(1.0, 0.8, 0.5))


func _nearest_dig() -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for node in _nodes:
		if str(node.get("kind", "")) != "dig" or bool(node.get("depleted", false)):
			continue
		var d := _flat((node.get("root") as Node3D).global_position, _player.global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


func _start_fetch() -> void:
	_fetch_left = 30.0
	var best: Dictionary = {}
	var best_d := 14.0
	for node in _nodes:
		if bool(node.get("depleted", false)) or str(node.get("kind", "")) not in ["tree", "drift", "bush", "fibre"]:
			continue
		var d := _flat((node.get("root") as Node3D).global_position, _pet.global_position)
		if d < best_d:
			best_d = d
			best = node
	if best.is_empty():
		return
	var kind := str(best.get("kind", ""))
	_pet_carry = "food" if kind == "bush" else ("fibre" if kind == "fibre" else "wood")
	_pet_target = best
	_pet_mode = "fetch"


## Closest standing node that still yields something the current goal needs.
func _needed_node() -> Dictionary:
	var want: Array = []
	if _step == "gather":
		if int(_inv.get("wood", 0)) < GATHER_WOOD:
			want.append("wood")
		if int(_inv.get("stone", 0)) < GATHER_STONE:
			want.append("stone")
	elif _step == "cook":
		if _fish_cooked + int(_inv.get("fish", 0)) < COOK_FISH:
			want.append("fish")
	elif _step in ["fire", "shelter"]:
		var recipe: Dictionary = _catalog.get("recipes", {}).get("campfire" if _step == "fire" else "lean_to", {})
		for key in recipe.keys():
			if str(key) != "seconds" and int(_inv.get(key, 0)) < int(recipe[key]):
				want.append(str(key))
	if want.is_empty():
		return {}
	var best: Dictionary = {}
	var best_d := INF
	for node in _nodes:
		if bool(node.get("depleted", false)) or str(node.get("kind", "")) == "pile":
			continue
		var gives := false
		for stage in node.get("loot", []):
			if stage is Array:
				for item in stage:
					if str(item.get("id", "")) in want:
						gives = true
		if not gives:
			continue
		var d := _flat((node.get("root") as Node3D).global_position, _player.global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


func _dusk_spawn() -> Vector3:
	var p := _player.global_position
	for i in 24:
		var a := TAU * float(i) / 24.0
		var at := p + Vector3(cos(a), 0, sin(a)) * 11.0
		at.y = _ground_y(at.x, at.z)
		if at.y > _water_y + 0.4 and absf(at.y - p.y) < 2.0 and _slope_at(at.x, at.z, 0.8) < 0.6:
			return at
	var camp := _landmark_position("camp")
	camp.y = _ground_y(camp.x, camp.z)
	return camp


## Bot / auto-play hint: which HUD button the next goal needs, if any.
func bot_goal() -> Dictionary:
	if _placing != "":
		if _ghost_ok:
			return {"press": "_place_btn"}
		if not _ghost_pin.is_finite():
			_ghost_pin = _build_spot()
		return {}
	if _building:
		return {}
	var want := ""
	if _step == "fire" and not _fire_lit and _can_pay("campfire"):
		want = "campfire"
	elif _step == "shelter" and _hut_stage == 0 and _can_pay("lean_to"):
		want = "lean_to"
	if want == "":
		return {}
	if not _build_open:
		return {"press": "_build_btn"}
	return {"press": "_build_" + want}


# --- camera vs foliage -----------------------------------------------------

## Foliage volumes the follow camera must not look through (palm trunks and
## crowns split so a crown does not block the open sand under it), plus a
## near-camera dither fade on foliage materials so leaves that still brush
## the lens dissolve instead of filling the frame.
func _prepare_foliage() -> void:
	_foliage_boxes.clear()
	_foliage_mats.clear()
	_foliage_links.clear()
	_fade_mats.clear()
	if _slice:
		for mmi in _slice.find_children("*", "MultiMeshInstance3D", true, false):
			var n := str(mmi.name)
			var hit := false
			for word in FOLIAGE_WORDS:
				if word in n:
					hit = true
			if not hit:
				continue
			var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var mats := _dither(mm.mesh)
			var local := mm.mesh.get_aabb()
			for i in mm.instance_count:
				var box: AABB = ((mmi as Node3D).global_transform * mm.get_instance_transform(i)) * local
				_add_foliage_box(box, "Palm" in n, mats)
	for mi in find_children("*", "MeshInstance3D", true, false):
		var path := str(get_path_to(mi)).to_lower()
		if path.begins_with("buildghost"):
			continue
		if not ("tree" in path or "palm" in path or "jungle" in path or "canopy" in path or "bush" in path):
			continue
		if "dead_tree_trunk" in path:
			continue
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var mats := _dither(m.mesh)
		for extra in [m.material_override] + range(m.get_surface_override_material_count()).map(func(i): return m.get_surface_override_material(i)):
			if extra is StandardMaterial3D:
				mats.append_array(_dither_mat(extra))
		var box: AABB = m.global_transform * m.get_aabb()
		# Gatherable trees and bushes come and go (respawn), so they keep a
		# link to their mesh and only count while it is visible.
		var link: Node3D = m if path.begins_with("nodes") else null
		_add_foliage_box(box, box.size.y > 2.6, mats, link)


func _add_foliage_box(box: AABB, tree: bool, mats: Array = [], link: Node3D = null) -> void:
	if box.size.y < 1.1:
		return
	if not tree:
		_foliage_boxes.append(box.grow(-0.12))
		_foliage_mats.append(mats)
		_foliage_links.append(link)
		return
	var c := box.position + box.size * 0.5
	# Palm fronds droop well below the crown, so the crown volume starts at
	# 45% of the height and keeps its full spread.
	var trunk_h := box.size.y * (0.35 if link else 0.45)
	_foliage_boxes.append(AABB(Vector3(c.x - 0.35, box.position.y, c.z - 0.35), Vector3(0.7, trunk_h, 0.7)))
	_foliage_mats.append(mats)
	_foliage_links.append(link)
	_foliage_boxes.append(AABB(Vector3(box.position.x, box.position.y + trunk_h, box.position.z), Vector3(box.size.x, box.size.y - trunk_h, box.size.z)))
	_foliage_mats.append(mats)
	_foliage_links.append(link)


## Near-lens dither on every foliage material; returns the materials so the
## canopy fade can widen the dither on whatever blocks the castaway.
func _dither(mesh: Mesh) -> Array:
	var out: Array = []
	for i in mesh.get_surface_count():
		out.append_array(_dither_mat(mesh.surface_get_material(i)))
	return out


func _dither_mat(mat: Material) -> Array:
	if not (mat is StandardMaterial3D):
		return []
	var std := mat as StandardMaterial3D
	if not std.has_meta("iom_dither"):
		std.set_meta("iom_dither", true)
		std.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		std.distance_fade_min_distance = NEAR_FADE_MIN
		std.distance_fade_max_distance = NEAR_FADE_MAX
	if not _fade_mats.has(std):
		_fade_mats.append(std)
	return [std]


func _foliage_live(i: int) -> bool:
	var link = _foliage_links[i] if i < _foliage_links.size() else null
	return link == null or not is_instance_valid(link) or (link as Node3D).is_visible_in_tree()


func _foliage_inside(p: Vector3) -> bool:
	for i in _foliage_boxes.size():
		var b: AABB = _foliage_boxes[i]
		if b.has_point(p) and _foliage_live(i):
			return true
	return false


## Look for a clear line to the castaway: the current yaw, then small swings
## either side, then a higher lift that looks over the shrubs. The camera
## eases toward the first clear option; no option means pull-in only.
func _probe_clear_view(head: Vector3) -> void:
	if _intro_k > 0.0 or _foliage_boxes.is_empty():
		_cam_yaw_goal = 0.0
		_cam_lift_goal = 0.0
		return
	for off in [0.0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9, 1.25, -1.25, 1.6, -1.6]:
		for lift in [0.0, -1.5, 1.6, 3.0]:
			if _cam_orbit_hold > 0.0 and absf(off) > 0.0:
				continue
			var back := Basis(Vector3.UP, _cam_yaw + off).z
			var eye: Vector3 = _player.global_position + back * FOLLOW_BACK + Vector3.UP * (FOLLOW_UP + lift)
			if _ground_y(eye.x, eye.z) > _player.global_position.y + 1.1:
				continue
			if _foliage_inside(eye) or _foliage_hit(head, eye) < 1.0:
				continue
			_cam_yaw_goal = off
			_cam_lift_goal = lift
			return
	_cam_yaw_goal = 0.0
	_cam_lift_goal = 1.6


## Canopy fade: foliage that still sits between the lens and the castaway
## gets its pixel dither widened out to just short of the player, so the
## leaves dissolve instead of hiding them. Eases back when clear.
func _fade_occluders(eye: Vector3, head: Vector3, delta: float) -> void:
	_occluding.clear()
	var reach := eye.distance_to(head) - 0.9
	for i in _foliage_boxes.size():
		var b: AABB = _foliage_boxes[i]
		var c := b.position + b.size * 0.5
		if absf(c.x - head.x) > 14.0 or absf(c.z - head.z) > 14.0 or not _foliage_live(i):
			continue
		if b.has_point(eye) or b.has_point(head) or b.intersects_segment(eye, head) != null:
			for m in _foliage_mats[i]:
				_occluding[m] = true
	var k := 1.0 - exp(-delta * 6.0)
	for m in _fade_mats:
		var std := m as StandardMaterial3D
		var goal := maxf(reach, NEAR_FADE_MAX) if _occluding.has(std) else NEAR_FADE_MAX
		std.distance_fade_max_distance = lerpf(std.distance_fade_max_distance, goal, k)
		std.distance_fade_min_distance = minf(NEAR_FADE_MIN + (std.distance_fade_max_distance - NEAR_FADE_MAX) * 0.8, std.distance_fade_max_distance - 0.6)


## How far from the lens a foliage material dissolves right now (the canopy
## fade widens this while the material blocks the castaway).
func foliage_fade_reach(mat: Material) -> float:
	if mat is StandardMaterial3D and (mat as StandardMaterial3D).has_meta("iom_dither"):
		return (mat as StandardMaterial3D).distance_fade_max_distance
	return 0.0


## Fraction along head->eye of the first foliage hit (1.0 = clear).
func _foliage_hit(head: Vector3, eye: Vector3) -> float:
	var best := 1.0
	var length := head.distance_to(eye)
	if length < 0.01:
		return 1.0
	for i in _foliage_boxes.size():
		var b: AABB = _foliage_boxes[i]
		var c := b.position + b.size * 0.5
		if absf(c.x - head.x) > 14.0 or absf(c.z - head.z) > 14.0:
			continue
		if b.has_point(head) or not _foliage_live(i):
			continue
		var hit = b.intersects_segment(head, eye)
		if hit != null:
			best = minf(best, head.distance_to(hit) / length)
	return best
