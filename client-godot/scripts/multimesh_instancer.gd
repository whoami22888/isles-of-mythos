class_name MultiMeshInstancer
extends MultiMeshInstance3D
## Batches repeated instances of one mesh/material into a MultiMesh.
## Use one node per homogeneous mesh/material batch (trees, rocks, coral,
## cannonballs, army units). A single-surface mesh produces one draw call per
## render pass; heterogeneous or multi-surface assets require separate batches.

const MAX_INSTANCE_COUNT := 10000
const FLOATS_PER_INSTANCE := 16 # 12 Transform3D floats + 4 RGBA floats.

@export var source_mesh: Mesh
@export var source_material: StandardMaterial3D

var _configured := false
var _instance_buffer := PackedFloat32Array()


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

	# MultiMesh format flags must be set before allocating any instances.
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
	if transforms.is_empty():
		clear_instances()
		return true

	if multimesh.instance_count != transforms.size():
		multimesh.instance_count = transforms.size()

	var required_float_count := transforms.size() * FLOATS_PER_INSTANCE
	if _instance_buffer.size() != required_float_count:
		_instance_buffer.resize(required_float_count)

	for index in range(transforms.size()):
		var transform := transforms[index]
		var instance_color := colors[index] if not colors.is_empty() else Color.WHITE
		var offset := index * FLOATS_PER_INSTANCE

		# Godot MultiMesh 3D buffer order is row-major Transform3D (12 floats),
		# followed by RGBA (4 floats) when use_colors is enabled.
		_instance_buffer[offset + 0] = transform.basis.x.x
		_instance_buffer[offset + 1] = transform.basis.y.x
		_instance_buffer[offset + 2] = transform.basis.z.x
		_instance_buffer[offset + 3] = transform.origin.x
		_instance_buffer[offset + 4] = transform.basis.x.y
		_instance_buffer[offset + 5] = transform.basis.y.y
		_instance_buffer[offset + 6] = transform.basis.z.y
		_instance_buffer[offset + 7] = transform.origin.y
		_instance_buffer[offset + 8] = transform.basis.x.z
		_instance_buffer[offset + 9] = transform.basis.y.z
		_instance_buffer[offset + 10] = transform.basis.z.z
		_instance_buffer[offset + 11] = transform.origin.z
		_instance_buffer[offset + 12] = instance_color.r
		_instance_buffer[offset + 13] = instance_color.g
		_instance_buffer[offset + 14] = instance_color.b
		_instance_buffer[offset + 15] = instance_color.a

	# Upload all transforms and colours in one buffer assignment.
	multimesh.buffer = _instance_buffer
	multimesh.visible_instance_count = transforms.size()
	custom_aabb = _calculate_custom_aabb(transforms)
	return true


func clear_instances() -> void:
	if multimesh == null:
		return
	multimesh.visible_instance_count = 0
	multimesh.instance_count = 0
	_instance_buffer.resize(0)
	multimesh.buffer = _instance_buffer
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
