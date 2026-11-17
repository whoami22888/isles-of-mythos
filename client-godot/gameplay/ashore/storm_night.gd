extends Node
## First-night storm for the washed-ashore island (DIGEST beat 14).
## Owned by washed_ashore.gd; reads and writes its state directly.
## Darkness, slanted rain, wind and rain loop, lightning as short contrast
## punches (sun + exposure spike, no bloom or emissive), thunder after a
## delay, fire fuel that burns down and must be fed with wood, Tide-Puck
## huddling and whimpering, and a dawn that restores the day look.
## Mobile budget: one CPUParticles3D (500 quads) that follows the camera.

const AUDIO := "res://assets/ashore/audio/"
const NIGHT_SECONDS := 95.0
const THREAT_AT := 26.0
const FUEL_MAX := 100.0
const FUEL_DRAIN := 1.35
const FUEL_PER_WOOD := 34.0
const FEED_RANGE := 3.4
const SHELTER_RANGE := 3.2
const FIRE_WARM_RANGE := 4.2

var host: Node3D
var active := false
var dawn := false
var age := 0.0
var fuel := FUEL_MAX
var threat_sent := false
var feeds := 0
var flashes := 0
var thunders := 0
var whimpers := 0
var cold_ticks := 0
var _flash_t := -1.0
var _next_flash := 7.0
var _thunder_in := -1.0
var _whimper_in := 4.0
var _dawn_k := -1.0
var _rain: CPUParticles3D
var _rain_audio: AudioStreamPlayer
var _base := {}
var _rng := RandomNumberGenerator.new()
## Capture-only: hold the lightning strobe on (renders from tests).
var hold_flash := false


func begin() -> void:
	if active or dawn:
		return
	active = true
	age = 0.0
	fuel = FUEL_MAX * 0.8
	_rng.seed = 4113
	_capture_base()
	_build_rain()
	_apply_night(0.0)
	if not host._fire_lit:
		host._light_fire()
	host._show_hint("Night storm! Keep the fire fed and stay under the lean-to")
	host._hint_t = 5.0
	host._play(AUDIO + "thunder_b.ogg", -3.0, 1.0)
	host._vibrate(90, 0.5)
	_next_flash = 3.0


func is_night() -> bool:
	return active and not dawn


func dawn_left() -> float:
	return maxf(NIGHT_SECONDS - age, 0.0)


func tick(delta: float) -> void:
	if _dawn_k >= 0.0:
		_tick_dawn(delta)
		return
	if not active:
		return
	age += delta
	_tick_fire(delta)
	_tick_lightning(delta)
	_tick_rain()
	_tick_pet(delta)
	if not threat_sent and age >= THREAT_AT and host._step == "storm":
		threat_sent = true
		_warn_threat()
	# Dawn only after the threat is dealt with.
	if host._step == "night" and age >= NIGHT_SECONDS:
		_begin_dawn()


## Warmth rules during the storm. Returns true when the storm owns warmth.
func warmth(delta: float) -> bool:
	if not active or dawn:
		return false
	var p: Vector3 = host._player.global_position
	var sheltered: bool = host._shelter and host._hut and host._flat(p, host._hut.global_position) < SHELTER_RANGE
	var by_fire: bool = host._fire_lit and host._flat(p, host._pit_position()) < FIRE_WARM_RANGE
	var rate := -1.5
	if sheltered and by_fire:
		rate = 5.0
	elif sheltered:
		rate = 0.4
	elif by_fire:
		rate = -0.35
	host._warmth = clampf(host._warmth + rate * delta, 0.0, 100.0)
	if host._warmth <= 0.0:
		host._warmth = 22.0
		host._health = maxi(host._health - 1, 1)
		cold_ticks += 1
		host._show_hint("Freezing! Get under the lean-to by the fire")
		host._hint_t = 3.0
		host._vibrate(120, 0.6)
	return true


func can_feed() -> bool:
	return is_night() and fuel < FUEL_MAX - 12.0 and int(host._inv.get("wood", 0)) > 0 \
		and host._near(host._pit_position(), FEED_RANGE)


