class_name MultiMeshInstancerTestScene
extends Node3D
## Diagnostic-only 512-instance scene. It is not production art or a visual milestone.

const InstancerScript := preload("res://scripts/multimesh_instancer.gd")

var instancer: MultiMeshInstancer


func _ready() -> void:
	var camera := Camera3D.new()
	camera.name = "TestCamera"
	camera.position = Vector3(24.0, 44.0, 72.0)
	add_child(camera)
	camera.look_at(Vector3(24.0, 0.0, 18.0), Vector3.UP)
	camera.current = true

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 0.8, 0.8)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.vertex_color_use_as_albedo = true

	instancer = InstancerScript.new()
	instancer.name = "BatchedInstances"
	instancer.source_mesh = mesh
	instancer.source_material = material
	instancer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instancer)


func populate(instance_total: int = 512) -> bool:
	if instancer == null or instance_total < 0 or instance_total > InstancerScript.MAX_INSTANCE_COUNT:
		return false

	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for index in range(instance_total):
		var column := index % 32
		var row := int(index / 32)
		var position := Vector3(float(column) * 1.5, 0.0, float(row) * 1.5)
		var yaw := deg_to_rad(float(index % 16) * 22.5)
		transforms.append(Transform3D(Basis(Vector3.UP, yaw), position))
		colors.append(Color(
			0.25 + float(index % 5) * 0.12,
			0.30 + float(index % 7) * 0.08,
			0.35 + float(index % 3) * 0.15,
			1.0
		))
	return instancer.set_instances(transforms, colors)
