extends SceneTree

# The vertical slice player is the rigged castaway stand-in (Quaternius UBC + UAL, CC0), not the gold capsule: it is
# mounted at the server position, about 1.8 m tall with its feet on the coastal terrain, turns toward
# the server position change, and plays Walk while the server position changes and Idle otherwise.
# The capsule remains as the fallback when the rig cannot be loaded. Presentation only.

const Scene = preload("res://gameplay/vertical_slice.tscn")
const PlayerAvatar = preload("res://gameplay/player_avatar.gd")
const FEET_TOLERANCE := 0.12
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("player avatar test failed: " + label)

func _frames(count: int) -> void:
	for _i in count:
		await process_frame

## Waits for at least `seconds` of simulated process time (not a frame count),
## so delta-based turning settles the same on fast and slow runners. Bounded.
func _wait_simulated(seconds: float) -> void:
	var elapsed := 0.0
	var frames := 0
	while elapsed < seconds and frames < 100000:
		await process_frame
		elapsed += root.get_process_delta_time()
		frames += 1

func _bone_world(skeleton: Skeleton3D, bone: String) -> Vector3:
	var index := skeleton.find_bone(bone)
	return (skeleton.global_transform * skeleton.get_bone_global_pose(index)).origin if index >= 0 else Vector3.INF

func _lowest_foot(skeleton: Skeleton3D) -> float:
	var lowest := INF
	for bone in ["foot_l", "foot_r", "ball_l", "ball_r"]:
		lowest = minf(lowest, _bone_world(skeleton, bone).y)
	return lowest

func _toe_direction(skeleton: Skeleton3D) -> Vector2:
	var heel := (_bone_world(skeleton, "foot_l") + _bone_world(skeleton, "foot_r")) * 0.5
	var toes := (_bone_world(skeleton, "ball_l") + _bone_world(skeleton, "ball_r")) * 0.5
	return Vector2(toes.x - heel.x, toes.z - heel.z).normalized()

func _check_faces(avatar: Node3D, skeleton: Skeleton3D, want: Vector2, label: String) -> void:
	# TURN_RATE 14/s: 0.6 s of simulation leaves < 0.03% of the turn remaining.
	await _wait_simulated(0.6)
	var yaw: float = avatar.facing_yaw()
	var forward := Vector2(sin(yaw), cos(yaw))
	check(forward.dot(want) > 0.97, "%s: body yaw faces %s, got %s" % [label, want, forward])
	var toes := _toe_direction(skeleton)
	check(toes.dot(want) > 0.8, "%s: the rig's toes point along %s, got %s" % [label, want, toes])

func run() -> void:
	var world = Scene.instantiate()
	root.add_child(world)
	await _frames(2)
	var coastal := world.get_node_or_null("CoastalWorld") as Node3D
	var avatar := world.get_node("ServerPlayerRepresentation") as Node3D
	check(coastal != null, "coastal world mounted")
	check(avatar.has_method("is_character_mounted") and avatar.is_character_mounted(), "rigged character mounted")
	if coastal == null or not avatar.is_character_mounted():
		quit(1)
		return
	var capsule := avatar.get_node("Capsule") as MeshInstance3D
	var character: Node3D = avatar.character()
	check(not capsule.visible, "placeholder capsule hidden")
	check(character.is_visible_in_tree(), "character visible")
	var skeleton := character.find_child("Skeleton3D", true, false) as Skeleton3D
	check(skeleton != null, "character has a skeleton")
	var anim: AnimationPlayer = avatar.animation_player()
	check(anim != null and anim.has_animation("Idle") and anim.has_animation("Walk"), "Idle and Walk clips present")

	# First authoritative state restores the session on the beach: a teleport, not a walk.
	world._on_player_state({"x": 16.0, "y": 12.0})
	await _frames(4)
	check(avatar.animation_state() == "Idle" and anim.current_animation == "Idle", "restored position stands idle")
	var terrain_y: float = coastal.terrain_height_at(16.0, 12.0)
	var feet := _lowest_foot(skeleton)
	check(absf(feet - terrain_y) <= FEET_TOLERANCE, "feet on terrain: lowest foot bone %.3f terrain %.3f" % [feet, terrain_y])
	var height := 0.0
	for node in character.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (node as MeshInstance3D).global_transform * (node as MeshInstance3D).get_aabb()
		height = maxf(height, box.size.y)
	check(absf(height - 1.8) < 0.1, "character is about 1.8 m tall, got %.3f" % height)

	# Server steps east: walk and face +X.
	for i in 4:
		world._on_player_state({"x": 16.0 + 0.3 * (i + 1), "y": 12.0})
		await _frames(2)
	check(avatar.animation_state() == "Walk" and anim.current_animation == "Walk" and anim.is_playing(), "walks while the server position changes")
	await _check_faces(avatar, skeleton, Vector2(1, 0), "east step")
	# Feet stay on the terrain at the new server position while walking.
	var x: float = avatar.position.x
	var walk_terrain: float = coastal.terrain_height_at(x, 12.0)
	check(is_equal_approx(avatar.position.y - world.PLAYER_HALF_HEIGHT, maxf(walk_terrain, coastal.water_level() - world.WADE_DEPTH)),
		"walking position keeps the feet height rule")

	# Then north (server -y, world -Z).
	for i in 3:
		world._on_player_state({"x": x, "y": 12.0 - 0.3 * (i + 1)})
		await _frames(2)
	check(avatar.animation_state() == "Walk", "keeps walking on a new heading")
	await _check_faces(avatar, skeleton, Vector2(0, -1), "north step")

	# No further server change: back to idle after the hold window.
	await create_timer(0.6).timeout
	check(avatar.animation_state() == "Idle" and anim.current_animation == "Idle", "returns to idle when the server position stops changing")
	feet = _lowest_foot(skeleton)
	terrain_y = coastal.terrain_height_at(avatar.position.x, avatar.position.z)
	check(absf(feet - terrain_y) <= FEET_TOLERANCE, "idle feet on terrain after moving: %.3f vs %.3f" % [feet, terrain_y])
	world.queue_free()

	# Fallback: a missing rig keeps the capsule.
	var fallback := PlayerAvatar.new()
	fallback.character_scene_path = "res://assets/opening/library/missing-character.glb"
	root.add_child(fallback)
	await _frames(1)
	check(not fallback.is_character_mounted(), "missing rig is not mounted")
	check((fallback.get_node("Capsule") as MeshInstance3D).visible, "capsule fallback visible when the rig is missing")
	fallback.observe_server_position(Vector3.ZERO)
	fallback.observe_server_position(Vector3(0.5, 0, 0))
	check(fallback.animation_state() == "Walk", "fallback still tracks movement state without a rig")
	fallback.queue_free()
	await _frames(1)
	if failures == 0:
		print("vertical slice player avatar test passed")
	quit(1 if failures > 0 else 0)
