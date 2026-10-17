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
	var terrain_material := StandardMaterial3D.new()
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 0.92
	surface.material_override = terrain_material


func shoreline_radius(angle: float) -> float:
	return island_radius * (1.0 + 0.13 * sin(3.0 * angle + 0.4)
		+ 0.07 * sin(7.0 * angle - 1.1) + 0.035 * cos(13.0 * angle))


func terrain_height(radius_fraction: float, angle: float) -> float:
	var inland: float = 1.0 - clampf(radius_fraction, 0.0, 1.0)
	# Taper angular ridges to zero at the centre to prevent a radial pinwheel.
	var angular_weight: float = smoothstep(0.02, 0.34, radius_fraction)
	var ridges: float = 1.0 + angular_weight * (
		0.20 * sin(3.0 * angle + 2.5 * radius_fraction)
		+ 0.11 * cos(7.0 * angle - 4.0 * radius_fraction))
	# A low sandy shelf leads into a steep rock escarpment and rounded highland.
	var beach_shelf: float = 0.12 * smoothstep(0.0, 0.18, inland)
	var cliff_rise: float = elevation * 0.55 * smoothstep(0.25, 0.43, inland)
	var highland: float = elevation * 0.45 * pow(inland, 1.5)
	return (beach_shelf + cliff_rise + highland) * ridges


func terrain_color(radius_fraction: float) -> Color:
	var inland: float = 1.0 - clampf(radius_fraction, 0.0, 1.0)
	var sand := Color(0.72, 0.62, 0.44)
	var rock := Color(0.40, 0.43, 0.43)
	var upland := Color(0.30, 0.40, 0.28)
	var cliff_band: float = smoothstep(0.22, 0.37, inland) * (
		1.0 - smoothstep(0.52, 0.68, inland))
	var upland_blend: float = smoothstep(0.58, 0.78, inland)
	return sand.lerp(rock, cliff_band).lerp(upland, upland_blend)


func build_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	# A single center vertex avoids zero-area triangles in the first ring.
	vertices.append(Vector3(0.0, terrain_height(0.0, 0.0), 0.0))
	uvs.append(Vector2.ZERO)
	colors.append(terrain_color(0.0))
	for ring in range(1, ring_segments + 1):
		var fraction := float(ring) / float(ring_segments)
		for segment in range(radial_segments):
			var angle := TAU * float(segment) / float(radial_segments)
			var radius := shoreline_radius(angle) * fraction
			var position := Vector3(cos(angle) * radius,
				terrain_height(fraction, angle), sin(angle) * radius)
			vertices.append(position)
			uvs.append(Vector2(position.x, position.z) * 0.08)
			colors.append(terrain_color(fraction))
	# Godot front faces require clockwise winding when viewed from above (+Y).
	for segment in range(radial_segments):
		var next_segment := (segment + 1) % radial_segments
		indices.append_array(PackedInt32Array([0, 1 + segment, 1 + next_segment]))
	for ring in range(ring_segments - 1):
		var inner_start := 1 + ring * radial_segments
		var outer_start := inner_start + radial_segments
		for segment in range(radial_segments):
			var next_segment := (segment + 1) % radial_segments
			var a := inner_start + segment
			var b := inner_start + next_segment
			var c := outer_start + segment
			var d := outer_start + next_segment
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var face := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += face
		normals[b] += face
		normals[c] += face
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	var tangent_sum := PackedVector3Array()
	tangent_sum.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var ia := indices[i]
		var ib := indices[i + 1]
		var ic := indices[i + 2]
		var edge_a := vertices[ib] - vertices[ia]
		var edge_b := vertices[ic] - vertices[ia]
		var uv_a := uvs[ib] - uvs[ia]
		var uv_b := uvs[ic] - uvs[ia]
		var determinant := uv_a.x * uv_b.y - uv_b.x * uv_a.y
		if absf(determinant) < 0.00001:
			continue
		var tangent := (edge_a * uv_b.y - edge_b * uv_a.y) / determinant
		tangent_sum[ia] += tangent
		tangent_sum[ib] += tangent
		tangent_sum[ic] += tangent
	var tangents := PackedFloat32Array()
	tangents.resize(vertices.size() * 4)
	for i in range(vertices.size()):
		var tangent := tangent_sum[i]
		if tangent.length_squared() < 0.00001:
			tangent = Vector3(1.0, 0.0, 0.0)
		tangent = (tangent - normals[i] * normals[i].dot(tangent)).normalized()
		tangents[i * 4] = tangent.x
		tangents[i * 4 + 1] = tangent.y
		tangents[i * 4 + 2] = tangent.z
		tangents[i * 4 + 3] = 1.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
