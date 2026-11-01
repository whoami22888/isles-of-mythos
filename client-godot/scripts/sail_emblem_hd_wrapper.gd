extends RefCounted
## Reusable, high-definition Order Cross sail-overlay material wrapper.
## Only the explicit imported sail surfaces are modified. Original glTF source,
## UV0 atlas, PBR texture bindings and base mesh remain immutable.

const SAIL_SHADER := preload("res://shaders/sail_shader.gdshader")
const CROSS_TEXTURE := preload("res://assets/emblems/order_cross_mask.svg")
const UV_MAPPER := preload("res://scripts/order_cross_uv_mapper.gd")


static func _shader_for_source(source: BaseMaterial3D, linen_grade_strength: float) -> ShaderMaterial:
	var cloth := ShaderMaterial.new()
	cloth.resource_name = "OrderCrossSail"
	cloth.shader = SAIL_SHADER
	cloth.set_shader_parameter("base_sail_tex", source.albedo_texture)
	cloth.set_shader_parameter("order_cross_emblem", CROSS_TEXTURE)
	# The imported atlas is brightened to cream without altering the PBR maps.
	cloth.set_shader_parameter("base_tint", Color.WHITE)
	cloth.set_shader_parameter("cross_color", Color(0.8, 0.1, 0.1, 1.0))
	cloth.set_shader_parameter("use_vector_cross", true)
	cloth.set_shader_parameter("emblem_scale", 1.25)
	cloth.set_shader_parameter("fabric_weave_strength", 0.02)
	cloth.set_shader_parameter("linen_grade_strength", linen_grade_strength)
	cloth.set_shader_parameter("alpha_scissor_threshold",
		maxf(0.01, source.alpha_scissor_threshold))
	cloth.set_shader_parameter("sail_roughness", source.roughness)
	cloth.set_shader_parameter("sail_metallic", source.metallic)
	if source.normal_enabled and source.normal_texture != null:
		cloth.set_shader_parameter("has_normal_map", true)
		cloth.set_shader_parameter("sail_normal_tex", source.normal_texture)
		cloth.set_shader_parameter("sail_normal_depth", source.normal_scale)
	if source.roughness_texture != null:
		cloth.set_shader_parameter("has_roughness_map", true)
		cloth.set_shader_parameter("sail_roughness_tex", source.roughness_texture)
		cloth.set_shader_parameter("roughness_channel", int(source.roughness_texture_channel))
	if source.metallic_texture != null:
		cloth.set_shader_parameter("has_metallic_map", true)
		cloth.set_shader_parameter("sail_metallic_tex", source.metallic_texture)
		cloth.set_shader_parameter("metallic_channel", int(source.metallic_texture_channel))
	if source.ao_enabled and source.ao_texture != null:
		cloth.set_shader_parameter("has_ao_map", true)
		cloth.set_shader_parameter("sail_ao_tex", source.ao_texture)
		cloth.set_shader_parameter("ao_channel", int(source.ao_texture_channel))
	return cloth


static func apply(ship_root: Node, expected_components: int = 4,
		expected_panels: int = 2, linen_grade_strength: float = 0.0) -> Dictionary:
	# Prepare all replacements before mutation; unexpected source UV islands
	# never leave a partially decorated ship.
	if ship_root == null or expected_components < 1 or expected_panels < 1 or linen_grade_strength < 0.0 or linen_grade_strength > 1.0:
		return {"error": "Invalid sail root/profile"}
	var work: Array = []
	var queue: Array[Node] = [ship_root]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null:
				var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
				for surface_index in range(mesh_instance.mesh.get_surface_count()):
					var original: Material = mesh_instance.get_active_material(surface_index)
					var is_sail := str(mesh_instance.name).to_lower().contains("sail")
					if original != null:
						is_sail = is_sail or str(original.resource_name).to_lower().contains("sail")
					if not is_sail:
						continue
					if mesh == null or mesh.get_surface_count() != 1 or surface_index != 0:
						return {"error": "Sail mesh must be a single imported ArrayMesh surface"}
					var source := original as BaseMaterial3D
					if source == null or source.albedo_texture == null:
						return {"error": "Imported PBR sail atlas missing"}
					var mapping: Dictionary = UV_MAPPER.create_mesh(
						mesh, surface_index, expected_components, expected_panels)
					if mapping.has("error"):
						return {"error": mapping["error"]}
					work.append({"node": mesh_instance, "mesh": mapping["mesh"],
						"material": _shader_for_source(source, linen_grade_strength)})
		for child in node.get_children():
			queue.append(child)
	if work.size() != 1:
		return {"error": "Expected precisely one imported sail mesh; found %d" % work.size()}
	for item in work:
		var mesh_instance: MeshInstance3D = item["node"]
		mesh_instance.mesh = item["mesh"]
		mesh_instance.set_surface_override_material(0, item["material"])
	return {"sail_surfaces": work.size(), "decorated_panels": expected_panels,
		"component_count": expected_components}
