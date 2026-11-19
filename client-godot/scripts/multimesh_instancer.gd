class_name MultiMeshInstancer
extends MultiMeshInstance3D
## Batches repeated instances of one mesh/material into a MultiMesh.
## Use one node per mesh/material batch (trees, rocks, coral, cannonballs,
## army units). A single-surface mesh produces one draw call per render pass;
## heterogeneous meshes or multi-surface materials require separate batches.

const MAX_INSTANCE_COUNT := 10000

@export var source_mesh: Mesh
@export var source_material: StandardMaterial3D

var _configured := false


func _ready() -> void:
	if source_mesh != null:
		configure(source_mesh, source_material)


func configure(mesh: Mesh, material: StandardMaterial3D = null) -> bool:
	if mesh == null or mesh.get_surface_count() != 1:
		push_warning("MultiMeshInstancer requires one non-null, single-surface mesh per batch")
		return false

	var selected_material: Material = material
	if selected_material == null:
		selected_material = mesh.surface_get_material(0)

	var pbr_material: StandardMaterial3D
	if selected_material == null:
		pbr_material = StandardMaterial3D.new()
	elif selected_material is StandardMaterial3D:
		pbr_material = (selected_material as StandardMaterial3D).duplicate(true) as StandardMaterial3D
	else:
		push_warning("MultiMeshInstancer requires StandardMaterial3D so per-instance colours remain supported")
		return false

	pbr_material.vertex_color_use_as_albedo = true
	material_override = pbr_material

	if multimesh == null:
		multimesh = MultiMesh.new()
	if multimesh.instance_count > 0:
		multimesh.visible_instance_count = 0
		multimesh.instance_count = 0
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = false
	multimesh.mesh = mesh

	source_mesh = mesh
	source_material = material
	_configured = true
	return true


func set_instances(transforms: Array[Transform3D], colors: Array[Color] = []) -> bool:
	if not _configured and not configure(source_mesh, source_material):
		return false
	if transforms.size() > MAX_INSTANCE_COUNT:
		push_warning("MultiMeshInstancer rejected more than %d instances" % MAX_INSTANCE_COUNT)
		return false
	if not colors.is_empty() and colors.size() != transforms.size():
		push_warning("MultiMeshInstancer colour count must match transform count")
		return false

	if multimesh.instance_count != transforms.size():
		multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
		var instance_color := colors[index] if not colors.is_empty() else Color.WHITE
		multimesh.set_instance_color(index, instance_color)

	multimesh.visible_instance_count = transforms.size()
	custom_aabb = _calculate_custom_aabb(transforms)
	return true


func clear_instances() -> void:
	if multimesh == null:
		return
	multimesh.visible_instance_count = 0
	multimesh.instance_count = 0
	custom_aabb = AABB()


func get_expected_draw_calls() -> int:
	if not _configured or multimesh == null or multimesh.mesh == null:
		return 0
	return multimesh.mesh.get_surface_count()


func _calculate_custom_aabb(transforms: Array[Transform3D]) -> AABB:
	if source_mesh == null or transforms.is_empty():
		return AABB()

	var mesh_bounds: AABB = source_mesh.get_aabb()
	var combined := AABB()
	var has_bounds := false
	for transform in transforms:
		for corner_index in range(8):
			var point: Vector3 = transform * mesh_bounds.get_endpoint(corner_index)
			if not has_bounds:
				combined = AABB(point, Vector3.ZERO)
				has_bounds = true
			else:
				combined = combined.expand(point)
	return combined
