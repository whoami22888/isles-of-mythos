extends Node3D
## Client-only opening battle. No server calls. After it ends, boot's
## authenticated session is handed to the existing gameplay scene.

const SHIP_SCENE := "res://assets/external/polyhaven/dutch_ship_medium/dutch_ship_medium_1k.gltf"
const SAIL_ALBEDO := "res://assets/external/polyhaven/dutch_ship_medium/textures/dutch_ship_medium_sails_rgba_1k.png"
const SAIL_NORMAL := "res://assets/external/polyhaven/dutch_ship_medium/textures/dutch_ship_medium_sails_nor_gl_1k.jpg"
const SAIL_ARM := "res://assets/external/polyhaven/dutch_ship_medium/textures/dutch_ship_medium_sails_arm_1k.jpg"
const SAND_ALBEDO := "res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_diff_1k.jpg"
const SAND_NORMAL := "res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_nor_gl_1k.jpg"
const SAND_ROUGH := "res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_rough_1k.jpg"
const CLIFF_SCENE := "res://assets/external/polyhaven/coastal_cliff_01/coastal_cliff_01_1k.gltf"
const CLIFF_ALBEDO := "res://assets/external/polyhaven/coastal_cliff_01/textures/coastal_cliff_01_diff_1k.jpg"
const CLIFF_NORMAL := "res://assets/external/polyhaven/coastal_cliff_01/textures/coastal_cliff_01_nor_gl_1k.jpg"
const KENNEY := "res://assets/opening/kenney/"
const PALM_V2 := "res://assets/generated/palm_v2/palm_v2_mobile.glb"
const DISPLAY_FONT := "res://assets/fonts/PirataOne-Regular.ttf"
const UI_FONT := "res://assets/fonts/IMFeENrm28P.ttf"
const FLAG_PATH := "user://opening_battle.cfg"

const AUDIO_CANNON := "res://assets/audio/cannon_boom.wav"
const AUDIO_SHANTY := "res://assets/audio/shanty_bed.ogg"
const AUDIO_BOOM := "res://assets/opening/audio/explosion.ogg"
const AUDIO_OCEAN := "res://assets/opening/audio/ocean.ogg"
const AUDIO_ROAR := "res://assets/opening/audio/roar.ogg"
const AUDIO_CHEER := "res://assets/opening/audio/cheer.ogg"
const AUDIO_SWING := "res://assets/opening/audio/swing.ogg"
const AUDIO_HIT := "res://assets/opening/audio/hit.ogg"

enum Beat { ESTABLISH, POWDER, BALL, TIMING, IMPACT, TARGET, VOLLEY, BOARDING, CHEER, DEFEAT, CALM, RISE, SMASH, ASHORE }

var _client: Node
var _endpoint := ""
var _token := ""
var _refresh := ""
var _beat := Beat.ESTABLISH
var _clock := 0.0
var _capture := false
var _finished := false
var _storm := 0.32
var _sun_rays := Vector3(0.46, -0.58, 0.34).normalized()
var _shake := 0.0
var _misses := 0
var _chose_mast := false
var _sail_speed := 1.15
var _glow: MeshInstance3D
var _glow_light: OmniLight3D
var _rock_point := Vector3(2.0, 0.2, -52.0)
var _snapped := false
var _player_hp := 5
var _player_iframes := 0.0
var _attack_cool := 0.0
var _dodge_cool := 0.0
var _stick := Vector2.ZERO
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _keys := Vector2.ZERO

var _water_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _player_ship: Node3D
var _enemy_ship: Node3D
var _camera: Camera3D
var _camera_ready := false
var _lock_camera := false
var _player: Node3D
var _player_idle: Node3D
var _player_run: Node3D
var _player_jump: Node3D
var _deck_center := Vector3.ZERO
var _deck_half := Vector2(4.0, 2.0)
var _cannon: Node3D
var _powder: Node3D
var _ball: Node3D
var _leviathan: Node3D
var _leviathan_rise := 0.0
var _white: ColorRect
var _prompt: Label
var _powder_button: Button
var _ball_button: Button
var _fire_button: Button
var _mast_button: Button
var _hull_button: Button
var _attack_button: Button
var _dodge_button: Button
var _skip_button: Button
var _stick_base: Control
var _hp: Label
var _ashore: Label
var _ring: Control
var _soft: Texture2D
var _display_font: Font
var _ui_font: Font
var _boarders: Array[Node3D] = []
var _crew: Array[Node3D] = []

func begin_authenticated_session(endpoint: String, token: String, refresh_token: String = "") -> void:
	_endpoint = endpoint
	_token = token
	_refresh = refresh_token

func _ready() -> void:
	var session := OpeningSession.new()
	session.name = "Session"
	session.configure(_endpoint, _token)
	_client = session
	add_child(_client)
	_display_font = _load_font(DISPLAY_FONT)
	_ui_font = _load_font(UI_FONT)
	_soft = load("res://assets/opening/soft_round.png")
	_build_environment()
	_build_water()
	_build_island()
	_player_ship = _build_galleon("PlayerGalleon", true)
	_enemy_ship = _build_galleon("NavyGalleon", false)
	_enemy_ship.position = Vector3(16.0, 0.0, -14.0)
	_place_crew()
	_build_leviathan()
	_camera = Camera3D.new()
	_camera.name = "DeckCamera"
	_camera.current = true
	_camera.fov = 52.0
	_camera.near = 0.15
	_camera.far = 500.0
	add_child(_camera)
	_build_ui()
	_play_bed()
	_update_camera(1.0)

func _process(delta: float) -> void:
	if _finished:
		return
	_clock += delta
	_storm = move_toward(_storm, 0.08 if _beat >= Beat.CHEER else 0.28, delta * 0.03)
	if _sky_mat:
		_sky_mat.set_shader_parameter("storm", _storm)
	if _water_mat:
		_water_mat.set_shader_parameter("storm", _storm)
		_water_mat.set_shader_parameter("ship_a", _ship_wake(_player_ship))
		_water_mat.set_shader_parameter("ship_b", _ship_wake(_enemy_ship))
	if _beat < Beat.DEFEAT:
		var step := Vector3(0.0, 0.0, -_sail_speed * delta)
		if _player_ship:
			_player_ship.position += step
		if _enemy_ship:
			_enemy_ship.position += step
	_shake = move_toward(_shake, 0.0, delta * 1.6)
	_update_camera(delta)
	_update_player(delta)
	_update_boarders(delta)
	_update_leviathan(delta)
	_update_beat(delta)

func _update_beat(delta: float) -> void:
	match _beat:
		Beat.ESTABLISH:
			if _clock > 7.5:
				_enter_powder()
		Beat.IMPACT:
			if _clock > 4.2:
				_enter_target()
		Beat.VOLLEY:
			if _clock > 4.6:
				_enter_boarding()
		Beat.CHEER:
			if _clock > 4.0:
				_enter_defeat()
		Beat.DEFEAT:
			_tick_defeat(delta)
			if _clock > 5.2:
				_enter_calm()
		Beat.CALM:
			_tick_calm(delta)
			if _clock > 3.6:
				_enter_rise()
		Beat.RISE:
			if _clock > 6.0:
				_enter_smash()
		Beat.SMASH:
			if _clock > 3.4:
				_enter_ashore()
		Beat.ASHORE:
			if _clock > 3.2 and not _capture:
				_finish_opening()

func _enter_powder() -> void:
	_beat = Beat.POWDER
	_clock = 0.0
	_say("Load the cannon")
	_show_buttons(_powder_button)

func _enter_ball() -> void:
	_beat = Beat.BALL
	_clock = 0.0
	_say("Now the ball")
	_powder_button.visible = false
	_show_buttons(_ball_button)
	_pulse(_ball)

func _enter_timing() -> void:
	_beat = Beat.TIMING
	_clock = 0.0
	_misses = 0
	_say("Fire as the spark meets the gold")
	_ball_button.visible = false
	_ring.visible = true
	_show_buttons(_fire_button)

func _enter_impact() -> void:
	_beat = Beat.IMPACT
	_clock = 0.0
	_hard_cut = true
	_ring.visible = false
	_fire_button.visible = false
	_say("Hit. She's smoking.")
	_fire_broadside(true)

