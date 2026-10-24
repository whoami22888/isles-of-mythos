extends SceneTree
## Real Godot scene/component integration. Structural/behavioural acceptance
## only: this is NOT a cinematic quality or phone FPS assertion.

var failures := 0


func check(value: bool, reason: String) -> void:
    if not value:
        failures += 1
        push_error(reason)


func _init() -> void:
    call_deferred("run")


func run() -> void:
    var packed: PackedScene = load("res://scenes/realistic_coastal_fx_slice.tscn")
    if packed == null:
        push_error("Coastal ship-water integration scene failed to load")
        quit(1)
        return
    var scene: Node3D = packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    var vessel := scene.get_node_or_null("HarbourShipFocalPoint") as Node3D
    var controller := scene.get_node_or_null("CoastalShipEffects")
    check(vessel != null, "Integration must bind the actual admitted PBR ship")
    check(controller != null, "Inherited coastal scene must contain FX controller")
    if vessel == null or controller == null:
        scene.queue_free()
        quit(1)
        return
    check(controller.components_ready(), "Wake and bow GPU effects must both attach")
    var wake: ShipWakeEffect = controller.wake
    var bow: ShipBowSprayEffect = controller.bow_spray
    check(wake != null and bow != null, "Both real effects required")
    if wake == null or bow == null:
        scene.queue_free()
        quit(1)
        return
    check(not bow.emitter.emitting, "Stationary scene must not flash bow spray")
    check(wake.get_sample_count() == 0, "Stationary scene must not fake a wake")
    check(scene.get_node_or_null("ShallowToDeepWater") != null, "Real coastline/water retained")
    check(scene.get_node_or_null("GameplayCamera") != null, "Gameplay camera retained")
    check(scene.get_node_or_null("CinematicRevealCamera") != null, "Cinematic camera retained")

    # Disable automatic ticks and test explicit visual movement independently.
    scene.set_process(false)
    controller.set_process(false)
    wake.set_process(false)
    bow.set_process(false)
    var start := vessel.position
    controller.start_visual_demo()
    for i in range(16):
        controller.advance_visual_demo(0.12)
    check(vessel.position.z < start.z - 4.0, "Demo must visibly move the real ship across water")
    check(wake.get_sample_count() >= 12, "Travel must produce a persistent V-shaped wake")
    check(wake.get_triangle_count() >= 40, "Wake needs actual 3D triangle geometry")
    check(bow.emitter.emitting, "Forward motion must produce animated GPU bow spray")
    check(wake.get_triangle_count() <= (wake.MAX_SAMPLES - 1) * 4, "Wake geometry must be bounded")
    check(bow.emitter.amount <= bow.MAX_DROPLETS, "Spray GPU particle count must be bounded")
    controller.stop_visual_demo()
    check(not bow.emitter.emitting, "Stopping demo must stop spray immediately")
    check(wake.get_sample_count() == 0, "Stopping demo must clear expired trail")
    check(is_equal_approx(vessel.position.x, start.x) and is_equal_approx(vessel.position.z, start.z),
        "Stopping/skip must restore preview vessel position without teleport foam")

    # Camera skip and reduced motion must leave ordinary gameplay readable.
    scene.play_cinematic()
    check(scene.cinematic_camera.current, "Full motion selects cinematic camera")
    controller._process(0.12)
    check(controller._demo_active, "Cinematic sequence must activate ship movement")
    scene.skip_cinematic()
    controller._process(0.12)
    check(scene.gameplay_camera.current and not controller._demo_active, "Skip restores gameplay and stops VFX movement")
    check(not bow.emitter.emitting, "Skip cannot leak spray into the gameplay camera")
    scene.play_cinematic(true)
    controller._process(0.12)
    check(scene.gameplay_camera.current and not controller._demo_active,
        "Reduced-motion route must skip VFX movement")

    scene.queue_free()
    print("Coastal ship-water integration: %d failures" % failures)
    quit(1 if failures else 0)
