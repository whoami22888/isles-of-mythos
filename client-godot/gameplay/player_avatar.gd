extends Node3D
## Presentation-only avatar for the server-authoritative player in the
## vertical slice. The node's position is still written by the world from
## server state (body centre, feet + feet_offset); this script only decides how
## that position looks: the admitted Kenney "Animated Characters" rig
## (CC0-1.0, see assets/opening/PROVENANCE.md) scaled to about 1.8 m with its
## feet on the terrain, turned toward the last server position change, and
## playing Idle or Walk depending on whether the server position is changing.
## Nothing here sends intents or predicts movement. If the rig cannot be
## loaded, the original gold capsule stays visible as a cheap fallback.

const KENNEY := "res://assets/opening/kenney/"
# Full literal paths AND preloads: the 10 Nov phone APK showed the gold
# capsule (washed white in sun) because the Kenney FBX never mounted.
# Concatenated KENNEY + "characterMedium.fbx" strings are invisible to the
# export dependency scanner, so the remapped .scn can be omitted from the
# PCK even with export_filter=all_resources. preload() forces a pack.
const CHARACTER_SCENE_PATH := "res://assets/opening/kenney/characterMedium.fbx"
const IDLE_CLIP_PATH := "res://assets/opening/kenney/idle.fbx"
const WALK_CLIP_PATH := "res://assets/opening/kenney/run.fbx"
const SKIN_TEXTURE_PATH := "res://assets/opening/kenney/criminalMaleA.png"
const CHARACTER_SCENE := preload("res://assets/opening/kenney/characterMedium.fbx")
const IDLE_CLIP := preload("res://assets/opening/kenney/idle.fbx")
const WALK_CLIP := preload("res://assets/opening/kenney/run.fbx")
const SKIN_TEXTURE := preload("res://assets/opening/kenney/criminalMaleA.png")
const TARGET_HEIGHT := 1.8
## Walk is held this long after the last server position change, so the 20 Hz
## state stream (moves are sent every 0.08 s) reads as continuous walking.
const WALK_HOLD_SECONDS := 0.3
## Planar server deltas below this are treated as standing still.
const MOVE_EPSILON := 0.01
## Larger jumps (restored session, respawn) snap without walking or turning.
const TELEPORT_DISTANCE := 4.0
const TURN_RATE := 14.0
const BLEND_SECONDS := 0.18
## The pack ships idle, run and jump only; the run clip slowed down stands in
## for a walk cycle at the server's 4 m/s land speed.
const WALK_SPEED_SCALE := 0.8
const ANIM_IDLE := "Idle"
const ANIM_WALK := "Walk"

## Height of the node origin above the feet (the world's PLAYER_HALF_HEIGHT).
var feet_offset := 0.9
var character_scene_path := CHARACTER_SCENE_PATH
var idle_clip_path := IDLE_CLIP_PATH
var walk_clip_path := WALK_CLIP_PATH
var skin_texture_path := SKIN_TEXTURE_PATH

var _capsule: MeshInstance3D
var _body: Node3D
var _character: Node3D
var _anim: AnimationPlayer
var _last_xz := Vector2.ZERO
var _has_last := false
var _walk_timer := 0.0
var _target_yaw := 0.0
var _state := ANIM_IDLE

func _ready() -> void:
	_capsule = MeshInstance3D.new()
	_capsule.name = "Capsule"
	var capsule := CapsuleMesh.new()
	capsule.height = TARGET_HEIGHT
	capsule.radius = 0.35
	_capsule.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#d9a441")
	_capsule.material_override = mat
	add_child(_capsule)
	_body = Node3D.new()
	_body.name = "Body"
	_body.position = Vector3(0.0, -feet_offset, 0.0)
	add_child(_body)
	_mount_character()

func is_character_mounted() -> bool:
	return _character != null

func animation_state() -> String:
	return _state

## Current yaw of the visible body (radians, 0 = facing world +Z).
func facing_yaw() -> float:
	return _body.rotation.y if _body else 0.0

func character() -> Node3D:
	return _character

func animation_player() -> AnimationPlayer:
	return _anim