func feed() -> void:
	host._inv["wood"] = int(host._inv.get("wood", 0)) - 1
	fuel = minf(FUEL_MAX, fuel + FUEL_PER_WOOD)
	feeds += 1
	if not host._fire_lit:
		host._light_fire()
		host._note_burst("Relit!")
	else:
		host._note_burst("Fire +")
	host._play(AUDIO + "build_place.ogg", -8.0, 0.8)
	host._chips(host._pit_position() + Vector3.UP * 0.4, Color(0.5, 0.36, 0.22), 8)
	host._vibrate(40, 0.4)


func line(step: String) -> String:
	var clock := "%d:%02d" % [int(dawn_left()) / 60, int(dawn_left()) % 60]
	var fire := "Fire %d%%" % int(round(fuel))
	if not host._fire_lit:
		fire = "Fire out!"
	if step == "storm":
		return "Storm night  ·  %s  ·  dawn in %s" % [fire, clock]
	return "Hold out till dawn  ·  %s  ·  %s" % [fire, clock]


## Where the play-test pointer should lead during the night.
func point() -> Vector3:
	if fuel < 55.0 or not host._fire_lit:
		if int(host._inv.get("wood", 0)) > 0:
			return host._pit_position()
		var wood := _nearest_wood()
		if not wood.is_empty():
			return (wood.get("root") as Node3D).global_position
	if host._hut and host._shelter:
		var hut: Vector3 = host._hut.global_position
		var to_pit: Vector3 = host._pit_position() - hut
		to_pit.y = 0.0
		return hut + to_pit.normalized() * minf(1.2, to_pit.length() * 0.5)
	return host._pit_position()


func flash_now() -> void:
	_flash_t = 0.0
	flashes += 1
	_thunder_in = _rng.randf_range(0.35, 1.4)


func state() -> Dictionary:
	return {"active": active, "dawn": dawn, "age": age, "fuel": fuel, "threat": threat_sent}


func restore(s: Dictionary) -> void:
	if s.is_empty() or not bool(s.get("active", false)) or bool(s.get("dawn", false)):
		return
	begin()
	age = float(s.get("age", 0.0))
	fuel = float(s.get("fuel", fuel))
	threat_sent = bool(s.get("threat", false))


# --- internals ------------------------------------------------------------

func _capture_base() -> void:
	var sun: DirectionalLight3D = host._sun
	var env: Environment = host._env
	if sun:
		_base["sun_e"] = sun.light_energy
		_base["sun_c"] = sun.light_color
		_base["sun_r"] = sun.rotation_degrees
	if env:
		_base["exp"] = host._base_exposure
		_base["fog_c"] = env.fog_light_color
		_base["fog_d"] = env.fog_density
		_base["amb_e"] = env.ambient_light_energy
		_base["sat"] = env.adjustment_saturation
		_base["adj"] = env.adjustment_enabled
		_base["bg"] = env.background_energy_multiplier
		_base["fog_end"] = env.fog_depth_end
		_base["fog_begin"] = env.fog_depth_begin
		_base["bright"] = env.adjustment_brightness


func _apply_night(flash: float) -> void:
	var sun: DirectionalLight3D = host._sun
	var env: Environment = host._env
	if sun:
		sun.light_energy = lerpf(0.7, 1.6, flash)
		sun.light_color = Color(0.55, 0.64, 0.78).lerp(Color(0.86, 0.9, 1.0), flash)
	if env:
		env.fog_light_color = Color(0.2, 0.24, 0.3).lerp(Color(0.6, 0.66, 0.76), flash)
		env.fog_density = float(_base.get("fog_d", 0.01)) * 2.2 + 0.004
		env.ambient_light_energy = float(_base.get("amb_e", 1.0)) * lerpf(0.95, 1.0, flash)
		env.tonemap_exposure = float(_base.get("exp", 1.0)) * lerpf(0.8, 0.95, flash)
		env.adjustment_enabled = true
		env.adjustment_saturation = lerpf(0.62, 0.35, flash)
		env.adjustment_brightness = float(_base.get("bright", 1.0)) * lerpf(0.9, 1.05, flash)
		env.background_energy_multiplier = float(_base.get("bg", 1.0)) * lerpf(0.2, 0.6, flash)
		env.fog_depth_begin = 6.0
		env.fog_depth_end = lerpf(70.0, 140.0, flash)


