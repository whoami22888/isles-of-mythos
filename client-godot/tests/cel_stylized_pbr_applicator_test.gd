extends SceneTree
## Structural regression for Prompt 005 cel-material application. No Vulkan required.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := 0
	var applicator := preload("res://scripts/cel_stylized_pbr_applicator.gd")

	var opaque := StandardMaterial3D.new()
	opaque.albedo_color = Color(0.55, 0.32, 0.18)
	opaque.roughness = 0.7
	var albedo := ImageTexture.create_from_image(_solid_image(Color(0.4, 0.25, 0.15)))
	albedo.resource_path = "res://_test_hull_diff.png"
	opaque.albedo_texture = albedo

	var mesh := BoxMesh.new()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.set_surface_override_material(0, opaque)
	root.add_child(instance)

	var converted := applicator.apply_to_mesh(instance, false)
	if converted != 1:
		push_error("Opaque hull material must convert to the cel shader, got %s" % converted)
		failures += 1
	var applied := instance.get_surface_override_material(0) as ShaderMaterial
	if applied == null or applied.shader != applicator.DESKTOP_SHADER:
		push_error("Converted material must use the desktop cel shader")
		failures += 1
	elif applied.get_shader_parameter("use_albedo_texture") != true:
		push_error("Converted material must keep the source albedo texture")
		failures += 1

	var sail := StandardMaterial3D.new()
	sail.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var sail_tex := ImageTexture.create_from_image(_solid_image(Color(0.95, 0.95, 0.9, 0.4)))
	sail_tex.resource_path = "res://_test_sails_rgba.png"
	sail.albedo_texture = sail_tex
	var sail_instance := MeshInstance3D.new()
	sail_instance.mesh = BoxMesh.new()
	sail_instance.set_surface_override_material(0, sail)
	root.add_child(sail_instance)
	if applicator.apply_to_mesh(sail_instance, false) != 0:
		push_error("Alpha-tested sail materials must be left untouched")
		failures += 1
	if sail_instance.get_surface_override_material(0) != sail:
		push_error("Sail material must remain the original StandardMaterial3D")
		failures += 1

	var water := ShaderMaterial.new()
	water.shader = load("res://shaders/ocean_surface.gdshader") as Shader
	var water_instance := MeshInstance3D.new()
	water_instance.mesh = PlaneMesh.new()
	water_instance.set_surface_override_material(0, water)
	root.add_child(water_instance)
	if applicator.apply_to_mesh(water_instance, false) != 0:
		push_error("Ocean surface materials must be left untouched")
		failures += 1

	instance.queue_free()
	sail_instance.queue_free()
	water_instance.queue_free()
	print("Prompt 005 cel applicator: %s failures" % failures)
	quit(1 if failures else 0)


func _solid_image(color: Color) -> Image:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image
