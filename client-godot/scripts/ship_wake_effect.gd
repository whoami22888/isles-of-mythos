class_name ShipWakeEffect
extends Node3D
## Client-side wake trails only. Never mutates ship position, speed, or server state.
## Attach beside the ship in the world scene (not beneath a rotating hull).
## Does not make a visual-quality claim until captured in the real Godot renderer.

const FOAM_SHADER: Shader = preload("res://shaders/ship_wake_foam.gdshader")
const MAX_SAMPLES := 80
const MIN_STEP_M := 0.12
const MIN_TICK_SEC := 0.08

@export_range(0.05, 0.5, 0.01) var sample_interval: float = 0.12
@export_range(1.0, 20.0, 0.5) var trail_lifetime: float = 8.0
@export_range(0.2, 10.0, 0.1) var hull_width: float = 3.2
@export_range(0.2, 20.0, 0.1) var hull_length: float = 9.0
@export_range(0.1, 10.0, 0.1) var minimum_speed: float = 0.65
@export var sea_level: float = -0.35

var vessel: Node3D
var _foam: MeshInstance3D
var _mesh: ArrayMesh
var _samples: Array[Dictionary] = []
var _elapsed: float = 0.0
var _sample_clock: float = 0.0
var _last_vessel_position := Vector3.ZERO
var _has_previous_position := false
var _triangles: int = 0


func _ready() -> void:
    _foam = MeshInstance3D.new()
    _foam.name = "WakeFoamGeometry"
    _foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _mesh = ArrayMesh.new()
    _foam.mesh = _mesh
    var material := ShaderMaterial.new()
    material.shader = FOAM_SHADER
    _foam.material_override = material
    add_child(_foam)


func attach_vessel(target: Node3D) -> void:
    # A new vessel invalidates all prior trail history.
    clear_wake()
    vessel = target
    if is_instance_valid(target):
        _last_vessel_position = target.global_position
        _has_previous_position = true


func clear_wake() -> void:
    _samples.clear()
    _triangles = 0
    _sample_clock = 0.0
    _has_previous_position = false
    if _mesh != null:
        _mesh.clear_surfaces()


func get_sample_count() -> int:
    return _samples.size()


func get_triangle_count() -> int:
    return _triangles


func _process(delta: float) -> void:
    advance_wake(delta)


func advance_wake(delta: float) -> void:
    # May also be called explicitly by deterministic scene tests.
    if not is_finite(delta) or delta <= 0.0:
        return
    _elapsed += minf(delta, 1.0)
    _sample_clock += delta
    var interval := maxf(MIN_TICK_SEC, sample_interval)
    if _sample_clock < interval:
        return
    var elapsed_for_velocity := maxf(_sample_clock, MIN_TICK_SEC)
    _sample_clock = 0.0

    if is_instance_valid(vessel):
        var current := vessel.global_position
        if not _has_previous_position:
            _last_vessel_position = current
            _has_previous_position = true
        var motion := Vector3(
            current.x - _last_vessel_position.x,
            0.0,
            current.z - _last_vessel_position.z
        )
        var distance := motion.length()
        var speed := distance / elapsed_for_velocity
        _last_vessel_position = current
        if distance >= MIN_STEP_M and speed >= minimum_speed:
            var travel_direction := motion / distance
            var spawn := current - travel_direction * (hull_length * 0.35)
            # Position and time are visual-only. No physics or collision bodies.
            _samples.append({
                "center": Vector3(spawn.x, sea_level + 0.018, spawn.z),
                "direction": travel_direction,
                "time": _elapsed,
                "strength": clampf(speed / 5.0, 0.18, 1.0)
            })
    _prune_samples()
    _rebuild_foam_mesh()


func _prune_samples() -> void:
    var cutoff := _elapsed - maxf(1.0, trail_lifetime)
    while _samples.size() > 0 and (float(_samples[0]["time"]) < cutoff or _samples.size() > MAX_SAMPLES):
        _samples.remove_at(0)


func _rebuild_foam_mesh() -> void:
    if _mesh == null:
        return
    _mesh.clear_surfaces()
    _triangles = 0
    if _samples.size() < 2:
        return
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    var uvs := PackedVector2Array()
    var indices := PackedInt32Array()
    var lifetime := maxf(trail_lifetime, 1.0)

    for i in range(_samples.size() - 1):
        var first: Dictionary = _samples[i]
        var second: Dictionary = _samples[i + 1]
        var a: Vector3 = first["center"]
        var b: Vector3 = second["center"]
        if a.distance_squared_to(b) <= 0.000001:
            continue
        # World-anchored water trail, unlike a billboard attached to the hull.
        var dir_a: Vector3 = first["direction"]
        var dir_b: Vector3 = second["direction"]
        var right_a := Vector3(-dir_a.z, 0.0, dir_a.x)
        var right_b := Vector3(-dir_b.z, 0.0, dir_b.x)
        var age_a := clampf((_elapsed - float(first["time"])) / lifetime, 0.0, 1.0)
        var age_b := clampf((_elapsed - float(second["time"])) / lifetime, 0.0, 1.0)
        var fade_a := pow(1.0 - age_a, 1.45) * float(first["strength"])
        var fade_b := pow(1.0 - age_b, 1.45) * float(second["strength"])
        # The two widening arms form a physically suggestive Kelvin-style V.
        for side in [-1.0, 1.0]:
            var center_a: Vector3 = a + right_a * float(side) * (hull_width * 0.30 + age_a * hull_width * 1.7)
            var center_b: Vector3 = b + right_b * float(side) * (hull_width * 0.30 + age_b * hull_width * 1.7)
            var width_a := hull_width * (0.19 + age_a * 0.32)
            var width_b := hull_width * (0.19 + age_b * 0.32)
            var left_a := to_local(center_a - right_a * width_a * 0.5)
            var right_edge_a := to_local(center_a + right_a * width_a * 0.5)
            var left_b := to_local(center_b - right_b * width_b * 0.5)
            var right_edge_b := to_local(center_b + right_b * width_b * 0.5)
            var index := vertices.size()
            for vertex in [left_a, right_edge_a, left_b, right_edge_b]:
                vertices.append(vertex)
                normals.append(Vector3.UP)
            uvs.append_array([Vector2(0.0, age_a), Vector2(1.0, age_a),
                Vector2(0.0, age_b), Vector2(1.0, age_b)])
            colors.append_array([Color(1.0, 1.0, 1.0, fade_a), Color(1.0, 1.0, 1.0, fade_a),
                Color(1.0, 1.0, 1.0, fade_b), Color(1.0, 1.0, 1.0, fade_b)])
            indices.append_array([index, index + 2, index + 1,
                index + 1, index + 2, index + 3])
            _triangles += 2

    if indices.is_empty():
        return
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    _mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
