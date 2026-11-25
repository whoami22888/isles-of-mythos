extends SceneTree
## Pure hysteresis tests plus real scene-tree lifecycle regressions.
const MobileLod := preload("res://scripts/mobile_lod.gd")
const LodImpostor := preload("res://scripts/lod_impostor_manager.gd")


func _init() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    var failures := 0

    # Preserve normal 45/5 hysteresis and exact-boundary behavior.
    var high := true
    high = MobileLod.next_detail_state(high, 10.0, 45.0, 5.0)
    if high != true:
        failures += 1
        push_error("Must stay high detail well within switch_distance")
    high = MobileLod.next_detail_state(high, 60.0, 45.0, 5.0)
    if high != false:
        failures += 1
        push_error("Must switch to low detail past switch_distance + hysteresis")
    high = MobileLod.next_detail_state(high, 42.0, 45.0, 5.0)
    if high != false:
        failures += 1
        push_error("Must stay low detail inside the hysteresis band")
    high = MobileLod.next_detail_state(high, 35.0, 45.0, 5.0)
    if high != true:
        failures += 1
        push_error("Must re-enter high detail once under switch_distance - hysteresis")

    # Previously permitted 10/15 configuration stranded low detail until
    # exact 0m. The bounded band must restore high at positive 5m and 1m.
    var stranded := true
    stranded = MobileLod.next_detail_state(stranded, 30.0, 10.0, 15.0)
    if stranded != false:
        failures += 1
        push_error("Invalid 10/15 band must still enter low detail at 30m")
    stranded = MobileLod.next_detail_state(stranded, 5.0, 10.0, 15.0)
    if stranded != true:
        failures += 1
        push_error("Invalid 10/15 band must restore high detail at 5m")
    stranded = MobileLod.next_detail_state(false, 1.0, 10.0, 15.0)
    if stranded != true:
        failures += 1
        push_error("Invalid 10/15 band must restore high detail at 1m")
    stranded = MobileLod.next_detail_state(false, 0.0, 10.0, 15.0)
    if stranded != true:
        failures += 1
        push_error("Invalid 10/15 band must restore high detail at 0m")

    var zero_band := true
    zero_band = MobileLod.next_detail_state(zero_band, 20.0, 20.0, 0.0)
    if zero_band != true:
        failures += 1
        push_error("Exactly at switch_distance with zero hysteresis must not switch away")
    zero_band = MobileLod.next_detail_state(zero_band, 20.01, 20.0, 0.0)
    if zero_band != false:
        failures += 1
        push_error("Just past switch_distance with zero hysteresis must switch to low detail")
    zero_band = MobileLod.next_detail_state(zero_band, 20.0, 20.0, 0.0)
    if zero_band != true:
        failures += 1
        push_error("Returning to exactly switch_distance with zero hysteresis must restore high detail")

    # Scene lifecycle: both children start visible. _ready must select
    # exactly one immediately, before any _process or rendered frame.
    var lod := MobileLod.new()
    lod.name = "LOD"
    lod.high_detail_path = NodePath("High")
    lod.low_detail_path = NodePath("Low")
    lod.camera_path = NodePath("Camera")
    lod.switch_distance = 10.0
    lod.hysteresis = 15.0
    var near_mesh := MeshInstance3D.new()
    near_mesh.name = "High"
    near_mesh.visible = true
    var far_mesh := MeshInstance3D.new()
    far_mesh.name = "Low"
    far_mesh.visible = true
    var camera := Camera3D.new()
    camera.name = "Camera"
    camera.position = Vector3(30.0, 0.0, 0.0)
    lod.add_child(near_mesh)
    lod.add_child(far_mesh)
    lod.add_child(camera)
    root.add_child(lod)
    if near_mesh.visible or not far_mesh.visible:
        failures += 1
        push_error("_ready must select low mesh exclusively at 30m before first frame")

    camera.position = Vector3(5.0, 0.0, 0.0)
    # process_frame fires before Node._process; two signals ensure one update.
    await process_frame
    await process_frame
    if not near_mesh.visible or far_mesh.visible:
        failures += 1
        push_error("Scene must recover high mesh exclusively at positive 5m")
    lod.queue_free()
    await process_frame

    # Missing camera must fail closed to one high-detail mesh and stop
    # processing rather than leaving both default-visible meshes active.
    var missing_camera := MobileLod.new()
    missing_camera.name = "MissingCameraLOD"
    missing_camera.high_detail_path = NodePath("High")
    missing_camera.low_detail_path = NodePath("Low")
    missing_camera.camera_path = NodePath("MissingCamera")
    var safe_high := MeshInstance3D.new()
    safe_high.name = "High"
    safe_high.visible = true
    var safe_low := MeshInstance3D.new()
    safe_low.name = "Low"
    safe_low.visible = true
    missing_camera.add_child(safe_high)
    missing_camera.add_child(safe_low)
    root.add_child(missing_camera)
    if not safe_high.visible or safe_low.visible or missing_camera.is_processing():
        failures += 1
        push_error("Missing camera must leave only high mesh visible and disable processing")
    missing_camera.queue_free()
    await process_frame


    # Prompt 008: exact 120/140 px hysteresis boundaries.
    if not LodImpostor.next_full_detail_state(true, 140.0):
        failures += 1
        push_error("Exactly 140 px must retain the current full-detail state")
    if LodImpostor.next_full_detail_state(false, 140.0):
        failures += 1
        push_error("Exactly 140 px must retain the current impostor state")
    if not LodImpostor.next_full_detail_state(true, 120.0):
        failures += 1
        push_error("Exactly 120 px must retain the current full-detail state")
    if LodImpostor.next_full_detail_state(false, 120.0):
        failures += 1
        push_error("Exactly 120 px must retain the current impostor state")
    if LodImpostor.next_full_detail_state(true, 119.99):
        failures += 1
        push_error("Below 120 px must enter the impostor state")
    if not LodImpostor.next_full_detail_state(false, 140.01):
        failures += 1
        push_error("Above 140 px must restore the full-detail state")

    # Octahedral directions must map into the configured row-major atlas.
    var front_frame := LodImpostor.octahedral_frame_index(Vector3(0.0, 0.0, 1.0), 8, 8)
    var right_frame := LodImpostor.octahedral_frame_index(Vector3(1.0, 0.0, 0.0), 8, 8)
    if front_frame == right_frame or front_frame < 0 or front_frame >= 64 or right_frame >= 64:
        failures += 1
        push_error("Octahedral directions must map to distinct in-range atlas frames")
    var zero_uv := LodImpostor.octahedral_uv(Vector3.ZERO)
    if zero_uv.distance_to(Vector2(0.5, 0.5)) > 0.0001:
        failures += 1
        push_error("A zero view vector must map to the stable atlas centre")

    # Real orthographic projection: 2 m bounds at 720 px viewport height
    # produce 144 px at camera size 10, then cross below 120 px at size 12.1.
    var previous_root_size := root.size
    root.size = Vector2i(1280, 720)
    var impostor_lod := LodImpostor.new()
    impostor_lod.name = "ScreenSpaceImpostorLOD"
    impostor_lod.mesh_path = NodePath("HighMesh")
    impostor_lod.impostor_path = NodePath("Impostor")
    # Empty path deliberately exercises the active viewport Camera3D.
    impostor_lod.camera_path = NodePath("")

    var impostor_mesh := MeshInstance3D.new()
    impostor_mesh.name = "HighMesh"
    var impostor_box := BoxMesh.new()
    impostor_box.size = Vector3(1.0, 2.0, 1.0)
    impostor_mesh.mesh = impostor_box
    # Non-zero offset and non-uniform scale must be preserved by the impostor.
    impostor_mesh.position = Vector3(0.0, 0.5, 0.0)
    impostor_mesh.scale = Vector3(1.5, 1.0, 0.5)

    var impostor_sprite := Sprite3D.new()
    impostor_sprite.name = "Impostor"
    var atlas_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
    atlas_image.fill(Color.WHITE)
    impostor_sprite.texture = ImageTexture.create_from_image(atlas_image)
    impostor_sprite.visible = true

    var impostor_camera := Camera3D.new()
    impostor_camera.name = "Camera"
    impostor_camera.position = Vector3(0.0, 0.0, 10.0)
    impostor_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    impostor_camera.size = 10.0
    impostor_camera.current = true

    impostor_lod.add_child(impostor_mesh)
    impostor_lod.add_child(impostor_sprite)
    impostor_lod.add_child(impostor_camera)
    root.add_child(impostor_lod)
    await process_frame
    impostor_lod._process(0.0)

    var measured_height := impostor_lod._projected_pixel_height()
    if measured_height <= 140.0:
        failures += 1
        push_error("Projected AABB height must exceed 140 px at the near orthographic zoom")

    # The sprite frame must match the source bounds, including mesh offset and scale.
    var frame_width := atlas_image.get_width() / impostor_lod.atlas_columns
    var frame_height := atlas_image.get_height() / impostor_lod.atlas_rows
    var sprite_height := impostor_sprite.pixel_size * float(frame_height)
    var sprite_width := impostor_sprite.pixel_size * float(frame_width) * impostor_sprite.scale.x
    if absf(sprite_height - 2.0) > 0.001:
        failures += 1
        push_error("Impostor frame height must match the 2 m source mesh bounds")
    if absf(sprite_width - 1.5) > 0.001:
        failures += 1
        push_error("Impostor frame width must match the 1.5 m transformed source bounds")
    if impostor_sprite.position.distance_to(Vector3(0.0, 0.5, 0.0)) > 0.001:
        failures += 1
        push_error("Impostor centre must follow the transformed source mesh bounds")

    if not impostor_mesh.visible or impostor_sprite.visible:
        failures += 1
        push_error("Initial near view must show only the full 3D mesh")

    # Directly invoke the same hot path used by the engine. Visibility must
    # swap in that call, not one frame later.
    impostor_camera.size = 12.1
    impostor_lod._process(0.0)
    if impostor_mesh.visible or not impostor_sprite.visible:
        failures += 1
        push_error("Crossing below 120 px must swap to the impostor immediately")

    var frame_before_orbit := impostor_sprite.frame
    impostor_camera.position = Vector3(10.0, 0.0, 10.0)
    impostor_lod._process(0.0)
    if impostor_sprite.frame == frame_before_orbit:
        failures += 1
        push_error("Changing the camera azimuth must select a different octahedral atlas frame")

    impostor_camera.size = 11.0
    impostor_lod._process(0.0)
    if impostor_mesh.visible or not impostor_sprite.visible:
        failures += 1
        push_error("The 120–140 px buffer must retain the current impostor state")

    impostor_camera.size = 10.0
    impostor_lod._process(0.0)
    if not impostor_mesh.visible or impostor_sprite.visible:
        failures += 1
        push_error("Crossing above 140 px must restore the 3D mesh immediately")

    # If all bounds corners are behind the camera, retain the full mesh.
    # The old zero-projected-corners path returned 0 px and incorrectly
    # switched to an impostor that can appear on the wrong side of the camera.
    impostor_camera.position = Vector3(0.0, 0.0, -10.0)
    impostor_lod._process(0.0)
    if impostor_lod._projected_pixel_height() <= 140.0 or not impostor_mesh.visible or impostor_sprite.visible:
        failures += 1
        push_error("All-behind-camera bounds must retain the full 3D mesh")

    # A camera intersecting the AABB also retains full detail until the
    # complete bounds are in front of the view plane.
    impostor_camera.position = Vector3(0.0, 0.5, 0.0)
    impostor_lod._process(0.0)
    if impostor_lod._projected_pixel_height() <= 140.0 or not impostor_mesh.visible or impostor_sprite.visible:
        failures += 1
        push_error("Camera-plane-intersecting bounds must retain the full 3D mesh")

    impostor_lod.queue_free()
    await process_frame
    root.size = previous_root_size

    # An absent atlas is not allowed to hide the only usable 3D representation.
    var missing_atlas_lod := LodImpostor.new()
    missing_atlas_lod.name = "MissingAtlasLOD"
    missing_atlas_lod.mesh_path = NodePath("HighMesh")
    missing_atlas_lod.impostor_path = NodePath("Impostor")
    var missing_atlas_mesh := MeshInstance3D.new()
    missing_atlas_mesh.name = "HighMesh"
    missing_atlas_mesh.mesh = BoxMesh.new()
    var missing_atlas_sprite := Sprite3D.new()
    missing_atlas_sprite.name = "Impostor"
    missing_atlas_sprite.visible = true
    missing_atlas_lod.add_child(missing_atlas_mesh)
    missing_atlas_lod.add_child(missing_atlas_sprite)
    root.add_child(missing_atlas_lod)
    if not missing_atlas_mesh.visible or missing_atlas_sprite.visible or missing_atlas_lod.is_processing():
        failures += 1
        push_error("Missing atlas must fail safe to the visible 3D mesh and stop processing")
    missing_atlas_lod.queue_free()
    await process_frame

    # A broken high-detail path must not leave a pre-visible impostor enabled.
    var invalid_mesh_lod := LodImpostor.new()
    invalid_mesh_lod.name = "InvalidMeshLOD"
    invalid_mesh_lod.mesh_path = NodePath("MissingMesh")
    invalid_mesh_lod.impostor_path = NodePath("Impostor")
    var invalid_mesh_sprite := Sprite3D.new()
    invalid_mesh_sprite.name = "Impostor"
    invalid_mesh_sprite.visible = true
    invalid_mesh_lod.add_child(invalid_mesh_sprite)
    root.add_child(invalid_mesh_lod)
    if invalid_mesh_sprite.visible or invalid_mesh_lod.is_processing():
        failures += 1
        push_error("Invalid mesh path must hide the impostor and stop processing")
    invalid_mesh_lod.queue_free()
    await process_frame

    print("Mobile LOD pure + scene lifecycle regression: %d failures" % failures)
    quit(1 if failures else 0)
