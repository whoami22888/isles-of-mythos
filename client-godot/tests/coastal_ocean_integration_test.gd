extends SceneTree
## Source-of-truth shoreline, material, and mast-safe camera contract.
## This is a structural/integration gate, NOT owner cinematic approval.

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
        push_error("Realistic coast+ship FX scene cannot load")
        quit(1)
        return
    var scene: Node3D = packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame

    var terrain := scene.get_node_or_null("IrregularCoastalTerrain") as MeshInstance3D
    var water := scene.get_node_or_null("ShallowToDeepWater") as MeshInstance3D
    check(terrain != null and terrain.mesh != null, "Missing real 96x72 coastal mesh")
    check(water != null, "Missing terrain-aware ocean mesh")
    if water == null or terrain == null or terrain.mesh == null:
        scene.queue_free()
        quit(1)
        return
    var plane := water.mesh as PlaneMesh
    check(plane != null, "Ocean must have a vertex-displaceable plane mesh")
    if plane != null:
        check(plane.subdivide_width >= 96 and plane.subdivide_depth >= 72,
            "Ocean needs actual geometry for moving swell")
        check(plane.size.x >= 640.0 and plane.size.y >= 480.0,
            "Single ocean must cover cinematic horizon without visible quad edges")
        check(plane.subdivide_width <= 160 and plane.subdivide_depth <= 120,
            "Full-screen ocean must keep a bounded near-field vertex budget")
    check(scene.get_node_or_null("FarDeepOcean") == null,
        "Ocean must not render overlapping near/far surfaces or a shader seam")
    var material := water.material_override as ShaderMaterial
    check(material != null and material.shader != null, "Require real shader material")
    if material == null or material.shader == null:
        scene.queue_free()
        quit(1)
        return
    var shader_source: String = material.shader.code
    check(shader_source.contains("coastal_shore_sampler.gdshaderinc"), "Material must use PR #173 shoreline")
    check(shader_source.contains("shore_terrain_height("), "Depth must sample actual terrain mesh")
    check(shader_source.contains("shore_terrain_coverage("), "Foam must honour terrain coverage")
    var shoreline_source: String = FileAccess.get_file_as_string("res://shaders/coastal_shore_sampler.gdshaderinc")
    check(shoreline_source.contains("smoothstep(0.0, 0.035, uv.x)"),
        "Terrain coverage edge must feather to avoid a rectangular ocean seam")
    check(not shoreline_source.contains("return step(0.0, uv.x)"),
        "Terrain coverage must not reintroduce a hard rectangular edge")
    check(not shader_source.contains("coastal_floor_height("), "Stale copied terrain equation banned")
    check(not shader_source.contains("land_region"), "Invented rectangular shore mask banned")
    check(shader_source.contains("fresnel"), "Grazing-angle water response required")
    check(shader_source.contains("NORMAL_MAP"), "Moving water normal detail required")
    check(material.get_shader_parameter("shoremap_bound") == true, "Fail closed if shoreline unbound")
    check(material.get_shader_parameter("shore_heightmap") is Texture2D, "Texture must bind to shader")
    check(material.get_shader_parameter("shore_texture_size") == Vector2(96.0, 72.0),
        "Texture must match actual current coastal mesh")
    var binding: Dictionary = scene._shore_binding
    check(binding.has("texture") and binding.has("resolution"), "Keep one-time heightfield receipt")
    if binding.has("texture"):
        var texture: Texture2D = binding["texture"]
        var data: Image = texture.get_image()
        check(data.get_width() == 96 and data.get_height() == 72,
            "Actual shoreline grid has 96x72 samples")
        var verts: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
        for loc in [0, 35, 95, 3456, 6911]:
            check(absf(verts[loc].y - data.get_pixel(loc % 96, loc / 96).r) < 0.0001,
                "Shoreline must agree with actual rendered terrain at vertex %d" % loc)

    for child in scene.get_children():
        if child is MeshInstance3D and child.mesh is QuadMesh:
            check(false, "No detached rectangular foam strips in current coastal scene")
    var grove := scene.get_node_or_null("CoastalPBRDepthLayer")
    check(grove != null, "Only genuine sourced PBR coastal depth assets allowed")
    if grove != null:
        check(grove.get_child_count() == 6, "Four sourced trees and two rocks must ground to the real terrain")
        for child in grove.get_children():
            check(child is Node3D, "Coastal vegetation must use instantiated true 3D assets")

    var camera: Camera3D = scene.get_node_or_null("CinematicRevealCamera")
    if camera != null:
        var bounds: AABB = scene.ship_visual_bounds_world()
        check(scene._ship_bounds_ready and bounds.size.y > 0.01, "Actual ship mast bounds required")
        check(scene.frame_ship_cinematic(camera, Vector3(-7.0, 5.2, -17.0)),
            "Must frame the real imported vessel")
        for corner in range(8):
            var pt: Vector3 = bounds.position + Vector3(
                bounds.size.x if corner & 1 else 0.0,
                bounds.size.y if corner & 2 else 0.0,
                bounds.size.z if corner & 4 else 0.0
            )
            var uv: Vector2 = camera.unproject_position(pt)
            check(not camera.is_position_behind(pt), "Ship geometry is behind cinematic camera")
            check(uv.x > 32.0 and uv.x < 1248.0 and uv.y > 32.0 and uv.y < 688.0,
                "Ship full AABB must stay inside camera safe frame")
    else:
        check(false, "Cinematic camera missing")

    scene.queue_free()
    print("Terrain-aware coast and full-ship framing: %d failures" % failures)
    quit(1 if failures else 0)
