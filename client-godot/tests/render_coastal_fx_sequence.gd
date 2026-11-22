extends SceneTree
## INTERNAL QA ONLY: capture genuine consecutive Godot renderer frames.
## This test is not proof of parity against the owner's master footage.
## No generated image is suitable for owner-facing display without review.

const FRAME_COUNT := 72
const SOURCE_ASSET_MANIFEST := "res://assets/external-assets.json"
const SOURCE_ASSET_ROOT := "res://assets/external"
var _previous_bytes := PackedByteArray()
var _changed_frames := 0


func _init() -> void:
    call_deferred("_record")


func _fail(reason: String) -> void:
    push_error(reason)
    quit(1)


func _write_source_asset_provenance(directory: String) -> bool:
    if not FileAccess.file_exists(SOURCE_ASSET_MANIFEST):
        _fail("Missing source asset manifest: " + SOURCE_ASSET_MANIFEST)
        return false
    var source_manifest_text := FileAccess.get_file_as_string(SOURCE_ASSET_MANIFEST)
    if source_manifest_text.is_empty():
        _fail("Source asset manifest is empty")
        return false
    var parsed: Variant = JSON.parse_string(source_manifest_text)
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("Source asset manifest is not a JSON object")
        return false
    var manifest: Dictionary = parsed
    if int(manifest.get("schema_version", -1)) != 1:
        _fail("Unsupported source asset manifest schema")
        return false
    var assets_value: Variant = manifest.get("assets", null)
    if typeof(assets_value) != TYPE_ARRAY:
        _fail("Source asset manifest has no assets array")
        return false
    var assets: Array = assets_value
    if assets.is_empty():
        _fail("Source asset manifest has no assets")
        return false

    var seen_paths: Dictionary = {}
    var checksum_lines: Array[String] = []
    for entry_value in assets:
        if typeof(entry_value) != TYPE_DICTIONARY:
            _fail("Source asset manifest contains a non-object entry")
            return false
        var entry: Dictionary = entry_value
        var relative_path := str(entry.get("path", "")).strip_edges()
        var expected_sha := str(entry.get("sha256", "")).to_lower()
        var source_url := str(entry.get("source_url", "")).strip_edges()
        var license_id := str(entry.get("license", "")).strip_edges()
        var license_url := str(entry.get("license_url", "")).strip_edges()
        if relative_path.is_empty() or relative_path.begins_with("/") or relative_path.contains("\\"):
            _fail("Unsafe source asset path in manifest: " + relative_path)
            return false
        var path_parts := relative_path.split("/")
        if path_parts.has("..") or path_parts.has("") or expected_sha.length() != 64:
            _fail("Invalid source asset path or SHA-256: " + relative_path)
            return false
        if source_url.is_empty() or license_id.is_empty() or license_url.is_empty():
            _fail("Missing source or licence metadata for: " + relative_path)
            return false
        if seen_paths.has(relative_path):
            _fail("Duplicate source asset path: " + relative_path)
            return false
        seen_paths[relative_path] = true
        var source_path := SOURCE_ASSET_ROOT.path_join(relative_path)
        if not FileAccess.file_exists(source_path):
            _fail("Missing source asset file: " + source_path)
            return false
        var actual_sha := FileAccess.get_sha256(source_path).to_lower()
        if actual_sha != expected_sha:
            _fail("Source asset SHA-256 mismatch for %s expected=%s actual=%s" % [
                relative_path, expected_sha, actual_sha
            ])
            return false
        checksum_lines.append("%s  %s" % [actual_sha, relative_path])

    checksum_lines.sort()
    var checksum_path := directory.path_join("ASSET-SHA256SUMS")
    var checksum_file := FileAccess.open(checksum_path, FileAccess.WRITE)
    if checksum_file == null:
        _fail("Could not write ASSET-SHA256SUMS")
        return false
    checksum_file.store_string("\n".join(checksum_lines) + "\n")
    checksum_file.close()

    var provenance_path := directory.path_join("ASSET-PROVENANCE.json")
    var provenance_file := FileAccess.open(provenance_path, FileAccess.WRITE)
    if provenance_file == null:
        _fail("Could not write ASSET-PROVENANCE.json")
        return false
    provenance_file.store_string(source_manifest_text)
    provenance_file.close()

    var source_manifest_sha := FileAccess.get_sha256(SOURCE_ASSET_MANIFEST).to_lower()
    var copied_manifest_sha := FileAccess.get_sha256(provenance_path).to_lower()
    var checksum_manifest_sha := FileAccess.get_sha256(checksum_path).to_lower()
    if source_manifest_sha.length() != 64 or copied_manifest_sha != source_manifest_sha or checksum_manifest_sha.length() != 64:
        _fail("Source asset provenance manifest checksum verification failed")
        return false
    print("IOM_INTERNAL_ASSET_PROVENANCE source_manifest_sha256=%s copied_manifest_sha256=%s checksums_sha256=%s entries=%d" % [
        source_manifest_sha, copied_manifest_sha, checksum_manifest_sha, checksum_lines.size()
    ])
    return true


