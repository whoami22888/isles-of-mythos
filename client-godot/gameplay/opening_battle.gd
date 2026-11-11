extends Node3D
## Client-only opening battle. No server calls. After it ends, boot's
## authenticated session is handed to the existing gameplay scene.
## The world is the approved realistic island (scenes/realistic_coastal_slice):
## its ocean_surface water, pass-11 lighting and sail setup are reused as-is,
## not restyled. The ending beats match the approved opening stills v2.

const Art := preload("res://gameplay/opening/opening_art.gd")
const SLICE_SCENE := preload("res://scenes/realistic_coastal_slice.tscn")
const SHIP_SCENE := preload("res://assets/external/polyhaven/dutch_ship_medium/dutch_ship_medium_1k.gltf")
const KENNEY := "res://assets/opening/kenney/"
const DISPLAY_FONT := "res://assets/fonts/PirataOne-Regular.ttf"
const UI_FONT := "res://assets/fonts/IMFeENrm28P.ttf"
const FLAG_PATH := "user://opening_battle.cfg"
## Battle start: open water south of the island, bows to -z (away from land).
const PLAYER_START := Vector3(4.0, -0.05, -34.0)
const ENEMY_OFFSET := Vector3(16.0, 0.0, -14.0)
## Approved stills v2 compositions (slice coordinates).
const MAST_WRECK := Vector3(40.0, -1.1, -8.0)
const MAST_WRECK_ROT := Vector3(22.0, -65.0, -5.0)
const HULL_SUNK := Vector3(30.0, -2.6, -6.0)
const HULL_SUNK_ROT := Vector3(-6.0, -90.0, -13.0)
const LEVIATHAN_AT := Vector3(8.0, -0.9, -16.0)
const CREW_SHIRTS := [Color(0.34, 0.13, 0.10), Color(0.17, 0.19, 0.22), Color(0.30, 0.27, 0.21)]
const NAVY_SHIRT := Color(0.07, 0.11, 0.24)

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
var _sun_rays := Vector3(0.46, -0.58, 0.34).normalized()
var _shake := 0.0
var _misses := 0
var _chose_mast := false
var _sail_speed := 1.15
var _glow: Node3D
var _player_hp := 5
var _player_iframes := 0.0
var _attack_cool := 0.0
var _dodge_cool := 0.0
var _stick := Vector2.ZERO
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _keys := Vector2.ZERO

var _water_mat: ShaderMaterial
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
var _slice: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _bounce: DirectionalLight3D
var _look := {}
var _water_y := -0.35
var _stage: Node3D
var _shot := []
var _wreck_halves: Array[Node3D] = []
var _head: Node3D
var _tentacle: Node3D

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
	_mount_world()
	_player_ship = _build_galleon("PlayerGalleon", true)
	_player_ship.position = PLAYER_START
	_enemy_ship = _build_galleon("NavyGalleon", false)
	_enemy_ship.position = PLAYER_START + ENEMY_OFFSET
	_place_crew()
	_build_leviathan()
	_camera = Camera3D.new()
	_camera.name = "DeckCamera"
	_camera.current = true
	_camera.fov = 52.0
	_camera.near = 0.15
	_camera.far = 600.0
	add_child(_camera)
	_camera.make_current()
	_set_wake(0.8)
	_build_ui()
	_play_bed()
	_update_camera(1.0)

func _process(delta: float) -> void:
	if _finished:
		return
	_clock += delta
	if _beat < Beat.DEFEAT:
		var step := Vector3(0.0, 0.0, -_sail_speed * delta)
		if _player_ship:
			_player_ship.position += step
		if _enemy_ship:
			_enemy_ship.position += step
		_sync_wake()
	_shake = move_toward(_shake, 0.0, delta * 1.6)
	_update_camera(delta)
	_follow_water()
	_update_player(delta)
	_update_boarders(delta)
	_update_leviathan(delta)
	_update_beat(delta)

func _update_beat(delta: float) -> void:
	if _capture:
		# Verification captures hold the posed beat; no automatic advance.
		return
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
	_clear_stage()
	_restore_look()
	if _chose_mast:
		_say("Her mast is gone. She's on the reef.")
		_stage_mast_wreck()
	else:
		_say("She's taking on water.")
		_play(AUDIO_BOOM, -8.0)
		_stage_hull_sink()