## Called by the world after every authoritative position update.
func observe_server_position(world_position: Vector3) -> void:
	var xz := Vector2(world_position.x, world_position.z)
	if not _has_last:
		_has_last = true
		_last_xz = xz
		return
	var step := xz - _last_xz
	_last_xz = xz
	var distance := step.length()
	if distance < MOVE_EPSILON:
		return
	if distance > TELEPORT_DISTANCE:
		_walk_timer = 0.0
		_set_state(ANIM_IDLE)
		return
	# The rig faces +Z at yaw 0, so the yaw toward a planar step is atan2(x, z).
	_target_yaw = atan2(step.x, step.y)
	_walk_timer = WALK_HOLD_SECONDS
	_set_state(ANIM_WALK)

func _process(delta: float) -> void:
	if _walk_timer > 0.0:
		_walk_timer -= delta
		if _walk_timer <= 0.0:
			_set_state(ANIM_IDLE)
	if _body:
		_body.rotation.y = lerp_angle(_body.rotation.y, _target_yaw, 1.0 - exp(-TURN_RATE * delta))

func _set_state(next: String) -> void:
	if next == _state and (_anim == null or _anim.is_playing()):
		return
	_state = next
	if _anim and _anim.has_animation(next):
		_anim.play(next, BLEND_SECONDS)
		_anim.speed_scale = WALK_SPEED_SCALE if next == ANIM_WALK else 1.0

func _mount_character() -> void:
	var packed = CHARACTER_SCENE if character_scene_path == CHARACTER_SCENE_PATH else load(character_scene_path)
	if packed == null and ResourceLoader.exists(character_scene_path):
		packed = load(character_scene_path)
	if not (packed is PackedScene):
		return
	var rig = packed.instantiate()
	if not (rig is Node3D):
		if rig:
			rig.free()
		return
	var meshes := _meshes(rig)
	if meshes.is_empty():
		rig.free()
		return
	rig.name = "Character"
	_body.add_child(rig)
	var box := _merged_aabb(rig)
	if box.size.y < 0.05:
		rig.queue_free()
		return
	rig.scale = Vector3.ONE * (TARGET_HEIGHT / box.size.y)
	var fitted := _merged_aabb(rig)
	rig.position.y -= fitted.position.y
	# One shared material and one 35 KB albedo for the single skinned surface.
	var skin = SKIN_TEXTURE if skin_texture_path == SKIN_TEXTURE_PATH else (load(skin_texture_path) if ResourceLoader.exists(skin_texture_path) else null)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = skin
	mat.roughness = 0.62
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for mesh in meshes:
		mesh.material_override = mat
	_anim = AnimationPlayer.new()
	_anim.name = "Clips"
	rig.add_child(_anim)
	var library := AnimationLibrary.new()
	_anim.add_animation_library("", library)
	_copy_longest_clip(library, idle_clip_path, ANIM_IDLE)
	_copy_longest_clip(library, walk_clip_path, ANIM_WALK)
	_character = rig
	_capsule.visible = false
	if _anim.has_animation(ANIM_IDLE):
		_anim.play(ANIM_IDLE)

func _copy_longest_clip(library: AnimationLibrary, path: String, alias: String) -> void:
	var packed = null
	if path == IDLE_CLIP_PATH:
		packed = IDLE_CLIP
	elif path == WALK_CLIP_PATH:
		packed = WALK_CLIP
	elif ResourceLoader.exists(path):
		packed = load(path)
	if not (packed is PackedScene):
		return
	var temp = packed.instantiate()
	var source := temp.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var best: Animation = null
	if source:
		for anim_name in source.get_animation_list():
			var anim := source.get_animation(anim_name)
			if anim != null and (best == null or anim.length > best.length):
				best = anim
	if best != null:
		var clip := best.duplicate() as Animation
		clip.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(alias, clip)
	temp.free()

## Bounds of the rig's meshes in the Body's space (feet at y = 0 once fitted).
func _merged_aabb(rig: Node3D) -> AABB:
	var to_body := _body.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mesh in _meshes(rig):
		var local := mesh.get_aabb()
		for i in 8:
			var corner := local.position + Vector3(
				local.size.x if i & 1 else 0.0,
				local.size.y if i & 2 else 0.0,
				local.size.z if i & 4 else 0.0)
			var point: Vector3 = to_body * (mesh.global_transform * corner)
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
