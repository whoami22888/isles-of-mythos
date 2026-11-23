extends SceneTree

# The vertical slice player is the admitted Kenney rigged character, not the gold capsule: it is
# mounted at the server position, about 1.8 m tall with its feet on the coastal terrain, turns toward
# the server position change, and plays Walk while the server position changes and Idle otherwise.
# The capsule remains as the fallback when the rig cannot be loaded. Presentation only.

const Scene = preload("res://gameplay/vertical_slice.tscn")
const PlayerAvatar = preload("res://gameplay/player_avatar.gd")
const FallbackDiagnosticOverlayScript = preload("res://scripts/fallback_diagnostic_overlay.gd")
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
	for bone in ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]:
		lowest = minf(lowest, _bone_world(skeleton, bone).y)
	return lowest

func _toe_direction(skeleton: Skeleton3D) -> Vector2:
	var heel := (_bone_world(skeleton, "LeftFoot") + _bone_world(skeleton, "RightFoot")) * 0.5
	var toes := (_bone_world(skeleton, "LeftToes_end") + _bone_world(skeleton, "RightToes_end")) * 0.5
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
	var player_proxy := world.get_node("ServerPlayerRepresentation") as Node3D
	var avatar := player_proxy.get_node("PlayerAvatar") as Node3D
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
	var x: float = avatar.global_position.x
	var walk_terrain: float = coastal.terrain_height_at(x, 12.0)
	check(is_equal_approx(avatar.global_position.y - world.PLAYER_HALF_HEIGHT, maxf(walk_terrain, coastal.water_level() - world.WADE_DEPTH)),
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
	terrain_y = coastal.terrain_height_at(avatar.global_position.x, avatar.global_position.z)
	check(absf(feet - terrain_y) <= FEET_TOLERANCE, "idle feet on terrain after moving: %.3f vs %.3f" % [feet, terrain_y])
	world.queue_free()

	# Fallback: a missing rig keeps the capsule.
	var fallback := PlayerAvatar.new()
	fallback.character_scene_path = "res://assets/opening/kenney/missing-character.fbx"
	root.add_child(fallback)
	await _frames(1)
	check(not fallback.is_character_mounted(), "missing rig is not mounted")
	var fallback_capsule := fallback.get_node("Capsule") as MeshInstance3D
	check(fallback_capsule.visible, "capsule fallback visible when the rig is missing")
	var fallback_material := fallback_capsule.material_override as StandardMaterial3D
	check(fallback_material != null and fallback_material.albedo_color == Color(0.0, 0.8, 1.0), "runtime missing rig uses the cyan diagnostic capsule")
	var fallback_log := FileAccess.get_file_as_string("user://missing_assets.log")
	check(fallback_log.contains("mesh\tres://assets/opening/kenney/missing-character.fbx"), "runtime missing rig is recorded by the diagnostic factory")
	fallback.observe_server_position(Vector3.ZERO)
	fallback.observe_server_position(Vector3(0.5, 0, 0))
	check(fallback.animation_state() == "Walk", "fallback still tracks movement state without a rig")
	fallback.queue_free()
	await _frames(1)

	# Existing runtime rig must remain mounted when optional FBX clips and its skin texture are absent.
	var missing_optional := PlayerAvatar.new()
	missing_optional.idle_clip_path = "res://assets/opening/kenney/missing-idle-004.fbx"
	missing_optional.walk_clip_path = "res://assets/opening/kenney/missing-walk-004.fbx"
	missing_optional.skin_texture_path = "res://assets/opening/kenney/missing-skin-004.png"
	root.add_child(missing_optional)
	await _frames(2)
	check(missing_optional.is_character_mounted(), "valid runtime rig remains mounted with missing optional presentation assets")
	var optional_anim := missing_optional.animation_player()
	check(optional_anim != null and not optional_anim.has_animation("Idle") and not optional_anim.has_animation("Walk"), "missing clips leave a safe empty animation player")
	var optional_meshes := missing_optional.character().find_children("*", "MeshInstance3D", true, false)
	if not optional_meshes.is_empty():
		var optional_material := (optional_meshes[0] as MeshInstance3D).material_override as StandardMaterial3D
		check(optional_material != null and optional_material.albedo_texture != null, "missing skin uses a generated checkerboard texture")
	else:
		check(false, "runtime rig exposes a mesh for the skin fallback assertion")
	var optional_log := FileAccess.get_file_as_string("user://missing_assets.log")
	check(optional_log.contains("animation\tres://assets/opening/kenney/missing-idle-004.fbx") and optional_log.contains("animation\tres://assets/opening/kenney/missing-walk-004.fbx") and optional_log.contains("texture\tres://assets/opening/kenney/missing-skin-004.png"), "missing runtime clips and skin are logged")
	missing_optional.queue_free()
	await _frames(1)
	# Prompt 004 rendered-evidence fixture: the real visual-capture workflow sets
	# IOM_VERTICAL_SLICE_OUTPUT_DIR, which mounts this isolated SubViewport overlay.
	var diagnostic_overlay := FallbackDiagnosticOverlayScript.new()
	root.add_child(diagnostic_overlay)
	await _frames(2)
	var diagnostic_label := diagnostic_overlay.get_node_or_null("DiagnosticPanel/Content/DiagnosticLabel") as Label
	check(diagnostic_label != null and diagnostic_label.text.contains("NOT PRODUCTION ART"),
		"Fallback render evidence must be explicitly labelled diagnostic-only")
	if diagnostic_label != null:
		check(diagnostic_label.text.contains("actual " + RenderingServer.get_current_rendering_method()),
			"Fallback evidence must report the actual renderer method, not only the requested method")
		check(diagnostic_label.text.contains("SHA "),
			"Fallback evidence must display source revision provenance")
	var event_path := "user://prompt004-github-event.json"
	var event_file := FileAccess.open(event_path, FileAccess.WRITE)
	check(event_file != null, "Synthetic pull-request event must be writable for provenance regression")
	if event_file != null:
		event_file.store_string(JSON.stringify({
			"pull_request": {
				"head": {
					"sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
				}
			}
		}))
		event_file.close()
		check(
			FallbackDiagnosticOverlayScript.resolve_source_sha(event_path, "merge-sha")
				== "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			"Capture label must prefer the exact PR head SHA over the GitHub merge SHA"
		)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(event_path))
	var diagnostic_viewport := diagnostic_overlay.get_node_or_null(
		"DiagnosticPanel/Content/ViewportContainer/DiagnosticViewport"
	) as SubViewport
	check(diagnostic_viewport != null, "Fallback evidence must use a real SubViewport")
	if diagnostic_viewport != null:
		check(diagnostic_viewport.own_world_3d, "Fallback evidence must use an isolated 3D world")
		check(diagnostic_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
			"Fallback evidence viewport must render continuously during capture")
		var diagnostic_world := diagnostic_viewport.get_node_or_null("DiagnosticWorld") as Node3D
		check(diagnostic_world != null, "Fallback evidence viewport must contain a 3D world")
		if diagnostic_world != null:
			var missing_character := diagnostic_world.get_node_or_null("MissingCharacter") as MeshInstance3D
			var missing_prop := diagnostic_world.get_node_or_null("MissingProp") as MeshInstance3D
			check(missing_character != null and missing_character.mesh is CapsuleMesh,
				"Rendered fallback fixture must mount the cyan character capsule")
			check(missing_prop != null and missing_prop.mesh is BoxMesh,
				"Rendered fallback fixture must mount the magenta prop box")
			if missing_character != null:
				var character_material := missing_character.material_override as StandardMaterial3D
				check(character_material != null
					and character_material.albedo_color.r < 0.01
					and absf(character_material.albedo_color.g - 0.8) < 0.01
					and character_material.albedo_color.b > 0.99,
					"Character diagnostic must use the specified cyan material")
			if missing_prop != null:
				var prop_material := missing_prop.material_override as StandardMaterial3D
				check(prop_material != null
					and prop_material.albedo_color.r > 0.99
					and prop_material.albedo_color.g < 0.01
					and prop_material.albedo_color.b > 0.99,
					"Prop diagnostic must use the specified magenta material")
	diagnostic_overlay.queue_free()
	await _frames(1)
	if failures == 0:
		print("vertical slice player avatar test passed")
	quit(1 if failures > 0 else 0)
