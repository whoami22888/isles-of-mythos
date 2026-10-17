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
    # The CI llvmpipe renderer may take ~0.5 s per frame. A wall-clock
    # cinematic tween then finishes before even 10 frames are captured.
    # Use a true in-engine fixed simulation step for ship/camera poses, not a
    # static-image pan or AI-generated substitute. Each screenshot still
    # comes directly from Godot's actual renderer.
    scene.set_cinematic_view()
    scene.set_process(false)
    integration.set_process(false)
    integration.wake.set_process(false)
    integration.bow_spray.set_process(false)
    integration.start_visual_demo()
    var camera_start: Vector3 = scene.cinematic_camera.position
    var waypoint_a := Vector3(-7.0, 4.8, -17.0)
    var waypoint_b := Vector3(-2.5, 5.2, -21.0)
    if not scene.cinematic_camera.current:
        _fail("Cinematic camera not selected")
        return
    var render_start_msec: int = Time.get_ticks_msec()
    for frame_number in range(FRAME_COUNT):
        var progress := float(frame_number) / float(FRAME_COUNT - 1)
        if progress < 0.5:
            var stage := smoothstep(0.0, 1.0, progress * 2.0)
            scene.cinematic_camera.position = camera_start.lerp(waypoint_a, stage)
        else:
            var stage := smoothstep(0.0, 1.0, (progress - 0.5) * 2.0)
            scene.cinematic_camera.position = waypoint_a.lerp(waypoint_b, stage)
        integration.advance_visual_demo(1.0 / 24.0)
        if not scene.frame_ship_cinematic(scene.cinematic_camera, scene.cinematic_camera.global_position):
            _fail("Imported ship has no valid full 3D visual bounds")
            return
        # Fail if ANY ship hull, mast, sail, or rigging bound leaves frame.
        # A hull centre in view is explicitly not enough for this gate.
        var bounds: AABB = scene.ship_visual_bounds_world()
        for corner in range(8):
            var point := bounds.position + Vector3(
                bounds.size.x if corner & 1 else 0.0,
                bounds.size.y if corner & 2 else 0.0,
                bounds.size.z if corner & 4 else 0.0
            )
            if scene.cinematic_camera.is_position_behind(point):
                _fail("Ship bounds behind camera at frame %d corner %d" % [frame_number, corner])
                return
            var projected: Vector2 = scene.cinematic_camera.unproject_position(point)
            if projected.x < 36.0 or projected.x > 1244.0 or projected.y < 36.0 or projected.y > 684.0:
                _fail("Ship rigging/hull clips frame at %d corner %d: %s" % [frame_number, corner, projected])
                return
        await process_frame
        await RenderingServer.frame_post_draw
        var pixels: Image = root.get_viewport().get_texture().get_image()
        if pixels == null or pixels.is_empty() or pixels.get_width() != 1280 or pixels.get_height() != 720:
            _fail("Missing 1280x720 actual engine frame at %d" % frame_number)
            return
        # Lossless RGBA8 capture avoids synchronous PNG compression during
        # the 240-second CPU software-renderer watchdog. Encode after exit.
        if pixels.get_format() != Image.FORMAT_RGBA8:
            pixels.convert(Image.FORMAT_RGBA8)
        var current_bytes: PackedByteArray = pixels.get_data()
        if current_bytes.size() != 1280 * 720 * 4:
            _fail("Invalid RGBA8 capture byte count at frame %d" % frame_number)
            return
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
        var frame_path := "%s/frame_%04d.rgba" % [directory, frame_number]
        var frame_file := FileAccess.open(frame_path, FileAccess.WRITE)
        if frame_file == null:
            _fail("Unable to open lossless Godot frame %d" % frame_number)
            return
        frame_file.store_buffer(current_bytes)
        frame_file.close()
        if frame_number % 6 == 0:
            print("IOM_INTERNAL_CAPTURE_FRAME %d/%d elapsed_ms=%d" % [
                frame_number + 1, FRAME_COUNT, Time.get_ticks_msec() - render_start_msec
            ])
    if _changed_frames < 12:
        _fail("Frame sequence is effectively static; no valid moving-engine evidence")
        return
    if not integration._demo_active:
        _fail("Ship movement stopped unexpectedly during cinematic capture")
        return
    if integration.wake.get_sample_count() < 2:
        _fail("No real wake geometry accumulated in the captured moving ship scene")
        return
    integration.stop_visual_demo()
    scene.set_gameplay_view()
    await process_frame
    if integration._demo_active or not scene.gameplay_camera.current:
        _fail("Cinematic capture failed to restore the gameplay camera and vessel")
        return
    print("Genuine Godot cinematic FX frames: %d, changed: %d, camera restored" % [
        FRAME_COUNT, _changed_frames
    ])
    scene.queue_free()
    quit(0)