func _tick_fire(delta: float) -> void:
	if not host._fire_lit:
		return
	var drain := FUEL_DRAIN
	if host._step == "storm" or host._step == "night":
		drain *= 1.0
	fuel = maxf(fuel - drain * delta, 0.0)
	var fire_node: Node3D = host._flame
	if fire_node and fire_node.get_child_count() > 0:
		var k := clampf(fuel / 60.0, 0.18, 1.0)
		for c in fire_node.get_children():
			if c is MeshInstance3D and str(c.name) != "Stones":
				(c as MeshInstance3D).scale = Vector3.ONE * k
	if fuel <= 0.0:
		host._fire_lit = false
		if fire_node:
			fire_node.visible = true
			for c in fire_node.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).visible = false
		if host._fire_loop:
			host._fire_loop.stop()
		host._show_hint("The fire's out! Feed it wood")
		host._hint_t = 3.0
		host._play(AUDIO + "squeak.ogg", -6.0, 0.55)
	elif fuel < 25.0 and fmod(age, 6.0) < delta:
		host._show_hint("The fire is dying. Add wood!")
		host._hint_t = 2.5


func _tick_lightning(delta: float) -> void:
	_next_flash -= delta
	if _next_flash <= 0.0:
		flash_now()
		_next_flash = _rng.randf_range(6.0, 13.0)
	var punch := 0.0
	if _flash_t >= 0.0:
		_flash_t += delta
		# Two hard strobes then out: 0-0.07 s, 0.16-0.24 s.
		if _flash_t < 0.07:
			punch = 1.0
		elif _flash_t > 0.16 and _flash_t < 0.24:
			punch = 0.75
		elif _flash_t > 0.4:
			_flash_t = -1.0
	if hold_flash:
		punch = 1.0
	_apply_night(punch)
	if _thunder_in >= 0.0:
		_thunder_in -= delta
		if _thunder_in < 0.0:
			thunders += 1
			host._play(AUDIO + ("thunder_a.ogg" if thunders % 2 == 1 else "thunder_b.ogg"), 0.0, _rng.randf_range(0.9, 1.05))
			host._vibrate(140, 0.9)


func _build_rain() -> void:
	if _rain:
		return
	_rain = CPUParticles3D.new()
	_rain.name = "StormRain"
	_rain.amount = 500
	_rain.lifetime = 0.7
	_rain.preprocess = 0.7
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(9.0, 0.5, 9.0)
	_rain.direction = Vector3(0.28, -1.0, 0.12)
	_rain.spread = 4.0
	_rain.gravity = Vector3(0, -9.0, 0)
	_rain.initial_velocity_min = 16.0
	_rain.initial_velocity_max = 20.0
	_rain.particle_flag_align_y = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, 0.55)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_color = Color(0.62, 0.68, 0.74, 0.32)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	_rain.mesh = quad
	host.add_child(_rain)
	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.name = "RainLoop"
	var stream = load(AUDIO + "rain_loop.ogg")
	if stream:
		stream = stream.duplicate()
		if "loop" in stream:
			stream.loop = true
		_rain_audio.stream = stream
		_rain_audio.volume_db = -6.0
		host.add_child(_rain_audio)
		_rain_audio.play()


func _tick_rain() -> void:
	if _rain and host._camera:
		var c: Vector3 = host._camera.global_position
		_rain.global_position = c + Vector3(-1.5, 6.5, -0.6) - host._camera.global_transform.basis.z * 3.0


func _tick_pet(delta: float) -> void:
	if not host._pet_freed or host._pet == null:
		return
	if host._pet_mode in ["follow", "huddle", "point", "sniff"] and host._shelter and host._hut and host._step != "dusk":
		host._pet_mode = "huddle"
		var hut: Vector3 = host._hut.global_position
		var goal: Vector3 = hut.lerp(host._pit_position(), 0.25) + Vector3(0.6, 0, 0.4)
		goal.y = host._ground_y(goal.x, goal.z)
		host._pet_goal = goal
	_whimper_in -= delta
	if _whimper_in <= 0.0 and host._step != "dusk":
		_whimper_in = _rng.randf_range(5.0, 9.0)
		whimpers += 1
		host._play(AUDIO + "squeak.ogg", -9.0, 0.62)