func _enter_calm() -> void:
	_beat = Beat.CALM
	_clock = 0.0
	_hard_cut = true
	_say("")
	_hush_bed()
	_clear_stage()
	_stage_two_ships(Vector3(-2.0, -0.05, -28.0), Vector3(22.0, -0.4, -22.0), Color(0.17, 0.19, 0.22), true)
	_set_wake(0.0)
	_darken(0.98, 0.6, 0.5, 0.6, Color(0.72, 0.8, 0.9))
	var mid := (_player_ship.global_position + _enemy_ship.global_position) * 0.5
	_glow = Art.calm_glow(_stage, mid, 1.1, 48.0, _water_y)
	_shot = [mid + Vector3(-4.0, 20.0, -26.0), mid + Vector3(0, 0.2, 0)]

func _enter_rise() -> void:
	_beat = Beat.RISE
	_clock = 0.0
	_hard_cut = true
	_say("")
	_sail_speed = 0.0
	_clear_stage()
	_stage_two_ships(Vector3(-4.0, -0.05, -24.0), Vector3(20.0, -0.4, -20.0), Color(0.72, 0.72, 0.7), false)
	_set_wake(0.0)
	_darken(1.0, 1.35, 0.55, 0.8, Color(0.9, 0.88, 0.82))
	_glow = Art.calm_glow(_stage, LEVIATHAN_AT, 0.5, 30.0, _water_y)
	_play(AUDIO_ROAR, -4.0)
	_shake = 0.85
	_leviathan_rise = 0.0
	if _leviathan:
		_leviathan.visible = true
		_leviathan.position = LEVIATHAN_AT + Vector3(0, -22.0, 0)
		_leviathan.rotation_degrees = Vector3.ZERO
	_foam_done = false
	var deck := _player_ship.global_position + Vector3(0, 3.2, 0)
	var aft := _player_ship.global_transform.basis.x
	var side := _player_ship.global_transform.basis.z
	_shot = [deck + aft * 22.0 + side * 12.0 + Vector3(0, 5.5, 0), LEVIATHAN_AT + Vector3(0, 8.0, 0)]