func _enter_target() -> void:
	_beat = Beat.TARGET
	_clock = 0.0
	_say("Choose the target")
	_show_buttons(_mast_button, _hull_button)

func _enter_volley() -> void:
	_beat = Beat.VOLLEY
	_clock = 0.0
	_hard_cut = true
	_mast_button.visible = false
	_hull_button.visible = false
	_say("Mast in splinters." if _chose_mast else "Hull staved in.")
	_fire_broadside(false)

func _enter_boarding() -> void:
	_beat = Beat.BOARDING
	_clock = 0.0
	_hard_cut = true
	_say("They're swinging aboard. Fight.")
	var count := 2 if _chose_mast else 3
	var hp := 4 if _chose_mast else 3
	for i in count:
		_spawn_boarder(i, hp)
	_attack_button.visible = true
	_dodge_button.visible = true
	_stick_base.visible = true
	_hp.visible = true
	_refresh_hp()

func _enter_cheer() -> void:
	_beat = Beat.CHEER
	_clock = 0.0
	_hard_cut = true
	_attack_button.visible = false
	_dodge_button.visible = false
	_stick_base.visible = false
	_stick = Vector2.ZERO
	_say("The crew cheers")
	_play(AUDIO_CHEER, -6.0)
	_burst(_player.global_position + Vector3(0, 2.2, 0), Color(1.0, 0.86, 0.45), 18, Vector3(0, 1.2, 0), 3.0, 0.35, 1.2)

func _enter_defeat() -> void:
	_beat = Beat.DEFEAT
	_clock = 0.0
	_hard_cut = true
	_sail_speed = 0.0
	if _chose_mast:
		_say("Her mast is gone. She's drifting.")
		_break_enemy_mast()
	else:
		_say("She's taking on water.")
		_play(AUDIO_BOOM, -8.0)
		if _enemy_ship:
			_burst(_enemy_ship.global_position + Vector3(0, 0.2, 0), Color(0.7, 0.9, 1.0), 22, Vector3(0, -2, 0), 3.5, 0.4, 1.1)

func _enter_calm() -> void:
	_beat = Beat.CALM
	_clock = 0.0
	_hard_cut = true
	_say("")
	_hush_bed()
	_storm = 0.0
	if _sky_mat:
		_sky_mat.set_shader_parameter("storm", 0.0)
	if _water_mat:
		_water_mat.set_shader_parameter("storm", 0.0)
		_water_mat.set_shader_parameter("shallow_color", Color(0.18, 0.95, 0.82))
		_water_mat.set_shader_parameter("deep_color", Color(0.02, 0.28, 0.32))
	_ensure_glow()
	if _glow:
		_glow.visible = true
	if _glow_light:
		_glow_light.visible = true

func _enter_rise() -> void:
	_beat = Beat.RISE
	_clock = 0.0
	_hard_cut = true
	_say("")
	_sail_speed = 0.0
	if _water_mat:
		_water_mat.set_shader_parameter("shallow_color", Color(0.25, 1.0, 0.78))
		_water_mat.set_shader_parameter("deep_color", Color(0.02, 0.22, 0.28))
	_play(AUDIO_ROAR, -4.0)
	_shake = 0.85
	if _glow_light:
		_glow_light.light_energy = 3.4
	_dim_leviathan_eyes()

func _enter_smash() -> void:
	_beat = Beat.SMASH
	_clock = 0.0
	_hard_cut = true
	_play(AUDIO_BOOM, -2.0)
	_shake = 1.6
	_snap_ship(_player_ship, 1.0)
	_snap_ship(_enemy_ship, -1.0)
	if _player_ship:
		_burst(_player_ship.global_position + Vector3(0, 2, 0), Color(0.75, 0.9, 1.0), 36, Vector3(0, -3, 0), 8.0, 0.8, 1.6)
	if _enemy_ship:
		_burst(_enemy_ship.global_position + Vector3(0, 3, 0), Color(0.55, 0.4, 0.28), 28, Vector3(0, 2, 0), 7.0, 0.55, 1.5)
	if _leviathan:
		_burst(_leviathan.global_position + Vector3(0, 4, 0), Color(0.55, 0.75, 0.8, 0.85), 40, Vector3(0, 2.5, 0), 7.0, 0.7, 1.4)
	# Everything goes dark.
	if _white:
		_white.color = Color(0, 0, 0, 0)
		_white.visible = true
		var fade := create_tween()
		fade.tween_interval(1.15)
		fade.tween_property(_white, "color:a", 1.0, 0.85)

func _enter_ashore() -> void:
	_beat = Beat.ASHORE
	_clock = 0.0
	_say("")
	_prompt.visible = false
	if _white:
		_white.color = Color(0, 0, 0, 1)
		_white.visible = true
	if _ashore:
		_ashore.visible = true
		_ashore.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_interval(0.4)
		tween.tween_property(_ashore, "modulate:a", 1.0, 0.6)

func defeat_path() -> String:
	return "mast" if _chose_mast else "hull"

func _write_opening_outcome() -> void:
	var cfg := ConfigFile.new()
	cfg.load(FLAG_PATH)
	cfg.set_value("opening", "completed", true)
	cfg.set_value("opening", "defeat_path", defeat_path())
	cfg.save(FLAG_PATH)

func _finish_opening() -> void:
	if _finished or _capture:
		return
	_finished = true
	_write_opening_outcome()
	var packed = load("res://gameplay/ashore/washed_ashore.tscn")
	if packed == null:
		return
	var gameplay = packed.instantiate()
	gameplay.begin_authenticated_session(_endpoint, _token, _refresh)
	get_tree().root.add_child(gameplay)
	if gameplay.has_method("apply_opening_outcome"):
		gameplay.apply_opening_outcome(defeat_path())
	get_tree().current_scene = gameplay
	queue_free()

func _on_skip() -> void:
	_finish_opening()

func _on_powder() -> void:
	if _beat != Beat.POWDER:
		return
	_play(AUDIO_HIT, -8.0)
	_enter_ball()

func _on_ball() -> void:
	if _beat != Beat.BALL:
		return
	_play(AUDIO_HIT, -10.0)
	_enter_timing()

func _on_fire() -> void:
	if _beat != Beat.TIMING:
		return
	var ring := _ring as TimingRing
	var hit := ring != null and ring.in_zone()
	if not hit:
		_misses += 1
		_say("The shot fell short. Watch the gold.")
		_splash_miss()
		if _misses < 2:
			return
	_enter_impact()

func _on_mast() -> void:
	if _beat != Beat.TARGET:
		return
	_chose_mast = true
	_enter_volley()

func _on_hull() -> void:
	if _beat != Beat.TARGET:
		return
	_chose_mast = false
	_enter_volley()

func _on_attack() -> void:
	if _beat != Beat.BOARDING or _attack_cool > 0.0 or _player == null:
		return
	_attack_cool = 0.48
	_play(AUDIO_SWING, -4.0)
	_player.rotation.y = _player.rotation.y
	var lunge := _player.transform.basis.x * 0.45
	_player.position += lunge
	_clamp_player()
	for boarder in _boarders:
		if not is_instance_valid(boarder) or not boarder.visible:
			continue
		if _player.global_position.distance_to(boarder.global_position) < 1.7:
			boarder.set_meta("hp", int(boarder.get_meta("hp")) - 1)
			boarder.set_meta("stagger", 0.35)
			_play(AUDIO_HIT, -6.0)
			_burst(boarder.global_position + Vector3(0, 1.1, 0), Color(0.95, 0.82, 0.55), 8, Vector3(0, 0.4, 0), 2.4, 0.18, 0.4)
			_flash_actor(boarder)

func _on_dodge() -> void:
	if _beat != Beat.BOARDING or _dodge_cool > 0.0 or _player == null:
		return
	_dodge_cool = 0.85
	_player_iframes = 0.45
	_show_pose("jump")
	var away := Vector3(_stick.x, 0, _stick.y)
	if away.length() < 0.2:
		away = -_player.transform.basis.x
	_player.position += away.normalized() * 1.35
	_clamp_player()

