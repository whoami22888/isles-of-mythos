extends SceneTree
## Pure hysteresis tests plus real scene-tree lifecycle regressions.
const MobileLod := preload("res://scripts/mobile_lod.gd")


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

    print("Mobile LOD pure + scene lifecycle regression: %d failures" % failures)
    quit(1 if failures else 0)
