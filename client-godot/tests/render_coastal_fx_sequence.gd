extends SceneTree
## INTERNAL QA ONLY: capture genuine consecutive Godot renderer frames.
## This test is not proof of parity against the owner's master footage.
## No generated image is suitable for owner-facing display without review.

const FRAME_COUNT := 72
var _previous_bytes := PackedByteArray()
var _changed_frames := 0


func _init() -> void:
    call_deferred("_record")


func _fail(reason: String) -> void:
    push_error(reason)
    quit(1)


func _record() -> void:
    var directory := OS.get_environment("IOM_FX_FRAMES_DIR")
    if directory.is_empty():
        _fail("IOM_FX_FRAMES_DIR is required; no default public output")
        return
    if DirAccess.make_dir_recursive_absolute(directory) != OK:
        _fail("Could not create renderer evidence directory")
        return
    var packed: PackedScene = load("res://scenes/realistic_coastal_fx_slice.tscn")
    if packed == null:
        _fail("Could not load actual coastal ship FX scene")
        return
    var scene: Node3D = packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    await process_frame
    var integration := scene.get_node_or_null("CoastalShipEffects")
    if integration == null or not integration.components_ready():
        _fail("Real vessel + both active VFX components not bound")
        return
    scene.play_cinematic()
    if not scene.cinematic_camera.current:
        _fail("Cinematic camera not selected")
        return
    for frame_number in range(FRAME_COUNT):
        await process_frame
        await RenderingServer.frame_post_draw
        var pixels: Image = root.get_viewport().get_texture().get_image()
        if pixels == null or pixels.is_empty() or pixels.get_width() != 1280 or pixels.get_height() != 720:
            _fail("Missing 1280x720 actual engine frame at %d" % frame_number)
            return
        var current_bytes: PackedByteArray = pixels.get_data()
        if frame_number > 0 and current_bytes != _previous_bytes:
            _changed_frames += 1
        _previous_bytes = current_bytes
        if frame_number == 0:
            var basis: Color = pixels.get_pixel(0, 0)
            var variation := 0
            for pixel in [Vector2i(320, 180), Vector2i(640, 360), Vector2i(960, 540)]:
                var c: Color = pixels.get_pixel(pixel.x, pixel.y)
                if abs(c.r - basis.r) + abs(c.g - basis.g) + abs(c.b - basis.b) > 0.09:
                    variation += 1
            if variation < 2:
                _fail("First captured engine frame is uniform or blank")
                return
        var frame_path := "%s/frame_%04d.png" % [directory, frame_number]
        if pixels.save_png(frame_path) != OK:
            _fail("Unable to write actual Godot frame %d" % frame_number)
            return
    if _changed_frames < 12:
        _fail("Frame sequence is effectively static; no valid moving-engine evidence")
        return
    if not integration._demo_active:
        _fail("Ship movement stopped unexpectedly during cinematic capture")
        return
    if integration.wake.get_sample_count() < 2:
        _fail("No real wake geometry accumulated in the captured moving ship scene")
        return
    scene.skip_cinematic()
    await process_frame
    if integration._demo_active or not scene.gameplay_camera.current:
        _fail("Cinematic capture failed to restore the gameplay camera and vessel")
        return
    print("Genuine Godot cinematic FX frames: %d, changed: %d, camera restored" % [
        FRAME_COUNT, _changed_frames
    ])
    scene.queue_free()
    quit(0)
