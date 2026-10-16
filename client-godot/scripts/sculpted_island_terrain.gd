extends Node3D
## Deterministic, first-party sculpted island mesh; no imported assets or gameplay authority.
## Standalone graphics workstream: does not edit existing island or shoreline PR surfaces.

@export_range(24, 192, 8) var radial_segments := 96
@export_range(8, 48, 2) var ring_segments := 24
@export var island_radius := 18.0
@export var elevation := 5.0

func _ready() -> void:
	var surface := MeshInstance3D.new()
	surface.name = "SculptedCoast"
	surface.mesh = build_mesh()
	add_child(surface)
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.69, 0.61, 0.43)
	sand.roughness = 0.92
	surface.material_override = sand


func shoreline_radius(angle: float) -> float:
	return island_radius * (1.0 + 0.13 * sin(3.0 * angle + 0.4)
		+ 0.07 * sin(7.0 * angle - 1.1) + 0.035 * cos(13.0 * angle))


func terrain_height(radius_fraction: float, angle: float) -> float:
	var interior := clampf((0.88 - radius_fraction) / 0.88, 0.0, 1.0)
	var ridges := 0.62 + 0.22 * sin(3.0 * angle + 2.5 * radius_fraction)
	ridges += 0.16 * cos(7.0 * angle - 4.0 * radius_fraction)
	var cliffs := smoothstep(0.14, 0.36, interior)
	return elevation * pow(interior, 1.3) * maxf(ridges, 0.2) * cliffs


func build_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in range(ring_segments + 1):
		var fraction := float(ring) / float(ring_segments)
		for segment in range(radial_segments + 1):
			var angle := TAU * float(segment) / float(radial_segments)
			var radius := shoreline_radius(angle) * fraction
			var position := Vector3(cos(angle) * radius,
				terrain_height(fraction, angle), sin(angle) * radius)
			vertices.append(position)
			uvs.append(Vector2(position.x, position.z) * 0.08)
	for ring in range(ring_segments):
		for segment in range(radial_segments):
			var a := ring * (radial_segments + 1) + segment
			var b := a + radial_segments + 1
			indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var face := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		normals[a] += face
		normals[b] += face
		normals[c] += face
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
