class_name ShipBowSprayEffect
extends Node3D
## Isolated client-only GPU wake-contact spray. No collisions, authority or network writes.
## Keep this node outside the animated hull so particles remain in world space.
## Ship model forward axis and metres-per-unit must be confirmed at integration.

const SPRAY_SHADER: Shader = preload("res://shaders/ship_bow_spray.gdshader")
const MAX_DROPLETS: int = 112
const MIN_VALID_DELTA: float = 0.0001

@export_range(0.4, 12.0, 0.1) var minimum_speed: float = 1.5
@export_range(2.0, 20.0, 0.5) var full_spray_speed: float = 8.0
@export_range(0.4, 20.0, 0.1) var hull_length: float = 9.0
@export_range(0.3, 8.0, 0.1) var hull_width: float = 3.0
@export var sea_level: float = -0.35
@export var bow_axis_local := Vector3(0.0, 0.0, -1.0)

var vessel: Node3D
var emitter: GPUParticles3D
var _particle_motion: ParticleProcessMaterial
var _previous_position := Vector3.ZERO
var _has_position := false
var _last_speed: float = 0.0


func _ready() -> void:
    emitter = GPUParticles3D.new()
    emitter.name = "WorldSpaceBowContactSpray"
    emitter.amount = MAX_DROPLETS
    emitter.lifetime = 1.05
    emitter.explosiveness = 0.0
    emitter.fixed_fps = 30
    emitter.local_coords = false
    emitter.one_shot = false
    emitter.emitting = false
    emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    emitter.visibility_aabb = AABB(Vector3(-12.0, -5.0, -12.0), Vector3(24.0, 12.0, 24.0))
    var fragment := ShaderMaterial.new()
    fragment.shader = SPRAY_SHADER
    var droplet_mesh := QuadMesh.new()
    droplet_mesh.size = Vector2(0.13, 0.37)
    droplet_mesh.material = fragment
    emitter.draw_pass_1 = droplet_mesh
    _particle_motion = ParticleProcessMaterial.new()
    _particle_motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    _particle_motion.emission_box_extents = Vector3(hull_width * 0.36, 0.04, 0.12)
    _particle_motion.direction = Vector3(0.0, 0.45, -0.9).normalized()
    _particle_motion.spread = 37.0
    _particle_motion.gravity = Vector3(0.0, -6.8, 0.0)
    _particle_motion.initial_velocity_min = 1.8
    _particle_motion.initial_velocity_max = 4.6
    _particle_motion.scale_min = 0.65
    _particle_motion.scale_max = 1.35
    emitter.process_material = _particle_motion
    add_child(emitter)


func attach_vessel(target: Node3D) -> void:
    if emitter != null:
        emitter.emitting = false
        emitter.restart()
    vessel = target
    _has_position = is_instance_valid(target)
    _last_speed = 0.0
    if _has_position:
        _previous_position = target.global_position


func get_last_speed() -> float:
    return _last_speed


func _process(delta: float) -> void:
    advance_contact(delta)


func advance_contact(delta: float) -> void:
    if emitter == null or not is_finite(delta) or delta < MIN_VALID_DELTA:
        return
    if not is_instance_valid(vessel):
        emitter.emitting = false
        _has_position = false
        _last_speed = 0.0
        return
    var position_now := vessel.global_position
    if not _has_position:
        _previous_position = position_now
        _has_position = true
        emitter.emitting = false
        return
    var translation := position_now - _previous_position
    _previous_position = position_now
    translation.y = 0.0
    var speed := translation.length() / delta
    _last_speed = speed
    var forward := vessel.global_basis * bow_axis_local
    forward.y = 0.0
    if forward.length_squared() <= 0.00001:
        emitter.emitting = false
        return
    forward = forward.normalized()
    var aligned := translation.length_squared() > 0.00001 and translation.normalized().dot(forward) >= 0.20
    var intensity := clampf((speed - minimum_speed) / maxf(0.01, full_spray_speed - minimum_speed), 0.0, 1.0)
    if not aligned or speed < minimum_speed or intensity <= 0.0:
        emitter.emitting = false
        return
    var bow := position_now + forward * (hull_length * 0.5)
    global_position = Vector3(bow.x, sea_level + 0.11, bow.z)
    # Rotate the short emission box with the bow heading, but keep horizontal
    # contact as the local origin for GPU droplets.
    global_rotation = Vector3(0.0, atan2(-forward.x, -forward.z), 0.0)
    _particle_motion.emission_box_extents.x = hull_width * 0.36
    _particle_motion.initial_velocity_min = 1.8 + intensity * 1.4
    _particle_motion.initial_velocity_max = 4.6 + intensity * 3.2
    emitter.amount_ratio = clampf(0.15 + intensity * 0.85, 0.0, 1.0)
    emitter.emitting = true