func _fire_broadside(player_shot: bool) -> void:
	_play(AUDIO_CANNON, -1.5)
	_shake = 0.7 if player_shot else 0.45
	var from := _cannon.global_position if _cannon else _player_ship.global_position + Vector3(0, 4, 0)
	var target := _enemy_ship.global_position + Vector3(0, 4.5, 0) if player_shot else _player_ship.global_position + Vector3(0, 4.2, 0)
	_muzzle(from)
	_burst(from, Color(1.0, 0.78, 0.35), 16, Vector3(0, 0.6, 0), 4.0, 0.45, 0.35)
	_burst(from, Color(0.55, 0.55, 0.55, 0.8), 22, Vector3(0, 1.4, 0), 2.2, 1.1, 1.8)
	_burst(target, Color(0.45, 0.28, 0.14), 26, Vector3(0, 2.0, 0), 5.5, 0.4, 1.3)
	_burst(target + Vector3(0, -1.5, 0), Color(0.7, 0.9, 1.0), 18, Vector3(0, -1, 0), 3.0, 0.55, 0.9)
	_play(AUDIO_BOOM, -3.0)
	if not player_shot and _enemy_ship:
		var tween := create_tween()
		var listed := _enemy_ship.rotation_degrees.z + (-8.0 if _chose_mast else 6.0)
		tween.tween_property(_enemy_ship, "rotation_degrees:z", listed, 1.2)

func _splash_miss() -> void:
	if _enemy_ship == null:
		return
	var at := _enemy_ship.global_position + Vector3(4.0, 0.4, -6.0)
	_burst(at, Color(0.75, 0.95, 1.0), 20, Vector3(0, 2.5, 0), 4.0, 0.5, 0.8)
	_play(AUDIO_HIT, -8.0)

func _update_player(delta: float) -> void:
	_attack_cool = maxf(_attack_cool - delta, 0.0)
	_dodge_cool = maxf(_dodge_cool - delta, 0.0)
	_player_iframes = maxf(_player_iframes - delta, 0.0)
	if _beat != Beat.BOARDING or _player == null:
		_show_pose("idle")
		return
	var wish := Vector3(_keys.x + _stick.x, 0.0, _keys.y + _stick.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	if _dodge_cool > 0.55:
		_show_pose("jump")
	elif wish.length() > 0.15:
		_show_pose("run")
		_player.position += wish * 4.2 * delta
		_clamp_player()
		_player.rotation.y = lerp_angle(_player.rotation.y, atan2(-wish.x, -wish.z), 1.0 - exp(-10.0 * delta))
	else:
		_show_pose("idle")

func _clamp_player() -> void:
	_player.position.x = clampf(_player.position.x, _deck_center.x - _deck_half.x, _deck_center.x + _deck_half.x)
	_player.position.z = clampf(_player.position.z, _deck_center.z - _deck_half.y, _deck_center.z + _deck_half.y)
	_player.position.y = _deck_center.y

func _update_boarders(delta: float) -> void:
	if _beat != Beat.BOARDING or _player == null:
		return
	var alive := 0
	for boarder in _boarders:
		if not is_instance_valid(boarder) or not boarder.visible:
			continue
		var hp := int(boarder.get_meta("hp"))
		if hp <= 0:
			boarder.visible = false
			_burst(boarder.global_position, Color(0.9, 0.8, 0.6), 10, Vector3(0, 1, 0), 2.0, 0.25, 0.6)
			continue
		alive += 1
		var swing := float(boarder.get_meta("swing"))
		swing = maxf(swing - delta, 0.0)
		boarder.set_meta("swing", swing)
		if swing > 0.0:
			var from: Vector3 = boarder.get_meta("from")
			var to: Vector3 = boarder.get_meta("to")
			var t := 1.0 - swing / 1.35
			var arc := from.lerp(to, t) + Vector3(0, sin(t * PI) * 3.2, 0)
			boarder.global_position = arc
			continue
		var stagger := float(boarder.get_meta("stagger"))
		if stagger > 0.0:
			boarder.set_meta("stagger", stagger - delta)
			boarder.rotation.z = sin(stagger * 30.0) * 0.4
			continue
		boarder.rotation.z = 0.0
		var flat := _player.global_position
		flat.y = boarder.global_position.y
		var offset := flat - boarder.global_position
		if offset.length() > 1.35:
			boarder.global_position += offset.normalized() * 2.1 * delta
			boarder.global_position.y = _player.global_position.y
		else:
			var cool := float(boarder.get_meta("cool")) - delta
			if cool <= 0.0 and _player_iframes <= 0.0:
				_player_hp -= 1
				_refresh_hp()
				_shake = 0.35
				_play(AUDIO_HIT, -5.0)
				_flash_actor(_player)
				cool = 1.15
				if _player_hp <= 0:
					_player_hp = 5
					_player_iframes = 1.2
					_say("The crew pulls you up")
					_refresh_hp()
			boarder.set_meta("cool", cool)
	if alive == 0 and _clock > 1.2 and _boarders.size() > 0:
		_enter_cheer()

var _hard_cut := false

func _camera_shot() -> Array:
	# Automatic cinematic cuts driven by battle beats. Presentation only.
	var aft := _player_ship.global_transform.basis.x
	var side := _player_ship.global_transform.basis.z
	var deck := _player.global_position + Vector3(0, 1.6, 0)
	var enemy := (_enemy_ship.global_position + Vector3(0, 5.0, 0)) if _enemy_ship else deck + Vector3(12, 0, 0)
	var cannon_at := _cannon.global_position if _cannon else deck
	match _beat:
		Beat.ESTABLISH:
			return [_player_ship.global_position + aft * 26.0 + side * 16.0 + Vector3(0, 14.0, 0), (_player_ship.global_position + enemy) * 0.5 + Vector3(0, 5.5, 0)]
		Beat.POWDER, Beat.BALL, Beat.TIMING:
			return [cannon_at + aft * 1.8 + side * -1.3 + Vector3(0, 1.75, 0), cannon_at - aft * 3.2 + Vector3(0, 1.3, 0)]
		Beat.IMPACT, Beat.VOLLEY:
			return [enemy + Vector3(7.0, 3.2, 9.0), enemy + Vector3(0, 2.6, 0)]
		Beat.BOARDING:
			var fight := deck
			if _boarders.size() > 0 and is_instance_valid(_boarders[0]):
				fight = fight.lerp(_boarders[0].global_position, 0.5)
			return [fight + side * 5.6 + aft * 1.4 + Vector3(0, 2.5, 0), fight + Vector3(0, 1.15, 0)]
		Beat.CHEER:
			return [deck + aft * 3.2 + side * 2.2 + Vector3(0, 2.1, 0), deck]
		Beat.DEFEAT:
			if _chose_mast:
				var wreck := _enemy_ship.global_position if _enemy_ship else _rock_point
				return [wreck + Vector3(13.0, 6.5, 8.0), wreck + Vector3(0, 2.2, 0)]
			var sunk := _enemy_ship.global_position if _enemy_ship else enemy
			return [Vector3(sunk.x + 14.0, 7.2, sunk.z + 5.5), Vector3(sunk.x, 1.4, sunk.z)]
		Beat.CALM:
			var mid := (_player_ship.global_position + (_enemy_ship.global_position if _enemy_ship else _player_ship.global_position)) * 0.5
			return [mid + Vector3(-4.0, 20.0, 26.0), mid + Vector3(0, 0.2, 0)]
		Beat.RISE:
			var rise_focus := (_leviathan.global_position + Vector3(0, 9.0, 0)) if _leviathan else enemy
			return [_player.global_position + aft * 10.0 + side * 4.0 + Vector3(0, 7.0, 0), rise_focus]
		Beat.SMASH:
			var blow := _leviathan.global_position if _leviathan else _player_ship.global_position
			return [blow + Vector3(18.0, 7.0, 14.0), blow + Vector3(0, 5.0, 0)]
		_:
			return [_player.global_position + aft * 2.4 + side * 2.2 + Vector3(0, 1.85, 0), deck - aft * 4.0]


func _update_camera(_delta: float) -> void:
	if _camera == null or _player == null or _player_ship == null:
		return
	var shot: Array = _camera_shot()
	var wanted: Vector3 = shot[0]
	var focus: Vector3 = shot[1]
	if (not _camera_ready) or _hard_cut:
		_camera.global_position = wanted
		_camera_ready = true
		_hard_cut = false
	else:
		var rate := 0.22 if _beat == Beat.ESTABLISH else (0.10 if _beat >= Beat.RISE else 0.16)
		_camera.global_position = _camera.global_position.lerp(wanted, rate)
	if _shake > 0.01:
		var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.18
		_camera.global_position += jitter
	_camera.look_at(focus, Vector3.UP)

func _update_leviathan(delta: float) -> void:
	if _leviathan == null or _beat < Beat.RISE:
		return
	var target := 1.0 if _beat == Beat.RISE or _beat == Beat.SMASH else 0.7
	var rate := 0.55 if _beat == Beat.SMASH else 0.28
	_leviathan_rise = move_toward(_leviathan_rise, target, delta * rate)
	_leviathan.position.y = lerpf(-16.0, 6.5, _leviathan_rise)
	_leviathan.rotation.y += delta * (0.55 if _beat == Beat.SMASH else 0.12)

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "World"
	var env := Environment.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/opening_sky.gdshader")
	_sky_mat.set_shader_parameter("storm", _storm)
	_sky_mat.set_shader_parameter("sun_direction", -_sun_rays)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.08
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.24
	env.adjustment_contrast = 1.06
	env.adjustment_brightness = 1.03
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_strength = 0.7
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 0.95
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.72, 0.86, 0.95)
	env.fog_density = 0.001
	env.fog_sky_affect = 0.12
	env.fog_depth_begin = 70.0
	env.fog_depth_end = 340.0
	env.fog_depth_curve = 1.2
	env.tonemap_exposure = 0.98
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.basis = Basis.looking_at(_sun_rays, Vector3.UP)
	sun.light_color = Color(1.0, 0.9, 0.72)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0
	sun.shadow_bias = 0.08
	sun.light_angular_distance = 0.6
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.basis = Basis.looking_at(Vector3(-0.5, -0.35, -0.4), Vector3.UP)
	fill.light_color = Color(0.55, 0.75, 1.0)
	fill.light_energy = 0.28
	fill.shadow_enabled = false
	add_child(fill)

