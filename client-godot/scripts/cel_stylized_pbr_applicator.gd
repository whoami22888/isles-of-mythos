extends RefCounted
class_name CelStylizedPbrApplicator
## Opt-in conversion of opaque imported materials onto the Prompt 005 cel shader.
## Water, particle FX, and alpha-tested sails/leaves stay on their existing materials.

const DESKTOP_SHADER := preload("res://shaders/cel_stylized_pbr.gdshader")
const MOBILE_SHADER := preload("res://shaders/cel_stylized_pbr_mobile.gdshader")

const SKIP_SHADER_HINTS := [
	"ocean_surface",
	"coastal_terrain_surface",
	"coastal_shore",
	"ship_wake",
	"ship_bow",
	"naval_cannon",
	"naval_wood",
]


static func apply_to_tree(root: Node, use_mobile: bool = false) -> int:
	var converted := 0
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_back() as Node
		if node is MeshInstance3D:
			converted += apply_to_mesh(node as MeshInstance3D, use_mobile)
		for child in node.get_children():
			var next_node: Node = child
			queue.append(next_node)
	return converted


static func apply_to_mesh(mesh_instance: MeshInstance3D, use_mobile: bool = false) -> int:
	if mesh_instance.mesh == null:
		return 0
	var converted := 0
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var source: Material = mesh_instance.get_active_material(surface_index)
		if source == null or _should_skip(source):
			continue
		mesh_instance.set_surface_override_material(surface_index, make_cel_material(source, use_mobile))
		converted += 1
	return converted


static func make_cel_material(source: Material, use_mobile: bool = false) -> ShaderMaterial:
	var cel := ShaderMaterial.new()
	cel.shader = MOBILE_SHADER if use_mobile else DESKTOP_SHADER
	cel.set_shader_parameter("base_color", Color.WHITE)
	cel.set_shader_parameter("metallic", 0.05)
	cel.set_shader_parameter("roughness", 0.6)
	cel.set_shader_parameter("use_albedo_texture", false)
	cel.set_shader_parameter("use_normal_texture", false)
	cel.set_shader_parameter("use_roughness_texture", false)
	cel.set_shader_parameter("use_triplanar", false)
	if source is StandardMaterial3D:
		var standard := source as StandardMaterial3D
		cel.set_shader_parameter("base_color", standard.albedo_color)
		cel.set_shader_parameter("metallic", standard.metallic)
		cel.set_shader_parameter("roughness", standard.roughness)
		if standard.albedo_texture != null:
			cel.set_shader_parameter("albedo_texture", standard.albedo_texture)
			cel.set_shader_parameter("use_albedo_texture", true)
		if standard.normal_texture != null or standard.normal_enabled:
			if standard.normal_texture != null:
				cel.set_shader_parameter("normal_texture", standard.normal_texture)
				cel.set_shader_parameter("use_normal_texture", true)
		if standard.roughness_texture != null:
			cel.set_shader_parameter("roughness_texture", standard.roughness_texture)
			cel.set_shader_parameter("use_roughness_texture", true)
	elif source is ShaderMaterial:
		var shader_material := source as ShaderMaterial
		_copy_shader_texture(shader_material, cel, ["albedo_texture", "texture_albedo"])
		_copy_shader_texture(shader_material, cel, ["normal_texture", "texture_normal"])
		_copy_shader_texture(shader_material, cel, ["roughness_texture", "texture_roughness"])
		var base_color: Variant = _first_shader_param(shader_material, ["base_color", "albedo_color"])
		if base_color is Color:
			cel.set_shader_parameter("base_color", base_color)
		var roughness: Variant = _first_shader_param(shader_material, ["roughness"])
		if roughness is float:
			cel.set_shader_parameter("roughness", roughness)
		var metallic: Variant = _first_shader_param(shader_material, ["metallic"])
		if metallic is float:
			cel.set_shader_parameter("metallic", metallic)
	if use_mobile:
		cel.set_shader_parameter("mobile_ramp_strength", 1.0)
		cel.set_shader_parameter("mobile_key_light_color", Vector3.ONE)
		cel.set_shader_parameter("mobile_key_light_direction", Vector3(0.35, 0.82, 0.45))
	return cel


static func _should_skip(material: Material) -> bool:
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		if shader != null:
			var path := str(shader.resource_path).to_lower()
			for hint in SKIP_SHADER_HINTS:
				if path.contains(hint):
					return true
			if shader == DESKTOP_SHADER or shader == MOBILE_SHADER:
				return true
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		if standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
		if standard.albedo_texture != null and (
			str(standard.albedo_texture.resource_path).to_lower().contains("sail")
			or str(standard.albedo_texture.resource_path).to_lower().contains("leaves")
		):
			return true
	var material_path := str(material.resource_path).to_lower()
	if material_path.contains("sail") or material_path.contains("leaves"):
		return true
	return false


static func _copy_shader_texture(source: ShaderMaterial, dest: ShaderMaterial, names: Array[String]) -> void:
	for name in names:
		var value: Variant = source.get_shader_parameter(name)
		if value is Texture2D:
			if name.contains("normal"):
				dest.set_shader_parameter("normal_texture", value)
				dest.set_shader_parameter("use_normal_texture", true)
			elif name.contains("rough"):
				dest.set_shader_parameter("roughness_texture", value)
				dest.set_shader_parameter("use_roughness_texture", true)
			else:
				dest.set_shader_parameter("albedo_texture", value)
				dest.set_shader_parameter("use_albedo_texture", true)
			return


static func _first_shader_param(source: ShaderMaterial, names: Array[String]) -> Variant:
	for name in names:
		var value: Variant = source.get_shader_parameter(name)
		if value != null:
			return value
	return null
