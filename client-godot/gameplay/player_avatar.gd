extends Node3D
## Presentation-only avatar for the server-authoritative player in the
## vertical slice. The node's position is still written by the world from
## server state (body centre, feet + feet_offset); this script only decides how
## that position looks: the castaway stand-in (Quaternius Ultimate Base
## Characters body with Universal Animation Library clips, CC0, 1K textures;
## see assets/opening/PROVENANCE.md) scaled to about 1.8 m with its feet on
## the terrain, turned toward the last server position change, and playing
## Idle or Walk depending on whether the server position is changing.
## Nothing here sends intents or predicts movement. If the rig cannot be
## loaded, the original gold capsule stays visible as a cheap fallback.

# Full literal path AND preload: concatenated strings are invisible to the
# export dependency scanner, so the rig could be left out of the PCK.
const CHARACTER_SCENE_PATH := "res://assets/opening/library/castaway_ubc_rigged/castaway_ubc_rigged.glb"
const CHARACTER_SCENE := preload("res://assets/opening/library/castaway_ubc_rigged/castaway_ubc_rigged.glb")
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
## The UAL walk cycle is authored for about 1.4 m/s; the server moves the
## player at 4 m/s on land, so play it faster to keep the feet from skating.
const WALK_SPEED_SCALE := 1.6
const ANIM_IDLE := "Idle"
const ANIM_WALK := "Walk"

## Height of the node origin above the feet (the world's PLAYER_HALF_HEIGHT).
var feet_offset := 0.9
var character_scene_path := CHARACTER_SCENE_PATH

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
	# The rig keeps its own 1K linen/canvas/skin materials and clips.
	_anim = rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for clip_name in [ANIM_IDLE, ANIM_WALK]:
			if _anim.has_animation(clip_name):
				_anim.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
	_character = rig
	_capsule.visible = false
	if _anim and _anim.has_animation(ANIM_IDLE):
		_anim.play(ANIM_IDLE)

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