func _build_water() -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Ocean"
	var plane := PlaneMesh.new()
	plane.size = Vector2(560, 560)
	plane.subdivide_width = 80
	plane.subdivide_depth = 80
	mesh_node.mesh = plane
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/opening_water.gdshader")
	_water_mat.set_shader_parameter("sun_dir", -_sun_rays)
	_water_mat.set_shader_parameter("storm", _storm)
	mesh_node.material_override = _water_mat
	mesh_node.position = Vector3(0, 0, -40)
	add_child(mesh_node)

func _build_island() -> void:
	var island := Node3D.new()
	island.name = "Island"
	island.position = Vector3(-18, 0, -62)
	add_child(island)
	var sand := MeshInstance3D.new()
	var disc := PlaneMesh.new()
	disc.size = Vector2(78, 54)
	disc.subdivide_width = 8
	disc.subdivide_depth = 8
	sand.mesh = disc
	var ground := ShaderMaterial.new()
	ground.shader = load("res://shaders/opening_ground.gdshader")
	ground.set_shader_parameter("albedo_tex", load(SAND_ALBEDO))
	ground.set_shader_parameter("normal_tex", load(SAND_NORMAL))
	ground.set_shader_parameter("rough_tex", load(SAND_ROUGH))
	ground.set_shader_parameter("uv_scale", 10.0)
	sand.material_override = ground
	sand.position = Vector3(0, 0.55, 0)
	island.add_child(sand)
	_place_model(island, CLIFF_SCENE, "Cliff", Vector3(-6, 0.2, 8), Vector3(0, 0.4, 0), 1.05)
	_place_model(island, KENNEY + "tower-complete-small.glb", "Watchtower", Vector3(-2, 8.2, 6), Vector3.ZERO, 1.8)
	_place_model(island, PALM_V2, "PalmA", Vector3(10, 0.55, -6), Vector3(0, 0.6, 0), 1.7 * 3.71)
	_place_model(island, PALM_V2, "PalmB", Vector3(16, 0.55, 2), Vector3(0, 1.2, 0), 1.6 * 3.71)
	_place_model(island, PALM_V2, "PalmC", Vector3(-16, 0.55, -8), Vector3(0, 2.1, 0), 1.5 * 3.71)
	_place_model(island, KENNEY + "rocks-sand-a.glb", "Rocks", Vector3(20, 0.2, 10), Vector3(0, 0.2, 0), 1.4)
	_rock_point = island.to_global(Vector3(20, 0.2, 10))
	_place_model(island, KENNEY + "structure-platform-dock.glb", "Dock", Vector3(24, 0.1, -4), Vector3(0, 1.1, 0), 2.4)
	_place_model(island, KENNEY + "ship-pirate-large.glb", "BeachedHull", Vector3(8, 0.7, 12), Vector3(0.15, 2.4, 0.05), 1.15)
	var falls := MeshInstance3D.new()
	falls.name = "Waterfall"
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(6.5, 11.0)
	sheet.orientation = PlaneMesh.FACE_Z
	falls.mesh = sheet
	var fall_mat := ShaderMaterial.new()
	fall_mat.shader = load("res://shaders/opening_falls.gdshader")
	falls.material_override = fall_mat
	falls.position = Vector3(-4, 6.2, 2.5)
	island.add_child(falls)
	var cone := MeshInstance3D.new()
	cone.name = "Volcano"
	var shape := CylinderMesh.new()
	shape.top_radius = 1.6
	shape.bottom_radius = 14.0
	shape.height = 26.0
	shape.radial_segments = 24
	cone.mesh = shape
	var lava := ShaderMaterial.new()
	lava.shader = load("res://shaders/opening_lava.gdshader")
	lava.set_shader_parameter("rock_tex", load(CLIFF_ALBEDO))
	lava.set_shader_parameter("rock_normal", load(CLIFF_NORMAL))
	cone.material_override = lava
	cone.position = Vector3(-18, 13.0, 36)
	island.add_child(cone)

func _build_galleon(node_name: String, player_side: bool) -> Node3D:
	var ship := Node3D.new()
	ship.name = node_name
	ship.rotation.y = -PI * 0.5
	add_child(ship)
	var packed = load(SHIP_SCENE)
	if packed != null:
		var model = packed.instantiate()
		model.name = "Hull"
		ship.add_child(model)
		_dress_sails(model)
	var deck := _measure_deck(ship)
	_deck_center = deck["center"]
	if player_side:
		_deck_half = deck["half"]
	var cannon := _place_model(ship, KENNEY + "cannon.glb", "Cannon", _deck_center + Vector3(1.4, 0.0, 1.7), Vector3(0, PI * 0.5, 0), 0.72)
	var powder := _place_model(ship, KENNEY + "barrel.glb", "Powder", _deck_center + Vector3(-0.2, 0.0, 1.15), Vector3.ZERO, 0.62)
	var ball := _place_model(ship, KENNEY + "cannon-ball.glb", "Ball", _deck_center + Vector3(0.45, 0.15, 1.15), Vector3.ZERO, 0.55)
	if player_side:
		_cannon = cannon
		_powder = powder
		_ball = ball
	_place_model(ship, KENNEY + "barrel.glb", "Barrel", _deck_center + Vector3(2.2, 0.0, -1.15), Vector3(0, 0.4, 0), 0.58)
	_place_model(ship, KENNEY + "chest.glb", "Chest", _deck_center + Vector3(-2.4, 0.0, -0.9), Vector3(0, 0.8, 0), 0.55)
	_place_model(ship, KENNEY + "flag-pirate.glb" if player_side else KENNEY + "flag.glb", "Flag", _deck_center + Vector3(-3.4, 0.2, 0.0), Vector3.ZERO, 1.6)
	_dress_flags(ship)
	if player_side:
		_player = _make_actor(ship, "Captain", _deck_center + Vector3(2.4, 0.0, -0.15))
	return ship