func _enter_smash() -> void:
	_beat = Beat.SMASH
	_clock = 0.0
	_play(AUDIO_BOOM, -2.0)
	_shake = 1.6
	if _leviathan:
		_leviathan_rise = 1.0
		_leviathan.position = LEVIATHAN_AT
		var lunge := create_tween()
		lunge.set_parallel(true)
		lunge.tween_property(_leviathan, "rotation_degrees:x", 28.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		lunge.tween_property(_leviathan, "position:y", LEVIATHAN_AT.y - 7.0, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_snap_ship(_player_ship, 1.0)
	_snap_ship(_enemy_ship, -1.0)
	var debris := _player_ship.global_position
	Art.put(_stage, Art.SNAPPED_MAST, "FloatingMast", Vector3(debris.x + 6.0, _water_y - 0.2, debris.z + 5.0), Vector3(0, 35, 3), 0.9)
	var sail := Art.put(_stage, Art.TORN_SAIL, "FloatingSail", Vector3(debris.x + 2.5, _water_y + 0.01, debris.z + 8.0), Vector3(0, 160, 0), 0.5)
	Art.tone(sail, Color(0.58, 0.54, 0.47))
	Art.spray(_stage, debris + Vector3(0, -0.2, 0), 10, 6.0, 2.4, 0.3, 3)
	Art.spray(_stage, _enemy_ship.global_position + Vector3(0, -0.2, 0), 8, 5.0, 2.2, 0.3, 5)
	_burst(debris + Vector3(0, 2, 0), Color(0.75, 0.9, 1.0), 36, Vector3(0, -3, 0), 8.0, 0.8, 1.6)
	_burst(_enemy_ship.global_position + Vector3(0, 3, 0), Color(0.55, 0.4, 0.28), 28, Vector3(0, 2, 0), 7.0, 0.55, 1.5)
	_burst(LEVIATHAN_AT + Vector3(0, 4, 0), Color(0.55, 0.75, 0.8, 0.85), 40, Vector3(0, 2.5, 0), 7.0, 0.7, 1.4)
	# Same framing as the rise, pulled back: the cut is the blow, not a new place.
	var deck := debris + Vector3(0, 3.2, 0)
	_shot = [deck + Vector3(0, 0, -26.0) + Vector3(14.0, 7.0, 0), LEVIATHAN_AT + Vector3(0, 5.0, 0)]
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
	_show_pose("attack")
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
		var rig := boarder.get_node_or_null("Rig")
		if offset.length() > 0.05:
			boarder.look_at(boarder.global_position + offset, Vector3.UP)
		if offset.length() > 1.35:
			boarder.global_position += offset.normalized() * 2.1 * delta
			boarder.global_position.y = _player.global_position.y
			Art.play(rig, "Run")
		else:
			var cool := float(boarder.get_meta("cool")) - delta
			if cool > 0.3:
				Art.play(rig, "SwordIdle")
			if cool <= 0.0 and _player_iframes <= 0.0:
				Art.play(rig, "Punch", 0.08, 1.3)
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
var _foam_done := false

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
			# Wide enough to read the enemy hull taking the hits (real-size galleon).
			return [enemy + Vector3(13.0, 0.8, 17.0), enemy + Vector3(0, -1.2, 0)]
		Beat.BOARDING:
			var fight := deck
			if _boarders.size() > 0 and is_instance_valid(_boarders[0]):
				fight = fight.lerp(_boarders[0].global_position, 0.5)
			return [fight + side * 5.6 + aft * 1.4 + Vector3(0, 2.5, 0), fight + Vector3(0, 1.15, 0)]
		Beat.CHEER:
			return [deck + aft * 3.2 + side * 2.2 + Vector3(0, 2.1, 0), deck]
		Beat.DEFEAT, Beat.CALM, Beat.RISE, Beat.SMASH:
			if _shot.size() == 2:
				return _shot
			return [deck + aft * 10.0 + Vector3(0, 6.0, 0), deck]
		_:
			return [_player.global_position + aft * 2.4 + side * 2.2 + Vector3(0, 1.85, 0), deck - aft * 4.0]


func _update_camera(_delta: float) -> void:
	if _camera == null or _player == null or _player_ship == null:
		return
	var shot: Array = _camera_shot()
	var wanted: Vector3 = shot[0]
	var focus: Vector3 = shot[1]
	if (not _camera_ready) or _hard_cut or _beat >= Beat.DEFEAT:
		# The ending beats are locked compositions (approved stills); they cut.
		_camera.global_position = wanted
		_camera_ready = true
		_hard_cut = false
	else:
		var rate := 0.22 if _beat == Beat.ESTABLISH else 0.16
		_camera.global_position = _camera.global_position.lerp(wanted, rate)
	_camera.fov = 52.0
	if _shake > 0.01:
		var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.18
		_camera.global_position += jitter
	_camera.look_at(focus, Vector3.UP)

func _update_leviathan(delta: float) -> void:
	if _leviathan == null or _beat != Beat.RISE:
		return
	# Rise from deep water to the approved pose in about three seconds.
	_leviathan_rise = move_toward(_leviathan_rise, 1.0, delta / 3.0)
	var eased := 1.0 - pow(1.0 - _leviathan_rise, 3.0)
	_leviathan.position = LEVIATHAN_AT + Vector3(0, lerpf(-22.0, 0.0, eased), 0)
	if not _foam_done and _leviathan_rise > 0.25:
		_foam_done = true
		Art.foam_ring(_stage, LEVIATHAN_AT + Vector3(0, 0, 2.0), 8.0, _water_y)
		Art.foam_ring(_stage, LEVIATHAN_AT + Vector3(-8.0, 0, -2.0), 3.0, _water_y)
		Art.spray(_stage, LEVIATHAN_AT + Vector3(0, 0.2, 2.0), 14, 7.0, 2.6, 0.3)

func _mount_world() -> void:
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
	var world := _slice.get_node_or_null("CoastalAtmosphere") as WorldEnvironment
	_env = world.environment if world else null
	_sun = _slice.get_node_or_null("WarmSun") as DirectionalLight3D
	_bounce = _slice.get_node_or_null("AquaBounce") as DirectionalLight3D
	var water := _slice.get_node_or_null("ShallowToDeepWater") as MeshInstance3D
	if water:
		_water_mat = water.material_override as ShaderMaterial
	if _slice.has_method("water_level"):
		_water_y = _slice.water_level()
	if _env and _sun:
		_look = {"exp": _env.tonemap_exposure, "amb": _env.ambient_light_energy, "bg": _env.background_energy_multiplier,
			"fog": _env.fog_light_color, "sat": _env.adjustment_saturation, "sun": _sun.light_energy, "sun_col": _sun.light_color}
	_stage = Node3D.new()
	_stage.name = "BeatStage"
	add_child(_stage)

## The bay's one ocean plane is 640 x 480 m around the island. The battle
## looks out to sea, so slide the plane under the camera (snapped to its
## vertex grid). The shader works in world XZ, so the look does not change.
func _follow_water() -> void:
	if _slice == null or _camera == null:
		return
	var water := _slice.get_node_or_null("ShallowToDeepWater") as Node3D
	if water == null:
		return
	var step := 640.0 / 96.0
	var ahead := -_camera.global_transform.basis.z
	ahead.y = 0.0
	var centre := _slice.to_local(_camera.global_position + ahead.normalized() * 110.0)
	water.position.x = snappedf(centre.x, step)
	water.position.z = snappedf(centre.z, step)

func _set_wake(strength: float, ship: Node3D = null) -> void:
	if _water_mat == null:
		return
	_water_mat.set_shader_parameter("wake_strength", strength)
	_sync_wake(ship)

## Same contract as realistic_coastal_slice.sync_ocean_vessel_uniforms, fed
## from the ship that is moving (the approved water look, untouched).
func _sync_wake(ship: Node3D = null) -> void:
	var vessel := ship if ship else _player_ship
	if _water_mat == null or vessel == null:
		return
	var forward := -vessel.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0, 0, -1)
	forward = forward.normalized()
	_water_mat.set_shader_parameter("vessel_xz", Vector2(vessel.global_position.x, vessel.global_position.z))
	_water_mat.set_shader_parameter("vessel_forward", Vector2(forward.x, forward.z))

func _darken(exposure: float, sun_energy: float, ambient: float, background: float, sun_color: Color) -> void:
	if _env == null or _sun == null:
		return
	_env.tonemap_exposure = exposure
	_env.ambient_light_energy = ambient
	_env.background_energy_multiplier = background
	_env.fog_light_color = Color(0.30, 0.38, 0.44)
	_env.adjustment_saturation = 0.72
	_sun.light_energy = sun_energy
	_sun.light_color = sun_color
	if _bounce:
		_bounce.visible = false

func _restore_look() -> void:
	if _env == null or _sun == null or _look.is_empty():
		return
	_env.tonemap_exposure = _look["exp"]
	_env.ambient_light_energy = _look["amb"]
	_env.background_energy_multiplier = _look["bg"]
	_env.fog_light_color = _look["fog"]
	_env.adjustment_saturation = _look["sat"]
	_sun.light_energy = _look["sun"]
	_sun.light_color = _look["sun_col"]
	if _bounce:
		_bounce.visible = true

func _clear_stage() -> void:
	_clear_bursts()
	_glow = null
	if _stage:
		for child in _stage.get_children():
			child.queue_free()

func _build_galleon(node_name: String, player_side: bool) -> Node3D:
	var ship := Node3D.new()
	ship.name = node_name
	ship.rotation.y = -PI * 0.5
	add_child(ship)
	var model := SHIP_SCENE.instantiate() as Node3D
	model.name = "Hull"
	ship.add_child(model)
	_slice._configure_ship_sails(model)
	ship.set_meta("sails", _sail_overrides(model))
	var deck := _measure_deck(ship)
	_deck_center = deck["center"]
	if player_side:
		_deck_half = deck["half"]
	var cannon := _deck_prop(ship, Art.CANNON, "Cannon", _deck_center + Vector3(1.4, 0.0, 1.7), Vector3(0, 0, 0), 0.62)
	var powder := _deck_prop(ship, Art.WINE_BARREL, "Powder", _deck_center + Vector3(-0.2, 0.0, 1.15), Vector3.ZERO, 0.72)
	var ball := _cannonball(ship, _deck_center + Vector3(0.45, 0.0, 1.15))
	if player_side:
		_cannon = cannon
		_powder = powder
		_ball = ball
	_deck_prop(ship, Art.WINE_BARREL, "Barrel", _deck_center + Vector3(2.2, 0.0, -1.15), Vector3(0, 23, 0), 0.68)
	_deck_prop(ship, Art.CRATE_B, "Crate", _deck_center + Vector3(-2.4, 0.0, -0.9), Vector3(0, 46, 0), 0.5)
	_deck_prop(ship, Art.ROPE, "Rope", _deck_center + Vector3(-1.0, 0.0, -1.2), Vector3(0, 10, 0), 0.22)
	if player_side:
		_player = _make_actor(ship, "Captain", _deck_center + Vector3(2.4, 0.0, -0.15))
	return ship

## Remember the sail override materials so beats can tint them.
func _sail_overrides(model: Node) -> Array:
	var found: Array = []
	for mesh in Art.meshes(model):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var mat := mesh.get_surface_override_material(i) as BaseMaterial3D
			if mat:
				found.append(mat)
	return found

func _deck_prop(ship: Node3D, scene: PackedScene, node_name: String, at: Vector3, rot_deg: Vector3, height: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = at
	holder.rotation_degrees = rot_deg
	ship.add_child(holder)
	var model := Art.spawn(scene, "Model")
	holder.add_child(model)
	Art.fit_height(model, height)
	var box := Art.world_aabb(model)
	model.global_position.y += holder.global_position.y - box.position.y
	return holder

func _cannonball(ship: Node3D, at: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Ball"
	holder.position = at
	ship.add_child(holder)
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	sphere.radial_segments = 16
	sphere.rings = 8
	ball.mesh = sphere
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.07, 0.07, 0.07)
	iron.roughness = 0.7
	iron.metallic = 0.0
	ball.material_override = iron
	ball.position.y = 0.11
	holder.add_child(ball)
	return holder

func _place_crew() -> void:
	if _player_ship:
		var player_deck := _measure_deck(_player_ship)
		_deck_center = player_deck["center"]
		_deck_half = player_deck["half"]
		_crew.append(_make_actor(_player_ship, "CrewA", _deck_center + Vector3(1.8, 0.0, -0.8), CREW_SHIRTS[0]))
		_crew.append(_make_actor(_player_ship, "CrewB", _deck_center + Vector3(-1.6, 0.0, 0.9), CREW_SHIRTS[1]))
	if _enemy_ship:
		var navy_deck := _measure_deck(_enemy_ship)
		_crew.append(_make_actor(_enemy_ship, "Navy", navy_deck["center"] + Vector3(0.4, 0.0, 0.2), NAVY_SHIRT))

func _make_actor(parent: Node, actor_name: String, at: Vector3, shirt: Color = Color(-1, 0, 0)) -> Node3D:
	var actor := Node3D.new()
	actor.name = actor_name
	parent.add_child(actor)
	actor.position = at
	var rig := Art.castaway(shirt)
	rig.name = "Rig"
	# The stand-in faces +Z; the battle steers actors with -Z forward.
	rig.rotation.y = PI
	actor.add_child(rig)
	_fit_actor(actor, 1.78)
	if actor_name == "Captain":
		Art.arm_with_cutlass(rig)
	return actor

func _fit_actor(actor: Node3D, meters: float) -> void:
	var box := _merged_aabb(actor)
	if box.size.y < 0.05:
		return
	var deck_y := actor.global_position.y
	actor.scale = Vector3.ONE * (meters / box.size.y)
	var fitted := _merged_aabb(actor)
	actor.global_position.y += deck_y - fitted.position.y

func _paint_actor(actor: Node3D, tint: Color) -> void:
	var rig := actor.get_node_or_null("Rig")
	if rig:
		Art.paint_shirt(rig, tint)

func _build_leviathan() -> void:
	# HY3D head + TripoSR tentacle with the approved grade. No emissive eyes.
	_leviathan = Node3D.new()
	_leviathan.name = "Leviathan"
	_leviathan.visible = false
	add_child(_leviathan)
	_leviathan.position = LEVIATHAN_AT + Vector3(0, -22.0, 0)
	_head = Art.put(_leviathan, Art.LEVIATHAN_HEAD, "Head", Vector3.ZERO, Vector3(0, 20, 0), 36.0)
	Art.grade_creature(_head)
	_tentacle = Art.put(_leviathan, Art.LEVIATHAN_TENTACLE, "Tentacle", Vector3(-8.0, -0.2, -2.0), Vector3(0, 70, -8), 1.0)
	var box := Art.world_aabb(_tentacle)
	if box.size.y > 0.01:
		_tentacle.scale = Vector3.ONE * (14.0 / box.size.y)
	Art.grade_creature(_tentacle)
	for mesh in Art.meshes(_leviathan):
		mesh.extra_cull_margin = 4.0

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
	var rig := _player.get_node_or_null("Rig")
	if rig == null:
		return
	var anim := rig.get_meta("clips", null) as AnimationPlayer
	if anim and anim.current_animation == "Attack" and anim.is_playing():
		return
	var clip := "SwordIdle" if _beat == Beat.BOARDING else "Idle"
	if which == "run":
		clip = "Run"
	elif which == "jump":
		clip = "Dodge"
	elif which == "attack":
		clip = "Attack"
	Art.play(rig, clip, 0.12, 1.4 if clip == "Attack" or clip == "Dodge" else 1.0)

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

func _pulse(node: Node3D) -> void:
	if node == null:
		return
	var tween := create_tween()
	tween.set_loops(3)
	tween.tween_property(node, "scale", node.scale * 1.12, 0.18)
	tween.tween_property(node, "scale", node.scale, 0.18)

func _flash_actor(actor: Node3D) -> void:
	var rig := actor.get_node_or_null("Rig")
	if rig == null:
		return
	var shirt := rig.get_meta("shirt", null) as StandardMaterial3D
	if shirt == null:
		shirt = Art.paint_shirt(rig, Color(0.30, 0.27, 0.21))
	if shirt == null:
		return
	var original: Color = shirt.get_meta("base", shirt.albedo_color)
	shirt.set_meta("base", original)
	shirt.albedo_color = Color(0.75, 0.62, 0.42)
	var tween := create_tween()
	tween.tween_property(shirt, "albedo_color", original, 0.25)
	Art.play(rig, "Hit", 0.05)

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
	_paint_actor(boarder, NAVY_SHIRT)
	_boarders.append(boarder)

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


## Put a ship back to its sailing look: visible, upright, approved sails.
func _reset_ship(ship: Node3D) -> void:
	if ship == null:
		return
	ship.visible = true
	ship.rotation_degrees = Vector3(0, -90, 0)
	if ship.has_meta("snapped"):
		ship.remove_meta("snapped")
	var model := ship.get_node_or_null("Hull")
	for mesh in Art.meshes(ship):
		mesh.visible = true
		mesh.layers = 1
	if model:
		for mesh in Art.meshes(model):
			if mesh.mesh == null:
				continue
			for i in mesh.mesh.get_surface_count():
				var mat := mesh.get_surface_override_material(i)
				if mat and not (mat in ship.get_meta("sails", [])):
					mesh.set_surface_override_material(i, null)
		for mat in ship.get_meta("sails", []):
			(mat as BaseMaterial3D).albedo_color = Color.WHITE
	for half in _wreck_halves:
		if is_instance_valid(half):
			half.queue_free()
	_wreck_halves.clear()


func _hull_model(ship: Node3D) -> Node3D:
	return ship.get_node_or_null("Hull") as Node3D if ship else null


func _hide_rigging(ship: Node3D) -> void:
	for mesh in Art.meshes(_hull_model(ship)):
		var n := str(mesh.name).to_lower()
		if "sail" in n or "rigging" in n:
			mesh.visible = false


## Mast path (stills v2 #1): wrecked on a reef of scaled rock shelves.
func _stage_mast_wreck() -> void:
	_reset_ship(_enemy_ship)
	_reset_ship(_player_ship)
	var c := MAST_WRECK
	_player_ship.global_position = Vector3(14.0, -0.05, -30.0)
	_hide_rigging(_enemy_ship)
	# Drift the last few metres onto the reef, then hold the approved pose.
	_enemy_ship.global_position = c + Vector3(-5.0, 1.0, -2.5)
	_enemy_ship.rotation_degrees = Vector3(0, -65, 0)
	var drift := create_tween()
	drift.set_parallel(true)
	drift.tween_property(_enemy_ship, "global_position", c, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	drift.tween_property(_enemy_ship, "rotation_degrees", MAST_WRECK_ROT, 2.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_set_wake(0.8, _enemy_ship)
	Art.put(_stage, Art.COAST_ROCKS_03, "ReefShelf", Vector3(c.x + 5.3, -0.2, c.z + 0.9), Vector3(0, 30, 0), 0.34)
	Art.put(_stage, Art.COAST_ROCKS_01, "ReefFlat", Vector3(c.x - 1.0, -0.05, c.z - 4.0), Vector3(0, 120, 0), 0.18)
	Art.put(_stage, Art.CLIFF, "ReefSpireA", Vector3(c.x - 1.9, -3.6, c.z + 7.0), Vector3(0, 70, 5), 5.0)
	Art.put(_stage, Art.CLIFF, "ReefSpireB", Vector3(c.x + 3.3, -3.4, c.z - 7.3), Vector3(0, 200, -7), 4.4)
	Art.put(_stage, Art.SEA_STACK, "ReefStack", Vector3(c.x + 4.0, -0.55, c.z + 4.5), Vector3(0, 40, 0), 1.3)
	Art.put(_stage, Art.DARK_BOULDER, "ReefBoulder", Vector3(c.x + 1.5, -0.5, c.z + 5.5), Vector3(0, 30, 0), 1.8)
	Art.put(_stage, Art.SNAPPED_MAST, "SnappedMast", Vector3(c.x + 2.1, -0.55, c.z + 4.2), Vector3(0, 35, 3), 0.9)
	var sail := Art.put(_stage, Art.TORN_SAIL, "TornSail", Vector3(c.x + 2.5, -0.36, c.z + 7.4), Vector3(0, 160, 0), 0.5)
	Art.tone(sail, Color(0.58, 0.54, 0.47))
	Art.spray(_stage, Vector3(c.x + 5.0, -0.3, c.z + 1.0), 4, 2.5, 1.0, 0.2)
	Art.spray(_stage, Vector3(c.x - 1.9, -0.3, c.z + 7.0), 3, 1.5, 0.9, 0.2)
	_burst(c + Vector3(0, 6, 0), Color(0.75, 0.7, 0.62), 18, Vector3(0, -1, 0), 3.0, 0.35, 0.9)
	_shot = [c + Vector3(13.0, 6.5, 8.0), c + Vector3(0, 2.2, 0)]


## Hull path (stills v2 #2): sinking by the stern, cargo afloat.
func _stage_hull_sink() -> void:
	_reset_ship(_enemy_ship)
	_reset_ship(_player_ship)
	var sunk := HULL_SUNK
	_player_ship.global_position = Vector3(6.0, -0.05, -30.0)
	_enemy_ship.global_position = Vector3(sunk.x, -0.6, sunk.z)
	_enemy_ship.rotation_degrees = Vector3(-2.0, -90.0, -5.0)
	var sink := create_tween()
	sink.set_parallel(true)
	sink.tween_property(_enemy_ship, "global_position:y", sunk.y, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	sink.tween_property(_enemy_ship, "rotation_degrees", HULL_SUNK_ROT, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_set_wake(0.8, _enemy_ship)
	Art.spray(_stage, Vector3(sunk.x + 4.5, -0.35, sunk.z), 6, 3.5, 1.2, 0.22)
	Art.put(_stage, Art.WINE_BARREL, "FloatingBarrel", Vector3(sunk.x + 6.0, -0.6, sunk.z + 5.0), Vector3(80, 20, 0), 1.0)
	Art.put(_stage, Art.CRATE_B, "FloatingCrate", Vector3(sunk.x + 2.0, -0.65, sunk.z + 6.5), Vector3(8, 30, 5), 1.0)
	Art.put(_stage, Art.DRIFT_TRUNK, "FloatingSpar", Vector3(sunk.x + 8.0, -0.65, sunk.z + 2.0), Vector3(0, 60, 0), 1.0)
	_burst(Vector3(sunk.x, 0.2, sunk.z), Color(0.7, 0.9, 1.0), 22, Vector3(0, -2, 0), 3.5, 0.4, 1.1)
	_shot = [Vector3(sunk.x + 14.0, 7.2, sunk.z + 5.5), Vector3(sunk.x, 1.4, sunk.z)]


## Calm and rise: both ships afloat bows to +z; the beaten ship shows its
## defeat (dismasted on the mast path, low and listing on the hull path).
func _stage_two_ships(player_at: Vector3, enemy_at: Vector3, sail_color: Color, dark_rigging: bool) -> void:
	_reset_ship(_player_ship)
	_reset_ship(_enemy_ship)
	_player_ship.global_position = player_at
	_player_ship.rotation_degrees = Vector3(0, 90, 0)
	_enemy_ship.global_position = enemy_at
	_enemy_ship.rotation_degrees = Vector3(4, 90, 3)
	if _chose_mast:
		_hide_rigging(_enemy_ship)
	for ship in [_player_ship, _enemy_ship]:
		for mat in ship.get_meta("sails", []):
			(mat as BaseMaterial3D).albedo_color = sail_color
		Art.set_layers(ship, 2)
		if dark_rigging:
			# The rigging mesh carries a white boom/furled sail that read as
			# white streaks under the calm grade.
			for mesh in Art.meshes(_hull_model(ship)):
				if "rigging" in str(mesh.name).to_lower():
					Art.tone_matching(mesh, "rigging", Color(0.3, 0.3, 0.3), 1.0)
				elif str(mesh.name).begins_with("Plane"):
					mesh.visible = false


func capture_pose(which: String) -> void:
	_capture = true
	_sail_speed = 0.0
	if which == "broadside":
		_enter_impact()
		_clock = 0.4
	elif which == "mast_wreck" or which == "hull_sink":
		_chose_mast = which == "mast_wreck"
		_enter_defeat()
		_clock = 4.0
	elif which == "calm":
		_enter_calm()
		_clock = 1.8
	elif which == "leviathan":
		_enter_calm()
		_enter_rise()
		_leviathan_rise = 1.0
		_update_leviathan(0.0)
		_clock = 4.0
	elif which == "smash":
		_enter_calm()
		_enter_rise()
		_leviathan_rise = 1.0
		_update_leviathan(0.0)
		_enter_smash()
		_clock = 0.6
		if _white:
			_white.visible = false
	elif which == "establish":
		_clock = 1.0
	else:
		_enter_powder()
		_clock = 0.2
	_update_camera(1.0)


## Called by the capture harness after tweens should have settled.
func settle_capture() -> void:
	for tween in get_tree().get_processed_tweens():
		if tween.is_valid():
			tween.custom_step(10.0)
	_update_camera(1.0)


func _tick_defeat(_delta: float) -> void:
	pass


func _tick_calm(_delta: float) -> void:
	if _glow:
		var light := _glow.get_node_or_null("AbyssalLight") as OmniLight3D
		if light:
			light.light_energy = 1.1 * (0.85 + 0.15 * sin(_clock * 2.4))


func _hush_bed() -> void:
	for name in ["Ocean", "Shanty"]:
		var player := get_node_or_null(name) as AudioStreamPlayer
		if player:
			var tween := create_tween()
			tween.tween_property(player, "volume_db", -48.0, 0.8)


## Both ships break in two: the galleon is swapped for the authored wreck
## halves (hull_half_bow / hull_half_stern), which drift apart and settle.
func _snap_ship(ship: Node3D, sign: float) -> void:
	if ship == null or ship.has_meta("snapped"):
		return
	var model := _hull_model(ship)
	var length := 30.0
	if model:
		var box := _merged_local_aabb(ship)
		length = maxf(box.size.x, box.size.z)
	ship.visible = false
	var basis := ship.global_transform.basis.orthonormalized()
	var at := ship.global_position
	var scale := length / 37.4
	var i := 0
	for scene in [Art.HULL_BOW, Art.HULL_STERN]:
		var half := Art.spawn(scene, "WreckHalf%d" % i)
		_stage.add_child(half)
		# The large Dutch ship halves are modelled bow along +z; the medium
		# galleon's bow is local -x, so turn them a quarter to match.
		half.global_transform = Transform3D(basis * Basis(Vector3.UP, -PI * 0.5), at + Vector3(0, -1.2, 0))
		half.scale = Vector3.ONE * scale
		var away := 1.0 if i == 0 else -1.0
		var drift := create_tween()
		drift.set_parallel(true)
		drift.tween_property(half, "global_position", half.global_position + basis.x * (-away * 2.2) + Vector3(0, -2.2, 0), 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		drift.tween_property(half, "rotation_degrees:x", half.rotation_degrees.x + away * 14.0 * sign, 1.6)
		drift.tween_property(half, "rotation_degrees:z", half.rotation_degrees.z + 10.0 * sign, 1.6)
		_wreck_halves.append(half)
		i += 1
	ship.set_meta("snapped", true)


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