func _warn_threat() -> void:
	var name := str(host._pet_stats.get("name", "Tide-Puck"))
	host._show_hint("%s growls at the wreck... something's coming!" % name)
	host._hint_t = 3.5
	host._play(AUDIO + "bark.ogg", -3.0, 0.6)
	host._vibrate(160, 0.7)
	if host._pet_freed:
		host._pet_mode = "follow"
	flash_now()
	host.get_tree().create_timer(2.2, false).timeout.connect(func():
		if host._step == "storm":
			host._enter("dusk"))


func _nearest_wood() -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1e9
	for node in host._nodes:
		if bool(node.get("depleted", false)):
			continue
		var kind := str(node.get("kind", ""))
		if not (kind in ["tree", "drift", "hull"]):
			continue
		var d: float = host._flat(host._player.global_position, (node.get("root") as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


func _begin_dawn() -> void:
	dawn = true
	_dawn_k = 0.0
	host._show_hint("Dawn. You survived the storm.")
	host._hint_t = 4.0
	if _rain:
		_rain.emitting = false
	if _rain_audio:
		var tw := host.create_tween()
		tw.tween_property(_rain_audio, "volume_db", -40.0, 4.0)
	host._dawn_reward()


func _tick_dawn(delta: float) -> void:
	# Two beats: night -> warm low sunrise (held), then sunrise -> full day.
	_dawn_k = minf(_dawn_k + delta / 16.0, 1.0)
	var k := _dawn_k
	var a := smoothstep(0.0, 0.4, k)
	var b := smoothstep(0.62, 1.0, k)
	var sun: DirectionalLight3D = host._sun
	var env: Environment = host._env
	var night := Color(0.55, 0.64, 0.78)
	var warm := Color(1.0, 0.6, 0.36)
	var fog_d := float(_base.get("fog_d", 0.01))
	if sun:
		sun.light_energy = lerpf(lerpf(0.7, 1.15, a), float(_base.get("sun_e", 1.0)), b)
		sun.light_color = night.lerp(warm, a).lerp(_base.get("sun_c", Color.WHITE), b)
		var day_r: Vector3 = _base.get("sun_r", sun.rotation_degrees)
		var low := Vector3(-9.0, day_r.y, day_r.z)
		sun.rotation_degrees = low.lerp(day_r, b)
	if env:
		var dawn_fog := Color(0.92, 0.6, 0.44)
		env.fog_light_color = Color(0.13, 0.16, 0.2).lerp(dawn_fog, a).lerp(_base.get("fog_c", dawn_fog), b)
		env.fog_density = lerpf(lerpf(fog_d * 2.2 + 0.004, fog_d * 1.5, a), fog_d, b)
		env.ambient_light_energy = float(_base.get("amb_e", 1.0)) * lerpf(lerpf(0.95, 0.75, a), 1.0, b)
		env.tonemap_exposure = float(_base.get("exp", 1.0)) * lerpf(lerpf(0.8, 0.92, a), 1.0, b)
		env.adjustment_saturation = lerpf(lerpf(0.62, float(_base.get("sat", 1.0)) * 1.08, a), float(_base.get("sat", 1.0)), b)
		env.adjustment_brightness = float(_base.get("bright", 1.0)) * lerpf(0.9, 1.0, maxf(a * 0.5, b))
		env.background_energy_multiplier = float(_base.get("bg", 1.0)) * lerpf(lerpf(0.2, 0.55, a), 1.0, b)
		env.fog_depth_begin = lerpf(lerpf(6.0, 14.0, a), float(_base.get("fog_begin", 32.0)), b)
		env.fog_depth_end = lerpf(lerpf(70.0, 110.0, a), float(_base.get("fog_end", 180.0)), b)
	if k >= 1.0:
		_dawn_k = -1.0
		active = false