func _place_crew() -> void:
	if _player_ship:
		var player_deck := _measure_deck(_player_ship)
		_deck_center = player_deck["center"]
		_deck_half = player_deck["half"]
		_crew.append(_make_actor(_player_ship, "CrewA", _deck_center + Vector3(1.8, 0.0, -0.8)))
		_crew.append(_make_actor(_player_ship, "CrewB", _deck_center + Vector3(-1.6, 0.0, 0.9)))
	if _enemy_ship:
		var navy_deck := _measure_deck(_enemy_ship)
		_crew.append(_make_actor(_enemy_ship, "Navy", navy_deck["center"] + Vector3(0.4, 0.0, 0.2)))

func _make_actor(parent: Node, actor_name: String, at: Vector3) -> Node3D:
	var actor := Node3D.new()
	actor.name = actor_name
	parent.add_child(actor)
	actor.position = at
	var rig := _instance_rig()
	if rig:
		rig.name = "Rig"
		actor.add_child(rig)
	_fit_actor(actor, 1.72)
	_paint_actor(actor, Color(1, 1, 1))
	if actor_name == "Captain":
		_add_blade(actor)
	return actor

func _instance_rig() -> Node3D:
	var packed = load(KENNEY + "characterMedium.fbx")
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
	_copy_longest_anim(library, KENNEY + "idle.fbx", "Idle")
	_copy_longest_anim(library, KENNEY + "run.fbx", "Run")
	_copy_longest_anim(library, KENNEY + "jump.fbx", "Jump")
	if player.has_animation("Idle"):
		player.play("Idle")
	return node

func _copy_longest_anim(library: AnimationLibrary, path: String, alias: String) -> void:
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

func _fit_actor(actor: Node3D, meters: float) -> void:
	var box := _merged_aabb(actor)
	if box.size.y < 0.05:
		return
	var deck_y := actor.global_position.y
	actor.scale = Vector3.ONE * (meters / box.size.y)
	var fitted := _merged_aabb(actor)
	actor.global_position.y += deck_y - fitted.position.y

func _paint_actor(actor: Node3D, tint: Color) -> void:
	var skin = load(KENNEY + "criminalMaleA.png")
	for mesh in _meshes(actor):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = skin
		mat.albedo_color = tint
		mat.roughness = 0.62
		mat.metallic = 0.0
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mesh.material_override = mat

func _add_blade(actor: Node3D) -> void:
	var blade := MeshInstance3D.new()
	blade.name = "Cutlass"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0.05, 0.85, 0.42)
	var hilt := Vector3(0.0, 0.95, 0.02)
	var edge := Vector3(0.08, 0.9, 0.22)
	st.set_color(Color(0.72, 0.76, 0.8))
	st.add_vertex(hilt)
	st.add_vertex(edge)
	st.add_vertex(tip)
	st.add_vertex(hilt)
	st.add_vertex(tip)
	st.add_vertex(edge + Vector3(-0.05, 0, 0.02))
	st.generate_normals()
	blade.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.82, 0.86)
	mat.metallic = 0.85
	mat.roughness = 0.28
	blade.material_override = mat
	blade.position = Vector3(0.15, 0.15, 0.05)
	actor.add_child(blade)

func _dress_sails(model: Node) -> void:
	var shader = load("res://shaders/opening_sail.gdshader")
	if shader == null:
		return
	for mesh in _meshes(model):
		if not ("sail" in mesh.name.to_lower()):
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("albedo_tex", load(SAIL_ALBEDO))
		mat.set_shader_parameter("normal_tex", load(SAIL_NORMAL))
		mat.set_shader_parameter("arm_tex", load(SAIL_ARM))
		mesh.material_override = mat

func _dress_flags(ship: Node) -> void:
	var shader = load("res://shaders/opening_cloth.gdshader")
	if shader == null:
		return
	for mesh in _meshes(ship):
		if not _under_named(mesh, "Flag"):
			continue
		var existing := mesh.get_active_material(0)
		var tex: Texture2D = null
		if existing is BaseMaterial3D:
			tex = (existing as BaseMaterial3D).albedo_texture
		if tex == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("albedo_tex", tex)
		mesh.set_surface_override_material(0, mat)

func _build_leviathan() -> void:
	_leviathan = Node3D.new()
	_leviathan.name = "Leviathan"
	_leviathan.position = Vector3(8, -16, -18)
	add_child(_leviathan)
	var body := MeshInstance3D.new()
	body.mesh = _serpent_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.015, 0.03, 0.045)
	mat.roughness = 0.42
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.18, 0.16)
	mat.emission_energy_multiplier = 0.55
	body.material_override = mat
	_leviathan.add_child(body)
	var arm := MeshInstance3D.new()
	arm.name = "Tentacle"
	arm.mesh = _serpent_mesh()
	arm.rotation_degrees = Vector3(18, 110, -25)
	arm.position = Vector3(-4.0, -2.0, 3.0)
	arm.scale = Vector3(1.35, 1.2, 1.35)
	var arm_mat := StandardMaterial3D.new()
	arm_mat.albedo_color = Color(0.01, 0.02, 0.03)
	arm_mat.roughness = 0.55
	arm_mat.emission_enabled = false
	arm.material_override = arm_mat
	_leviathan.add_child(arm)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.name = "Eye"
		var sphere := SphereMesh.new()
		sphere.radius = 0.22
		sphere.height = 0.44
		eye.mesh = sphere
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(0.04, 0.08, 0.07)
		glow.emission_enabled = true
		glow.emission = Color(0.08, 0.16, 0.12)
		glow.emission_energy_multiplier = 0.35
		eye.material_override = glow
		eye.position = Vector3(side * 0.55, 16.2, 1.1)
		_leviathan.add_child(eye)

func _serpent_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 26
	var segments := 14
	var frames: Array = []
	for i in rings:
		var t := float(i) / float(rings - 1)
		var center := Vector3(sin(t * TAU * 1.15) * 3.4, lerpf(0.0, 18.0, t), cos(t * TAU * 0.65) * 2.2)
		var radius := lerpf(2.6, 0.45, t)
		var tangent := Vector3(cos(t * TAU * 1.15), 18.0 / TAU, -sin(t * TAU * 0.65)).normalized()
		var side := tangent.cross(Vector3.UP).normalized()
		if side.length() < 0.2:
			side = Vector3.RIGHT
		var up := side.cross(tangent).normalized()
		var ring := PackedVector3Array()
		for s in segments:
			var a := TAU * float(s) / float(segments)
			ring.append(center + (side * cos(a) + up * sin(a)) * radius)
		frames.append(ring)
	for i in rings - 1:
		var a_ring: PackedVector3Array = frames[i]
		var b_ring: PackedVector3Array = frames[i + 1]
		for s in segments:
			var s2 := (s + 1) % segments
			st.add_vertex(a_ring[s])
			st.add_vertex(b_ring[s])
			st.add_vertex(a_ring[s2])
			st.add_vertex(a_ring[s2])
			st.add_vertex(b_ring[s])
			st.add_vertex(b_ring[s2])
	st.generate_normals()
	return st.commit()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Interface"
	add_child(layer)
	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_prompt.offset_left = -420
	_prompt.offset_top = 28
	_prompt.offset_right = 420
	_prompt.offset_bottom = 110
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(_prompt, 40, true)
	_prompt.text = "Hold the deck"
	layer.add_child(_prompt)
	_skip_button = _wood_button("Skip intro", "SkipIntro")
	_skip_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_button.offset_left = -210
	_skip_button.offset_top = 18
	_skip_button.offset_right = -16
	_skip_button.offset_bottom = 74
	_skip_button.pressed.connect(_on_skip)
	layer.add_child(_skip_button)
	_powder_button = _action_button("Powder", _on_powder)
	_ball_button = _action_button("Cannonball", _on_ball)
	_fire_button = _action_button("Fire", _on_fire)
	_mast_button = _action_button("Mast  ·  slow them", _on_mast)
	_hull_button = _action_button("Hull  ·  smash them", _on_hull)
	_attack_button = _action_button("Attack", _on_attack)
	_dodge_button = _action_button("Dodge", _on_dodge)
	_layout_actions()
	for button in [_powder_button, _ball_button, _fire_button, _mast_button, _hull_button, _attack_button, _dodge_button]:
		button.visible = false
		layer.add_child(button)
	_ring = TimingRing.new()
	_ring.name = "TimingRing"
	_ring.set_anchors_preset(Control.PRESET_CENTER)
	_ring.offset_left = -90
	_ring.offset_top = -40
	_ring.offset_right = 90
	_ring.offset_bottom = 140
	_ring.visible = false
	layer.add_child(_ring)
	_stick_base = Control.new()
	_stick_base.name = "Stick"
	_stick_base.visible = false
	_stick_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stick_base.offset_left = 28
	_stick_base.offset_top = -210
	_stick_base.offset_right = 188
	_stick_base.offset_bottom = -50
	_stick_base.draw.connect(_draw_stick)
	layer.add_child(_stick_base)
	_hp = Label.new()
	_hp.visible = false
	_hp.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hp.offset_left = 20
	_hp.offset_top = 18
	_hp.offset_right = 280
	_hp.offset_bottom = 70
	_style_label(_hp, 28, false)
	layer.add_child(_hp)
	_white = ColorRect.new()
	_white.color = Color(0, 0, 0, 0)
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white.visible = false
	layer.add_child(_white)
	_ashore = Label.new()
	_ashore.text = "Washed ashore..."
	_ashore.visible = false
	_ashore.set_anchors_preset(Control.PRESET_CENTER)
	_ashore.offset_left = -360
	_ashore.offset_top = -40
	_ashore.offset_right = 360
	_ashore.offset_bottom = 40
	_ashore.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_ashore, 54, true)
	layer.add_child(_ashore)