func _record() -> void:
    var directory := OS.get_environment("IOM_FX_FRAMES_DIR")
    if directory.is_empty():
        _fail("IOM_FX_FRAMES_DIR is required; no default public output")
        return
    if DirAccess.make_dir_recursive_absolute(directory) != OK:
        _fail("Could not create renderer evidence directory")
        return
    var rendering_method := RenderingServer.get_current_rendering_method()
    var rendering_driver := RenderingServer.get_current_rendering_driver_name()
    if rendering_method != "mobile" or rendering_driver != "vulkan":
        _fail(
            "Expected Vulkan Mobile renderer, got driver=%s method=%s"
            % [rendering_driver, rendering_method]
        )
        return
    print("IOM_INTERNAL_RENDERER driver=%s method=%s" % [rendering_driver, rendering_method])
    if not _write_source_asset_provenance(directory):
        return
    var start_frame := int(OS.get_environment("IOM_FX_START_FRAME")) if OS.has_environment("IOM_FX_START_FRAME") else 0
    var end_frame := int(OS.get_environment("IOM_FX_END_FRAME")) if OS.has_environment("IOM_FX_END_FRAME") else FRAME_COUNT
    if start_frame != 0 or end_frame != FRAME_COUNT:
        _fail("Capture must use one renderer process for the complete 0..71 sequence; partitioned workers reset lighting state")
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
    var ocean := scene.get_node_or_null("ShallowToDeepWater") as MeshInstance3D
    if ocean == null or not (ocean.material_override is ShaderMaterial):
        _fail("Deterministic capture requires a bound ocean ShaderMaterial")
        return
    var ocean_material := ocean.material_override as ShaderMaterial
    ocean_material.set_shader_parameter("deterministic_capture", true)
    scene.set_cinematic_view()
    scene.set_process(false)
    integration.set_process(false)
    integration.wake.set_process(false)
    integration.bow_spray.set_process(false)
    integration.wake.sync_ocean_wave_parameters(ocean_material)
    integration.wake.set_deterministic_capture(true, 0.0)
    integration.start_visual_demo()
    var scene_triangles := 0
    var mesh_instances := 0
    for node in scene.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh == null:
            continue
        mesh_instances += 1
        for surface_index in range(mesh_instance.mesh.get_surface_count()):
            var indices: PackedInt32Array = mesh_instance.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX]
            scene_triangles += indices.size() / 3
    print("IOM_INTERNAL_SCENE_GEOMETRY mesh_instances=%d triangles=%d" % [mesh_instances, scene_triangles])
    # Side/rear view: the vessel moves seaward along -Z, so its world-anchored
    # wake trails back toward this camera instead of disappearing behind the hull.
    scene.cinematic_camera.position = Vector3(-15.0, 5.5, -5.8)
    var camera_start: Vector3 = scene.cinematic_camera.position
    var waypoint_a := Vector3(-17.0, 6.0, -5.8)
    var waypoint_b := Vector3(-13.0, 5.2, -5.8)
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
        var capture_time := float(frame_number) / 24.0
        ocean_material.set_shader_parameter("capture_time_seconds", capture_time)
        integration.advance_visual_demo(1.0 / 24.0)
        integration.wake.set_capture_time(capture_time)
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
        if frame_number == 0:
            # Keep all 72 frames in this renderer process. Separate worker
            # processes rebuilt camera-dependent directional shadow state and
            # caused measurable lighting jumps at frames 23->24 and 47->48.
            # Warm the one renderer before recording; do not partition capture.
            for _warmup in range(3):
                await process_frame
                await RenderingServer.frame_post_draw
        var fence_start_msec := Time.get_ticks_msec()
        print("IOM_INTERNAL_CAPTURE_BEGIN frame=%d state_ms=%d" % [
            frame_number, Time.get_ticks_msec() - render_start_msec
        ])
        await process_frame
        await RenderingServer.frame_post_draw
        var fence_elapsed_msec := Time.get_ticks_msec() - fence_start_msec
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
            # Static land at this camera angle is a stable lighting probe.
            # A dark worker measured 82-85 luma here; lit runs measure 94+.
            # Fail that worker before it uploads a visually invalid segment.
            var land_luma := 0.0
            var land_samples := 0
            for y in range(330, 470, 4):
                for x in range(830, 1190, 4):
                    var land_pixel := pixels.get_pixel(x, y)
                    land_luma += (54.0 * land_pixel.r + 183.0 * land_pixel.g + 19.0 * land_pixel.b) / 256.0
                    land_samples += 1
            land_luma = land_luma * 255.0 / float(land_samples)
            print("IOM_INTERNAL_LAND_LUMA frame=%d luma=%.2f" % [frame_number, land_luma])
            if land_luma < 90.0:
                _fail("Underlit Mobile renderer at partition start %d: land luma %.2f" % [frame_number, land_luma])
                return
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
            print("IOM_INTERNAL_CAPTURE_FRAME %d/%d elapsed_ms=%d fence_ms=%d" % [
                frame_number + 1, FRAME_COUNT, Time.get_ticks_msec() - render_start_msec,
                fence_elapsed_msec
            ])
    if _changed_frames < mini(12, FRAME_COUNT - 1):
        _fail("Frame sequence is effectively static; no valid moving-engine evidence")
        return
    if not integration._demo_active:
        _fail("Ship movement stopped unexpectedly during cinematic capture")
        return
    if integration.wake.get_sample_count() < 2:
        _fail("No real wake geometry accumulated in the captured moving ship scene")
        return
    if integration.wake.get_triangle_count() < 8:
        _fail("Wake samples did not produce visible ribbon geometry")
        return
    integration.stop_visual_demo()
    scene.set_gameplay_view()
    await process_frame
    if integration._demo_active or not scene.gameplay_camera.current:
        _fail("Cinematic capture failed to restore the gameplay camera and vessel")
        return
    print("Genuine Godot cinematic FX frames: 0-%d, changed: %d, camera restored" % [
        FRAME_COUNT - 1, _changed_frames
    ])
    scene.queue_free()
    quit(0)
