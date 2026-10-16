extends Node3D
## Deterministic coastal composition prototype. Not licensed scanned rock or vegetation art.

const ROCK_POSITIONS := [
	Vector3(-7.2, 0.2, -1.1), Vector3(-7.7, 0.2, -0.3),
	Vector3(6.8, 0.2, 1.8), Vector3(7.5, 0.2, 2.2),
	Vector3(-2.1, 0.2, 7.3), Vector3(1.3, 0.2, -7.1)
]

func _ready() -> void:
	_build_rocks()
	_build_palm(Vector3(-4.2, 0.3, -4.5), 0.0)
	_build_palm(Vector3(4.0, 0.3, 4.8), 1.1)
	_build_palm(Vector3(3.5, 0.3, -4.1), 2.3)


func _build_rocks() -> void:
	for i in range(ROCK_POSITIONS.size()):
		var stone := MeshInstance3D.new()
		stone.name = "CoastalRock_%02d" % i
		var shape := SphereMesh.new()
		shape.radial_segments = 12
		shape.rings = 8
		stone.mesh = shape
		stone.position = ROCK_POSITIONS[i]
		stone.scale = Vector3(1.1 + 0.17 * i, 0.45 + 0.08 * (i % 3), 0.8 + 0.07 * i)
		stone.rotation.y = float(i) * 0.83
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.41, 0.43, 0.40).lerp(Color(0.55, 0.51, 0.43), float(i % 3) / 3.0)
		material.roughness = 0.94
		stone.material_override = material
		add_child(stone)


func _build_palm(location: Vector3, spin: float) -> void:
	var palm := Node3D.new()
	palm.name = "Palm_%d" % get_child_count()
	palm.position = location
	add_child(palm)
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.41, 0.27, 0.16)
	trunk_material.roughness = 0.91
	for i in range(5):
		var section := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.16 - float(i) * 0.013
		cylinder.bottom_radius = 0.23 - float(i) * 0.01
		cylinder.height = 0.82
		section.mesh = cylinder
		section.position = Vector3(0.07 * i, 0.42 + 0.77 * i, 0)
		section.material_override = trunk_material
		palm.add_child(section)
	var foliage := StandardMaterial3D.new()
	foliage.albedo_color = Color(0.14, 0.39, 0.18)
	foliage.roughness = 0.85
	foliage.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in range(7):
		var leaf := MeshInstance3D.new()
		var leaf_mesh := PlaneMesh.new()
		leaf_mesh.size = Vector2(3.7, 0.48)
		leaf.mesh = leaf_mesh
		leaf.material_override = foliage
		leaf.position = Vector3(0.3, 4.15, 0)
		leaf.rotation = Vector3(-0.23, spin + TAU * i / 7.0, -0.18)
		palm.add_child(leaf)