func _layout_actions() -> void:
	var wide := [_mast_button, _hull_button]
	_powder_button.offset_left = -150
	_powder_button.offset_right = 150
	_ball_button.offset_left = -170
	_ball_button.offset_right = 170
	_fire_button.offset_left = -130
	_fire_button.offset_right = 130
	_mast_button.offset_left = -430
	_mast_button.offset_right = -20
	_hull_button.offset_left = 20
	_hull_button.offset_right = 430
	_attack_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_attack_button.offset_left = -230
	_attack_button.offset_top = -200
	_attack_button.offset_right = -28
	_attack_button.offset_bottom = -120
	_dodge_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dodge_button.offset_left = -230
	_dodge_button.offset_top = -108
	_dodge_button.offset_right = -28
	_dodge_button.offset_bottom = -28
	for button in [_powder_button, _ball_button, _fire_button]:
		button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		button.offset_top = -120
		button.offset_bottom = -36
	for button in wide:
		button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		button.offset_top = -130
		button.offset_bottom = -36

func _wood_button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	if _ui_font:
		button.add_theme_font_override("font", _ui_font)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(0.98, 0.9, 0.7))
	var fill := Color(0.33, 0.16, 0.06)
	var edge := Color(0.9, 0.72, 0.32)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = fill.lightened(0.08) if state == "hover" else fill
		box.border_color = edge
		box.set_border_width_all(3 if state == "focus" else 2)
		box.set_corner_radius_all(8)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 8
		box.content_margin_bottom = 8
		button.add_theme_stylebox_override(state, box)
	return button

func _action_button(text: String, handler: Callable) -> Button:
	var button := _wood_button(text, text.split(" ")[0])
	button.add_theme_font_size_override("font_size", 30)
	button.custom_minimum_size = Vector2(180, 72)
	button.pressed.connect(handler)
	return button

func _style_label(label: Label, size: int, display: bool) -> void:
	var font := _display_font if display else _ui_font
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.75))
	label.add_theme_color_override("font_outline_color", Color(0.16, 0.06, 0.02))
	label.add_theme_constant_override("outline_size", 10)

func _say(text: String) -> void:
	if _prompt:
		_prompt.text = text
		_prompt.visible = not text.is_empty()

func _show_buttons(a: Button, b: Button = null) -> void:
	a.visible = true
	if b:
		b.visible = true

func _refresh_hp() -> void:
	if _hp:
		_hp.text = "Grit  %d" % _player_hp

func _draw_stick() -> void:
	if _stick_base == null:
		return
	var c := _stick_base.size * 0.5
	_stick_base.draw_circle(c, 62, Color(0.12, 0.06, 0.03, 0.45))
	_stick_base.draw_arc(c, 62, 0, TAU, 40, Color(0.9, 0.72, 0.32, 0.9), 3.0)
	_stick_base.draw_circle(c + _stick * 36.0, 24, Color(0.95, 0.82, 0.45, 0.95))

func _show_pose(which: String) -> void:
	if _player == null:
		return
	var player := _find_player(_player)
	if player == null:
		return
	var clip := "Idle"
	if which == "run":
		clip = "Run"
	elif which == "jump":
		clip = "Jump"
	if player.has_animation(clip) and player.current_animation != clip:
		player.play(clip)

func _play_bed() -> void:
	_loop_player("Ocean", AUDIO_OCEAN, -12.0)
	_loop_player("Shanty", AUDIO_SHANTY, -16.0)

func _loop_player(node_name: String, path: String, db: float) -> void:
	var stream := _looping(path)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = db
	player.autoplay = true
	add_child(player)

func _looping(path: String) -> AudioStream:
	var loaded = load(path)
	if loaded is AudioStreamOggVorbis:
		var loop := (loaded as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		if loop == null:
			return loaded
		loop.loop = true
		return loop
	if loaded is AudioStreamWAV:
		var loop := (loaded as AudioStreamWAV).duplicate() as AudioStreamWAV
		if loop == null:
			return loaded
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_begin = 0
		loop.loop_end = maxi(int(round(loop.get_length() * float(loop.mix_rate))), 1)
		return loop
	return null

func _play(path: String, db: float) -> void:
	var loaded = load(path)
	if not (loaded is AudioStream):
		return
	var player := AudioStreamPlayer.new()
	player.stream = loaded
	player.volume_db = db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _muzzle(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.global_position = at
	light.light_color = Color(1.0, 0.72, 0.32)
	light.light_energy = 8.0
	light.omni_range = 14.0
	light.shadow_enabled = false
	add_child(light)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.18)
	tween.finished.connect(light.queue_free)

func _burst(at: Vector3, color: Color, amount: int, gravity: Vector3, speed: float, size: float, life: float) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.amount = amount
	particles.lifetime = life
	particles.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	add_child(particles)
	particles.global_position = at
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35
	process.direction = Vector3(0, 1, 0)
	process.spread = 75.0
	process.initial_velocity_min = speed * 0.35
	process.initial_velocity_max = speed
	process.gravity = gravity
	process.scale_min = size * 0.35
	process.scale_max = size
	process.color = color
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _soft
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	particles.draw_pass_1 = quad
	particles.emitting = true
	get_tree().create_timer(life + 0.25).timeout.connect(particles.queue_free)

func _pitch_ship(ship: Node3D, degrees: float) -> void:
	if ship == null:
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ship, "rotation_degrees:z", degrees, 1.4)
	tween.tween_property(ship, "position:y", -2.4, 2.2)

func _pulse(node: Node3D) -> void:
	if node == null:
		return
	var tween := create_tween()
	tween.set_loops(3)
	tween.tween_property(node, "scale", node.scale * 1.12, 0.18)
	tween.tween_property(node, "scale", node.scale, 0.18)

func _flash_actor(actor: Node3D) -> void:
	for mesh in _meshes(actor):
		var mat := mesh.material_override
		if mat is StandardMaterial3D:
			var original: Color = (mat as StandardMaterial3D).albedo_color
			(mat as StandardMaterial3D).albedo_color = Color(1.0, 0.85, 0.55)
			var tween := create_tween()
			tween.tween_property(mat, "albedo_color", original, 0.25)

