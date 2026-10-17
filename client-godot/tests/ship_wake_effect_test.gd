extends SceneTree
## Deterministic behavior / geometry contract. Not proof of visual quality or FPS.

const Wake = preload("res://scripts/ship_wake_effect.gd")
var _failures: int = 0


func _check(value: bool, description: String) -> void:
    if not value:
        push_error(description)
        _failures += 1


func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    var vessel := Node3D.new()
    vessel.name = "MockShipVisualOnly"
    root.add_child(vessel)
    var wake := Wake.new()
    wake.name = "TestShipWake"
    root.add_child(wake)
    await process_frame
    wake.set_process(false)
    wake.attach_vessel(vessel)

    _check(wake.get_triangle_count() == 0, "Stationary ship must start with no foam geometry")
    _check(wake.get_sample_count() == 0, "No samples before actual movement")
    wake.advance_wake(0.12)
    _check(wake.get_sample_count() == 0, "Stationary ship must not generate fake wakes")
    wake.advance_wake(-2.0)
    wake.advance_wake(NAN)
    _check(wake.get_sample_count() == 0, "Invalid or negative delta must be ignored")

    for i in range(16):
        vessel.position.z = -float(i + 1) * 0.7
        wake.advance_wake(0.12)
    _check(wake.get_sample_count() == 16, "Moving ship must generate world-anchored samples")
    _check(wake.get_triangle_count() == 60, "Each of 15 spans must have two paired foam arms")
    _check(wake.get_sample_count() <= wake.MAX_SAMPLES, "Wake sample bound must be enforced")
    var foam := wake.get_node_or_null("WakeFoamGeometry") as MeshInstance3D
    _check(foam != null, "Wake must build one dedicated visual mesh")
    if foam != null:
        _check(foam.mesh.get_surface_count() == 1, "Moving wake must provide triangle geometry")
        var arrays := foam.mesh.surface_get_arrays(0)
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
        _check(vertices.size() == 120, "Bounded paired wake strips require consistent vertex counts")
        _check(colors.size() == vertices.size(), "Per-vertex age must be available to shader")
        _check(foam.material_override is ShaderMaterial, "Wake must use animated foam shader")
        if foam.material_override is ShaderMaterial:
            var source: String = foam.material_override.shader.code
            _check(source.contains("wave_height"), "Foam must follow the ocean's animated swells")
            _check(source.contains("smooth_noise"), "Foam must be broken into moving detail")

    var known_pose := vessel.transform
    wake.advance_wake(0.12)
    _check(vessel.transform == known_pose, "Wake update may not alter vessel transform")
    _check(wake.get_sample_count() == 16, "Stationary vessel must not add wake samples")
    for i in range(85):
        wake.advance_wake(0.12)
    _check(wake.get_sample_count() == 0, "A stopped vessel's foam history must expire")
    _check(wake.get_triangle_count() == 0, "Expired foam must not consume mesh surfaces")

    for i in range(120):
        vessel.position.z -= 0.8
        wake.advance_wake(0.12)
    _check(wake.get_sample_count() <= wake.MAX_SAMPLES, "Long voyage must preserve bounded memory")
    _check(wake.get_triangle_count() <= (wake.MAX_SAMPLES - 1) * 4, "Long voyage must cap GPU geometry")
    wake.attach_vessel(null)
    _check(wake.get_sample_count() == 0 and wake.get_triangle_count() == 0, "Detach must clear prior ship wake")

    wake.queue_free()
    vessel.queue_free()
    print("Ship wake focused tests: %d failures" % _failures)
    quit(1 if _failures > 0 else 0)
