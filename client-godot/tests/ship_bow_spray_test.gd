extends SceneTree
## Behaviour/authority regression only; NO assertion of artistic parity.

var failures := 0

func check(value: bool, reason: String) -> void:
    if not value:
        failures += 1
        push_error(reason)


func _init() -> void:
    call_deferred("run")


func run() -> void:
    # Dynamic load keeps a broken effect script from preventing the test
    # harness from running and terminating nonzero.
    var effect_script: Script = load("res://scripts/ship_bow_spray_effect.gd")
    if effect_script == null or not effect_script.can_instantiate():
        push_error("Bow spray source cannot be loaded")
        quit(1)
        return
    var vessel := Node3D.new()
    vessel.name = "VisualOnlyTestShip"
    root.add_child(vessel)
    var effect = effect_script.new()
    effect.name = "BowContactTest"
    root.add_child(effect)
    await process_frame
    effect.set_process(false)
    effect.attach_vessel(vessel)
    check(effect.emitter != null, "GPU spray node required")
    check(effect.emitter.amount == effect.MAX_DROPLETS, "Particle budget must be capped")
    check(not effect.emitter.local_coords, "Particles must be world anchored")
    check(not effect.emitter.emitting, "Attachment must not spawn foam without motion")

    for i in range(10):
        effect.advance_contact(0.1)
    check(not effect.emitter.emitting, "Stationary ship must not spray")
    check(effect.get_last_speed() == 0.0, "Stationary speed must be zero")

    vessel.position.z = -0.8
    var before := vessel.transform
    effect.advance_contact(0.1)
    check(effect.emitter.emitting, "Forward vessel must spray")
    check(effect.emitter.amount <= 112, "No unbounded GPU emission")
    check(effect.emitter.amount_ratio > 0.15, "Higher speed should increase emission")
    check(effect.get_last_speed() >= 7.9, "Visual speed must derive from travel distance")
    check(before == vessel.transform, "VFX must never move vessel")
    effect.attach_vessel(vessel)
    check(not effect.emitter.emitting, "Reattaching a moving vessel must stop particle restart emissions")
    check(effect.emitter.amount_ratio == 0.0, "Reattach must clear old spray density")

    effect.advance_contact(0.1)
    check(not effect.emitter.emitting, "No motion must stop new particles")
    vessel.position.z = 0.6
    effect.advance_contact(0.1)
    check(not effect.emitter.emitting, "Reverse motion must not emit bow spray")
    vessel.position.z = -0.3
    effect.advance_contact(-0.5)
    check(not effect.emitter.emitting, "Negative time delta must be ignored")
    effect.attach_vessel(null)
    effect.advance_contact(0.1)
    check(not effect.emitter.emitting, "Disconnection must stop spray")
    check(effect.get_last_speed() == 0.0, "Disconnection must clear transient speed")
    check(effect.emitter.process_material is ParticleProcessMaterial, "Use native bounded GPU motion")
    check(effect.emitter.draw_pass_1 is QuadMesh, "Use material-backed droplet pass")
    var mesh := effect.emitter.draw_pass_1 as QuadMesh
    if mesh != null:
        check(mesh.material is ShaderMaterial, "Shader foam required")
        if mesh.material is ShaderMaterial:
            check(mesh.material.shader.code.contains("droplet"), "Fine droplet breakup must be present")
    check(effect.get_child_count() == 1, "One reusable emitter, not repeated allocated spray nodes")

    vessel.queue_free()
    effect.queue_free()
    print("Ship bow contact regressions: %s failures" % failures)
    quit(1 if failures > 0 else 0)