func _spawn_boarder(index: int, hp: int) -> void:
	if _enemy_ship == null or _player_ship == null or _player == null:
		return
	var boarder := _make_actor(_player_ship, "Boarder%d" % index, _deck_center)
	boarder.set_meta("hp", hp)
	boarder.set_meta("stagger", 0.0)
	boarder.set_meta("cool", 0.8 + float(index) * 0.3)
	boarder.set_meta("swing", 1.35)
	var from := _enemy_ship.global_position + Vector3(-2.0 + float(index) * 1.6, 5.0, 0.0)
	var to := _player.global_position + Vector3(-1.2 + float(index), 0.0, 1.4)
	boarder.set_meta("from", from)
	boarder.set_meta("to", to)
	boarder.global_position = from
	_paint_actor(boarder, Color(0.62, 0.72, 0.95))
	_boarders.append(boarder)

func _place_model(parent: Node, path: String, node_name: String, at: Vector3, rotation: Vector3, scale: float) -> Node3D:
	var packed = load(path)
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = at
	holder.rotation = rotation
	holder.scale = Vector3.ONE * scale
	parent.add_child(holder)
	if packed != null:
		var model = packed.instantiate()
		holder.add_child(model)
	return holder

func _measure_deck(ship: Node3D) -> Dictionary:
	var hull: MeshInstance3D = null
	for mesh in _meshes(ship):
		if "hull" in mesh.name.to_lower():
			hull = mesh
			break
	var box := _aabb_in(ship, hull) if hull else _merged_local_aabb(ship)
	var center := box.position + box.size * 0.5
	center.y = box.position.y + box.size.y * 0.52
	var half := Vector2(maxf(box.size.x * 0.28, 1.2), maxf(box.size.z * 0.32, 0.8))
	return {"center": center, "half": half}

func _aabb_in(space: Node3D, mesh: MeshInstance3D) -> AABB:
	var local := mesh.get_aabb()
	var xform := space.global_transform.affine_inverse() * mesh.global_transform
	var box := AABB()
	var first := true
	for i in 8:
		var corner := local.position
		if i & 1:
			corner.x += local.size.x
		if i & 2:
			corner.y += local.size.y
		if i & 4:
			corner.z += local.size.z
		var point: Vector3 = xform * corner
		if first:
			box = AABB(point, Vector3.ZERO)
			first = false
		else:
			box = box.expand(point)
	return box

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

func _merged_local_aabb(space: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in _meshes(space):
		var part := _aabb_in(space, mesh)
		if first:
			box = part
			first = false
		else:
			box = box.merge(part)
	return box

func _under_named(node: Node, expected: String) -> bool:
	var cursor := node
	while cursor:
		if expected.to_lower() in str(cursor.name).to_lower():
			return true
		cursor = cursor.get_parent()
	return false

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found

func _play_clip(node: Node) -> void:
	var player := _find_player(node)
	if player == null:
		return
	var list := player.get_animation_list()
	if list.size() > 0:
		player.play(list[0])

func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null

func _ship_wake(ship: Node3D) -> Vector4:
	if ship == null:
		return Vector4.ZERO
	var forward := -ship.global_transform.basis.z
	return Vector4(ship.global_position.x, ship.global_position.z, forward.x, forward.z)

func _load_font(path: String) -> Font:
	var loaded = load(path)
	if loaded is Font:
		return loaded
	return null

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x < 280.0 and event.position.y > get_viewport().get_visible_rect().size.y - 280.0 and _beat == Beat.BOARDING:
			_stick_id = event.index
			_stick_origin = event.position
		elif not event.pressed and event.index == _stick_id:
			_stick_id = -1
			_stick = Vector2.ZERO
			if _stick_base:
				_stick_base.queue_redraw()
		_try_prop_tap(event.position if event.pressed else Vector2(-1, -1))
	elif event is InputEventScreenDrag and event.index == _stick_id:
		_stick = (event.position - _stick_origin) / 78.0
		if _stick.length() > 1.0:
			_stick = _stick.normalized()
		if _stick_base:
			_stick_base.queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		_try_prop_tap(event.position)
	elif event is InputEventKey and not event.echo:
		var pressed: bool = event.pressed
		match event.keycode:
			KEY_A, KEY_LEFT:
				_keys.x = -1.0 if pressed else 0.0
			KEY_D, KEY_RIGHT:
				_keys.x = 1.0 if pressed else 0.0
			KEY_W, KEY_UP:
				_keys.y = -1.0 if pressed else 0.0
			KEY_S, KEY_DOWN:
				_keys.y = 1.0 if pressed else 0.0
			KEY_J, KEY_SPACE:
				if pressed:
					_on_attack()
			KEY_K, KEY_SHIFT:
				if pressed:
					_on_dodge()

func _try_prop_tap(screen: Vector2) -> void:
	if screen.x < 0.0 or _camera == null:
		return
	var from := _camera.project_ray_origin(screen)
	var to := from + _camera.project_ray_normal(screen) * 80.0
	var best: Node3D = null
	var best_d := 1.6
	for prop in [_powder, _ball, _cannon]:
		if prop == null:
			continue
		var d := _ray_point_distance(from, to, prop.global_position)
		if d < best_d:
			best_d = d
			best = prop
	if best == null:
		return
	if best == _powder:
		_on_powder()
	elif best == _ball:
		_on_ball()
	elif best == _cannon and _beat == Beat.TIMING:
		_on_fire()

func _ray_point_distance(from: Vector3, to: Vector3, point: Vector3) -> float:
	var dir := to - from
	var length := dir.length()
	if length < 0.001:
		return 999.0
	dir /= length
	var along := (point - from).dot(dir)
	if along < 0.0 or along > length:
		return 999.0
	return point.distance_to(from + dir * along)

func _clear_bursts() -> void:
	for child in get_children():
		if child is GPUParticles3D:
			child.queue_free()


func _restore_enemy_for_pose() -> void:
	_clear_bursts()
	if _enemy_ship == null:
		return
	_enemy_ship.rotation_degrees = Vector3.ZERO
	_enemy_ship.position.y = 0.0
	for mesh in _meshes(_enemy_ship):
		mesh.visible = true
	var stump := _enemy_ship.get_node_or_null("BrokenMast")
	if stump:
		stump.queue_free()


func capture_pose(which: String) -> void:
	_capture = true
	_sail_speed = 0.0
	if which == "broadside":
		_enter_impact()
		_clock = 0.4
	elif which == "mast_wreck":
		_chose_mast = true
		_restore_enemy_for_pose()
		_place_for_ending()
		_enter_defeat()
		_tick_defeat(2.2)
		_clock = 2.2
		_clear_bursts()
	elif which == "hull_sink":
		_chose_mast = false
		_restore_enemy_for_pose()
		_place_for_ending()
		_enter_defeat()
		_tick_defeat(0.85)
		_clock = 0.85
		_clear_bursts()
		if _enemy_ship:
			_burst(_enemy_ship.global_position + Vector3(0, 0.5, 0), Color(0.75, 0.92, 1.0, 0.7), 8, Vector3(0, 1.2, 0), 1.6, 0.2, 0.7)
	elif which == "calm":
		_chose_mast = false
		_restore_enemy_for_pose()
		_place_for_ending()
		if _enemy_ship:
			_enemy_ship.position.y = 0.0
			_enemy_ship.rotation_degrees.x = 0.0
			_enemy_ship.rotation_degrees.z = 0.0
		_enter_calm()
		_tick_calm(1.8)
		_clock = 1.8
		_clear_bursts()
	elif which == "leviathan":
		_place_for_ending()
		_beat = Beat.RISE
		_clock = 5.0
		_leviathan_rise = 0.92
		_storm = 0.05
		_say("")
		_dim_leviathan_eyes()
		if _leviathan:
			_leviathan.position.y = 5.5
		_enter_smash()
		_clock = 0.35
		if _white:
			_white.visible = false
	else:
		_enter_powder()
		_clock = 0.2
	_update_camera(1.0)


func _tick_defeat(delta: float) -> void:
	if _enemy_ship == null:
		return
	if _chose_mast:
		var to := _rock_point - _enemy_ship.global_position
		to.y = 0.0
		if to.length() > 1.2:
			_enemy_ship.global_position += to.normalized() * minf(delta * 7.5, to.length())
		_enemy_ship.rotation_degrees.z = move_toward(_enemy_ship.rotation_degrees.z, 22.0, delta * 10.0)
		_enemy_ship.rotation_degrees.x = move_toward(_enemy_ship.rotation_degrees.x, 8.0, delta * 6.0)
		_enemy_ship.position.y = move_toward(_enemy_ship.position.y, 0.35, delta * 1.2)
		if to.length() < 8.0 and int(_clock * 4.0) != int((_clock - delta) * 4.0):
			_burst(_enemy_ship.global_position + Vector3(0, 0.4, 0), Color(0.55, 0.45, 0.32), 10, Vector3(0, -1, 0), 2.2, 0.3, 0.6)
	else:
		_enemy_ship.position.y = move_toward(_enemy_ship.position.y, -7.5, delta * 2.1)
		_enemy_ship.rotation_degrees.z = move_toward(_enemy_ship.rotation_degrees.z, -28.0, delta * 8.0)
		_enemy_ship.rotation_degrees.x = move_toward(_enemy_ship.rotation_degrees.x, 12.0, delta * 5.0)
		if int(_clock * 3.0) != int((_clock - delta) * 3.0):
			_burst(_enemy_ship.global_position + Vector3(0, 0.6, 0), Color(0.7, 0.9, 1.0), 14, Vector3(0, 1.5, 0), 2.4, 0.28, 0.9)
			_burst(_enemy_ship.global_position + Vector3(0, -0.4, 0), Color(0.55, 0.8, 0.95, 0.7), 10, Vector3(0, 2.2, 0), 1.6, 0.18, 1.1)


func _tick_calm(delta: float) -> void:
	_ensure_glow()
	if _glow:
		var pulse := 0.45 + 0.55 * (0.5 + 0.5 * sin(_clock * 2.4))
		var mat := _glow.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 1.2 + pulse * 1.1
		_glow.position.y = 0.12
	if _glow_light:
		_glow_light.light_energy = 1.2 + 0.8 * (0.5 + 0.5 * sin(_clock * 2.4))


func _break_enemy_mast() -> void:
	if _enemy_ship == null:
		return
	for mesh in _meshes(_enemy_ship):
		var n := mesh.name.to_lower()
		if "sail" in n or "rigging" in n:
			mesh.visible = false
	var stump := MeshInstance3D.new()
	stump.name = "BrokenMast"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.22
	cyl.height = 2.4
	stump.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.14, 0.08)
	mat.roughness = 0.9
	stump.material_override = mat
	stump.position = _measure_deck(_enemy_ship)["center"] + Vector3(0, 1.1, 0)
	stump.rotation_degrees = Vector3(18, 0, 28)
	_enemy_ship.add_child(stump)
	_burst(_enemy_ship.global_position + Vector3(0, 6, 0), Color(0.75, 0.7, 0.62), 18, Vector3(0, -1, 0), 3.0, 0.35, 0.9)


