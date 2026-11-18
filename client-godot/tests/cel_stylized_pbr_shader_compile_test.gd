extends SceneTree
## Infrastructure-only shader smoke test: require the actual Vulkan Mobile renderer.

const TEST_SCENE_PATH := "res://tests/cel_stylized_pbr_shader_test.tscn"
const DESKTOP_SHADER_PATH := "res://shaders/cel_stylized_pbr.gdshader"
const MOBILE_SHADER_PATH := "res://shaders/cel_stylized_pbr_mobile.gdshader"
const SHARED_INCLUDE_PATH := "res://shaders/cel_stylized_pbr_shared.gdshaderinc"
const DEFAULT_CAPTURE_PATH := "user://cel-stylized-pbr-vulkan-mobile.png"


func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    var rendering_method := RenderingServer.get_current_rendering_method()
    var rendering_driver := RenderingServer.get_current_rendering_driver_name()
    if rendering_method != "mobile" or rendering_driver != "vulkan":
        push_error(
            "Expected Vulkan Mobile renderer, got driver=%s method=%s"
            % [rendering_driver, rendering_method]
        )
        quit(1)
        return

    var shared_source := FileAccess.get_file_as_string(SHARED_INCLUDE_PATH)
    if not shared_source.contains("void light()") or not shared_source.contains("IOM_CEL_MOBILE_VERTEX_RAMP"):
        push_error("Shared shader include must retain the desktop light() and mobile ramp paths")
        quit(1)
        return

    var desktop_shader := load(DESKTOP_SHADER_PATH) as Shader
    var mobile_shader := load(MOBILE_SHADER_PATH) as Shader
    if desktop_shader == null or mobile_shader == null:
        push_error("Both desktop and mobile Prompt 005 shader variants must load")
        quit(1)
        return
    var mobile_shader_source := FileAccess.get_file_as_string(MOBILE_SHADER_PATH)
    if not mobile_shader_source.contains("vertex_lighting"):
        push_error("Mobile shader variant must explicitly exercise vertex_lighting")
        quit(1)
        return

    var packed_scene: PackedScene = load(TEST_SCENE_PATH)
    if packed_scene == null:
        push_error("Could not load Prompt 005 shader test scene: %s" % TEST_SCENE_PATH)
        quit(1)
        return

    var scene := packed_scene.instantiate() as Node3D
    if scene == null:
        push_error("Prompt 005 shader test scene root is not Node3D")
        quit(1)
        return

    var mobile_mesh := scene.get_node_or_null("MobileMesh") as MeshInstance3D
    var desktop_mesh := scene.get_node_or_null("DesktopMesh") as MeshInstance3D
    if mobile_mesh == null or desktop_mesh == null:
        push_error("Prompt 005 scene must include both mobile and desktop shader meshes")
        quit(1)
        return

    var mobile_material := mobile_mesh.material_override as ShaderMaterial
    var desktop_material := desktop_mesh.material_override as ShaderMaterial
    if mobile_material == null or mobile_material.shader != mobile_shader:
        push_error("Mobile test mesh must use the explicit vertex_lighting shader variant")
        quit(1)
        return
    if desktop_material == null or desktop_material.shader != desktop_shader:
        push_error("Desktop test mesh must use the per-light shader variant")
        quit(1)
        return

    root.add_child(scene)
    mobile_material.set_shader_parameter("mobile_ramp_strength", 1.0)
    mobile_material.set_shader_parameter("mobile_key_light_color", Vector3.ONE)
    mobile_material.set_shader_parameter("mobile_key_light_direction", Vector3(0.0, 0.0, 1.0))
    for frame_index in range(4):
        await process_frame
    await RenderingServer.frame_post_draw

    var front_image: Image = root.get_viewport().get_texture().get_image()
    if front_image == null or front_image.is_empty() or front_image.get_width() < 64 or front_image.get_height() < 64:
        push_error("Vulkan Mobile did not produce a usable Prompt 005 front-ramp frame")
        scene.queue_free()
        quit(1)
        return

    var sample_position := Vector2i(front_image.get_width() / 2, front_image.get_height() / 2)
    var front_pixel := front_image.get_pixel(sample_position.x, sample_position.y)
    mobile_material.set_shader_parameter("mobile_key_light_direction", Vector3(0.0, 0.0, -1.0))
    for frame_index in range(2):
        await process_frame
    await RenderingServer.frame_post_draw

    var back_image: Image = root.get_viewport().get_texture().get_image()
    if back_image == null or back_image.is_empty():
        push_error("Vulkan Mobile did not produce the Prompt 005 reverse-ramp frame")
        scene.queue_free()
        quit(1)
        return

    var back_pixel := back_image.get_pixel(sample_position.x, sample_position.y)
    var ramp_delta := Vector3(front_pixel.r, front_pixel.g, front_pixel.b).distance_to(
        Vector3(back_pixel.r, back_pixel.g, back_pixel.b)
    )
    if ramp_delta < 0.05:
        push_error(
            "Mobile vertex-lighting ramp did not respond to key-light direction (delta=%f)"
            % ramp_delta
        )
        scene.queue_free()
        quit(1)
        return

    var first_pixel := back_image.get_pixel(0, 0)
    var first_vector := Vector4(first_pixel.r, first_pixel.g, first_pixel.b, first_pixel.a)
    var sample_positions: Array[Vector2i] = [
        Vector2i(back_image.get_width() / 4, back_image.get_height() / 4),
        Vector2i(back_image.get_width() / 2, back_image.get_height() / 2),
        Vector2i(back_image.get_width() * 3 / 4, back_image.get_height() * 3 / 4),
    ]
    var varied_samples := 0
    for sample in sample_positions:
        var sample_pixel := back_image.get_pixel(sample.x, sample.y)
        var sample_vector := Vector4(
            sample_pixel.r,
            sample_pixel.g,
            sample_pixel.b,
            sample_pixel.a
        )
        if sample_vector.distance_to(first_vector) > 0.03:
            varied_samples += 1

    if varied_samples < 2:
        push_error("Vulkan Mobile Prompt 005 frame is uniform or blank")
        scene.queue_free()
        quit(1)
        return

    var capture_path := OS.get_environment("IOM_SHADER_CAPTURE_PATH")
    if capture_path.is_empty():
        capture_path = DEFAULT_CAPTURE_PATH
    var save_error := back_image.save_png(capture_path)
    if save_error != OK:
        push_error("Could not save internal Vulkan Mobile shader frame: %d" % save_error)
        scene.queue_free()
        quit(1)
        return

    print(
        "PROMPT005_VULKAN_MOBILE_RENDER=PASS driver=%s method=%s size=%dx%d ramp_delta=%f capture=%s"
        % [
            rendering_driver,
            rendering_method,
            back_image.get_width(),
            back_image.get_height(),
            ramp_delta,
            capture_path,
        ]
    )
    scene.queue_free()
    quit(0)