func _ensure_glow() -> void:
	if _glow:
		return
	_glow = MeshInstance3D.new()
	_glow.name = "AbyssalGlow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(56, 56)
	_glow.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.08, 0.85, 0.72, 0.22)
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.9, 0.75)
	mat.emission_energy_multiplier = 1.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.render_priority = 1
	_glow.material_override = mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid := Vector3.ZERO
	if _player_ship and _enemy_ship:
		mid = (_player_ship.global_position + _enemy_ship.global_position) * 0.5
	elif _player_ship:
		mid = _player_ship.global_position
	_glow.position = Vector3(mid.x, 0.12, mid.z)
	add_child(_glow)
	_glow_light = OmniLight3D.new()
	_glow_light.name = "AbyssalLight"
	_glow_light.light_color = Color(0.25, 0.85, 0.8)
	_glow_light.light_energy = 2.4
	_glow_light.omni_range = 36.0
	_glow_light.shadow_enabled = false
	_glow_light.position = _glow.position + Vector3(0, 0.8, 0)
	add_child(_glow_light)


func _hush_bed() -> void:
	for name in ["Ocean", "Shanty"]:
		var player := get_node_or_null(name) as AudioStreamPlayer
		if player:
			var tween := create_tween()
			tween.tween_property(player, "volume_db", -48.0, 0.8)


func _dim_leviathan_eyes() -> void:
	if _leviathan == null:
		return
	for child in _leviathan.get_children():
		if child.name.begins_with("Eye") and child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
			if mat:
				mat.emission_energy_multiplier = 0.15
				mat.albedo_color = Color(0.02, 0.04, 0.03)


func _snap_ship(ship: Node3D, sign: float) -> void:
	if ship == null or _snapped and ship.has_meta("snapped"):
		return
	var hull := ship.get_node_or_null("Hull") as Node3D
	if hull == null:
		_pitch_ship(ship, 16.0 * sign)
		return
	var origin := hull.global_position
	var normal := ship.global_transform.basis.x.normalized()
	hull.visible = false
	for side in [-1.0, 1.0]:
		var half := hull.duplicate() as Node3D
		half.visible = true
		half.name = "HullHalf_%d" % int(side)
		ship.add_child(half)
		_apply_clip(half, origin, normal * side)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(half, "rotation_degrees:z", sign * side * 24.0, 0.95)
		tween.tween_property(half, "position:y", half.position.y - 1.6, 1.25)
		tween.tween_property(half, "position:x", half.position.x + side * 1.8, 1.1)
	ship.set_meta("snapped", true)
	_snapped = true


func _apply_clip(root: Node, origin: Vector3, normal: Vector3) -> void:
	var shader = load("res://shaders/opening_clip_half.gdshader")
	if shader == null:
		return
	for mesh in _meshes(root):
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("clip_origin", origin)
		mat.set_shader_parameter("clip_normal", normal)
		var existing := mesh.get_active_material(0)
		if existing is BaseMaterial3D and (existing as BaseMaterial3D).albedo_texture:
			mat.set_shader_parameter("albedo_tex", (existing as BaseMaterial3D).albedo_texture)
		mesh.material_override = mat


func _place_for_ending() -> void:
	_sail_speed = 0.0
	# Keep both ships in open water so defeat / calm / leviathan shots don't
	# plant the galleon on the island grass.
	if _chose_mast:
		if _player_ship:
			_player_ship.global_position = _rock_point + Vector3(-18.0, 0.0, 14.0)
		if _enemy_ship:
			_enemy_ship.global_position = _rock_point + Vector3(5.5, 0.15, 5.0)
	else:
		if _player_ship:
			_player_ship.global_position = Vector3(4.0, 0.0, -22.0)
		if _enemy_ship:
			_enemy_ship.global_position = Vector3(16.0, 0.0, -30.0)
	if _leviathan:
		var mid := Vector3(10.0, -16.0, -26.0)
		if _player_ship and _enemy_ship:
			mid = (_player_ship.global_position + _enemy_ship.global_position) * 0.5
			mid.y = -16.0
		_leviathan.position = mid
	if _glow:
		var mid2 := Vector3.ZERO
		if _player_ship and _enemy_ship:
			mid2 = (_player_ship.global_position + _enemy_ship.global_position) * 0.5
		_glow.position = Vector3(mid2.x, 0.12, mid2.z)
		if _glow_light:
			_glow_light.position = _glow.position + Vector3(0, 0.5, 0)


class OpeningSession extends Node:
	var _url := ""
	var _token := ""

	func configure(url: String, token: String) -> void:
		_url = url
		_token = token


class TimingRing extends Control:
	var angle := 0.2
	var zone := 0.9

	func _process(delta: float) -> void:
		angle = fposmod(angle + delta * 1.35, TAU)
		queue_redraw()

	func in_zone() -> bool:
		return absf(angle_difference(angle, zone)) < 0.32

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.38
		draw_arc(center, radius, 0.0, TAU, 72, Color(0.25, 0.12, 0.04, 0.85), 10.0, true)
		draw_arc(center, radius, zone - 0.32, zone + 0.32, 20, Color(0.98, 0.8, 0.28), 16.0, true)
		var spark := center + Vector2(cos(angle), sin(angle)) * radius
		draw_circle(spark, 13.0, Color(1.0, 0.95, 0.75))
