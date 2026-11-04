class_name TropicalBayDressing
extends RefCounted
## Original low-poly bay dressing: palms, grass, huts, a volcano and hazy islets.
## No second water or terrain system. The coastal slice still owns the mesh
## and the shore-height contract. Geometry here is first-party.

const PALM_BUDGET := 96
const GRASS_BUDGET := 180
const PALM_TRIANGLE_BUDGET := 120


static func attach(coast: Node3D) -> void:
	var root := Node3D.new()
	root.name = "TropicalBayDressing"
	coast.add_child(root)
	var palm_mesh := _palm_mesh()
	var palm_multi := _scatter_multimesh(coast, palm_mesh, PALM_BUDGET, 2.35, 15.0, 0.9, 1.55, false)
	palm_multi.name = "TropicalPalmGrove"
	root.add_child(palm_multi)
	var grass_multi := _scatter_multimesh(coast, _grass_mesh(), GRASS_BUDGET, 1.25, 14.0, 0.75, 1.35, true)
	grass_multi.name = "TropicalGrassTufts"
	root.add_child(grass_multi)
	root.add_child(_settlement(coast))
	root.add_child(_volcano())
	root.add_child(_distant_islands())


static func palm_triangle_count() -> int:
	return _count_triangles(_palm_mesh())


static func _count_triangles(mesh: ArrayMesh) -> int:
	var total := 0
	for surface_index in range(mesh.get_surface_count()):
		var indices: PackedInt32Array = mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX]
		total += indices.size() / 3
	return total


static func _scatter_multimesh(coast: Node3D, mesh: ArrayMesh, budget: int, spacing: float, z_limit: float, scale_min: float, scale_max: float, include_beach: bool) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = budget
	var placed := 0
	var x := -22.0
	while x <= 22.0 and placed < budget:
		var z := -1.0 if include_beach else 1.2
		while z <= z_limit and placed < budget:
			var jitter_x := sin(x * 12.1 + z * 4.7) * spacing * 0.35
			var jitter_z := cos(x * 7.3 - z * 9.1) * spacing * 0.35
			var px := x + jitter_x
			var pz := z + jitter_z
			var py: float = coast._terrain_height(px, pz)
			var slope := absf(coast._terrain_height(px + 0.8, pz) - py) + absf(coast._terrain_height(px, pz + 0.8) - py)
			var min_height := -0.05 if include_beach else 1.05
			if py > coast.WATER_Y + min_height and slope < (0.85 if include_beach else 1.15) and _clear_of_ship(px, pz):
				var yaw := sin(px * 3.7 + pz * 2.2) * TAU
				var scale := lerpf(scale_min, scale_max, 0.5 + 0.5 * sin(px * 5.1 + pz))
				var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale * lerpf(0.85, 1.2, 0.5 + 0.5 * cos(pz)), scale))
				multi.set_instance_transform(placed, Transform3D(basis, Vector3(px, py, pz)))
				placed += 1
			z += spacing
		x += spacing
	multi.visible_instance_count = placed
	instance.set_meta("placed_count", placed)
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = _foliage_material()
	return instance


static func _clear_of_ship(px: float, pz: float) -> bool:
	return Vector2(px - 1.0, pz + 5.8).length() > 7.5


static func _foliage_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.86
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _palm_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var sides := 6
	var segments := 4
	var trunk_top := 3.4
	for segment in range(segments + 1):
		var t := float(segment) / float(segments)
		var radius := lerpf(0.22, 0.09, t)
		var lean := sin(t * 1.2) * 0.28
		var y := t * trunk_top
		for side in range(sides):
			var angle := TAU * float(side) / float(sides)
			var normal := Vector3(cos(angle), 0.15, sin(angle)).normalized()
			vertices.append(Vector3(cos(angle) * radius + lean, y, sin(angle) * radius))
			normals.append(normal)
			colors.append(Color(0.45, 0.27, 0.12).lerp(Color(0.62, 0.40, 0.18), t))
	for segment in range(segments):
		for side in range(sides):
			var next_side := (side + 1) % sides
			var a := segment * sides + side
			var b := segment * sides + next_side
			var c := a + sides
			var d := b + sides
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var frond_root := vertices.size()
	var fronds := 7
	for frond in range(fronds):
		var yaw := TAU * float(frond) / float(fronds)
		var direction := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-direction.z, 0.0, direction.x)
		var base := frond_root + frond * 6
		var droop: Array[float] = [0.35, -0.05, -0.85]
		var reach: Array[float] = [0.35, 1.15, 2.15]
		var half_width: Array[float] = [0.16, 0.42, 0.12]
		for step in range(3):
			var center := Vector3(0.0, trunk_top, 0.0) + direction * reach[step] + Vector3(0.0, droop[step], 0.0)
			vertices.append(center + side * half_width[step])
			vertices.append(center - side * half_width[step])
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)
			var green := Color(0.10, 0.42, 0.14).lerp(Color(0.45, 0.62, 0.16), float(step) / 2.0)
			colors.append(green)
			colors.append(green)
		indices.append_array(PackedInt32Array([
			base, base + 2, base + 1,
			base + 1, base + 2, base + 3,
			base + 2, base + 4, base + 3,
			base + 3, base + 4, base + 5,
		]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _grass_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for blade in range(3):
		var yaw := float(blade) * TAU / 3.0
		var direction := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-direction.z, 0.0, direction.x) * 0.18
		var tip := direction * 0.05 + Vector3(0.0, 0.55, 0.0)
		var base_index := vertices.size()
		vertices.append(-side)
		vertices.append(side)
		vertices.append(tip)
		for _i in range(3):
			normals.append(Vector3.UP)
		colors.append(Color(0.16, 0.40, 0.12))
		colors.append(Color(0.16, 0.40, 0.12))
		colors.append(Color(0.55, 0.72, 0.22))
		indices.append_array(PackedInt32Array([base_index, base_index + 2, base_index + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _settlement(coast: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "BeachSettlement"
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	var pier := MeshInstance3D.new()
	pier.name = "WoodenPier"
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for plank in range(7):
		var z := 1.4 - float(plank) * 0.95
		var deck_y: float = maxf(coast.WATER_Y + 0.35, coast._terrain_height(-7.2, z) + 0.2)
		_add_box(vertices, colors, indices, Vector3(-7.2, deck_y, z), Vector3(1.6, 0.12, 0.72), Color(0.55, 0.38, 0.20))
		_add_box(vertices, colors, indices, Vector3(-7.9, deck_y - 0.55, z), Vector3(0.12, 1.0, 0.12), Color(0.38, 0.25, 0.14))
		_add_box(vertices, colors, indices, Vector3(-6.5, deck_y - 0.55, z), Vector3(0.12, 1.0, 0.12), Color(0.38, 0.25, 0.14))
	pier.mesh = _colored_mesh(vertices, colors, indices)
	pier.material_override = material
	pier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pier)
	for hut in [
		[Vector3(-12.5, 0.0, 3.6), 1.7, Color(0.72, 0.58, 0.36), Color(0.62, 0.28, 0.16)],
		[Vector3(-9.4, 0.0, 5.4), 1.35, Color(0.78, 0.64, 0.40), Color(0.70, 0.34, 0.18)],
		[Vector3(8.8, 0.0, 4.8), 1.5, Color(0.66, 0.52, 0.34), Color(0.55, 0.24, 0.16)],
	]:
		var hut_vertices := PackedVector3Array()
		var hut_colors := PackedColorArray()
		var hut_indices := PackedInt32Array()
		_add_hut(hut_vertices, hut_colors, hut_indices, Vector3.ZERO, hut[1], hut[2], hut[3])
		var hut_mesh := MeshInstance3D.new()
		hut_mesh.mesh = _colored_mesh(hut_vertices, hut_colors, hut_indices)
		hut_mesh.material_override = material
		hut_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var spot: Vector3 = hut[0]
		hut_mesh.position = Vector3(spot.x, coast._terrain_height(spot.x, spot.z), spot.z)
		root.add_child(hut_mesh)
	return root


static func _colored_mesh(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _add_hut(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, origin: Vector3, size: float, wall: Color, roof: Color) -> void:
	_add_box(vertices, colors, indices, origin + Vector3(0.0, size * 0.45, 0.0), Vector3(size, size * 0.9, size * 0.8), wall)
	_add_prism_roof(vertices, colors, indices, origin + Vector3(0.0, size * 0.95, 0.0), Vector3(size * 1.25, size * 0.55, size * 1.05), roof)


static func _add_prism_roof(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, center: Vector3, size: Vector3, color: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y
	var hz := size.z * 0.5
	var base := vertices.size()
	var corners := [
		center + Vector3(-hx, 0.0, -hz),
		center + Vector3(hx, 0.0, -hz),
		center + Vector3(hx, 0.0, hz),
		center + Vector3(-hx, 0.0, hz),
		center + Vector3(0.0, hy, -hz),
		center + Vector3(0.0, hy, hz),
	]
	for corner in corners:
		vertices.append(corner)
		colors.append(color)
	indices.append_array(PackedInt32Array([
		base, base + 1, base + 4,
		base + 1, base + 2, base + 4,
		base + 4, base + 2, base + 5,
		base + 2, base + 3, base + 5,
		base + 3, base, base + 5,
		base + 5, base, base + 4,
	]))


static func _add_box(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, center: Vector3, size: Vector3, color: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var base := vertices.size()
	var corners := [
		center + Vector3(-hx, -hy, -hz),
		center + Vector3(hx, -hy, -hz),
		center + Vector3(hx, hy, -hz),
		center + Vector3(-hx, hy, -hz),
		center + Vector3(-hx, -hy, hz),
		center + Vector3(hx, -hy, hz),
		center + Vector3(hx, hy, hz),
		center + Vector3(-hx, hy, hz),
	]
	for corner in corners:
		vertices.append(corner)
		colors.append(color)
	# Outward winding matches the coastal heightfield (clockwise from outside).
	var faces := [
		[0, 1, 2, 3],
		[5, 4, 7, 6],
		[4, 0, 3, 7],
		[1, 5, 6, 2],
		[3, 2, 6, 7],
		[4, 5, 1, 0],
	]
	for face in faces:
		indices.append_array(PackedInt32Array([
			base + face[0], base + face[2], base + face[1],
			base + face[0], base + face[3], base + face[2],
		]))


static func _volcano() -> Node3D:
	var root := Node3D.new()
	root.name = "DistantVolcano"
	root.position = Vector3(6.0, -0.35, 86.0)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _cone_mesh(18.0, 20.0, Color(0.22, 0.18, 0.16), Color(0.45, 0.12, 0.06), 16)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh_instance)
	var smoke := CPUParticles3D.new()
	smoke.name = "VolcanoSmoke"
	smoke.amount = 12
	smoke.lifetime = 5.0
	smoke.preprocess = 5.0
	smoke.explosiveness = 0.05
	smoke.local_coords = false
	smoke.direction = Vector3(0.15, 1.0, 0.05)
	smoke.spread = 14.0
	smoke.gravity = Vector3(0.0, 0.2, 0.0)
	smoke.initial_velocity_min = 1.1
	smoke.initial_velocity_max = 2.0
	smoke.scale_amount_min = 1.4
	smoke.scale_amount_max = 3.2
	smoke.position = Vector3(0.0, 19.0, 0.0)
	var puff := SphereMesh.new()
	puff.radial_segments = 6
	puff.rings = 3
	puff.radius = 0.8
	puff.height = 1.4
	smoke.mesh = puff
	var smoke_material := StandardMaterial3D.new()
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.albedo_color = Color(0.75, 0.72, 0.68, 0.28)
	smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke.material_override = smoke_material
	root.add_child(smoke)
	return root


static func _cone_mesh(radius: float, height: float, base_color: Color, peak_color: Color, sides: int = 10) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.append(Vector3(0.0, height, 0.0))
	colors.append(peak_color)
	for side in range(sides):
		var angle := TAU * float(side) / float(sides)
		vertices.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
		colors.append(base_color.lerp(peak_color, 0.25))
	for side in range(sides):
		var next_side := (side + 1) % sides
		indices.append_array(PackedInt32Array([0, 1 + next_side, 1 + side]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _distant_islands() -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	instance.name = "HazyIslets"
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = _cone_mesh(1.0, 0.55, Color(0.16, 0.28, 0.24), Color(0.20, 0.32, 0.26))
	var spots := [
		Transform3D(Basis.IDENTITY.scaled(Vector3(18.0, 10.0, 14.0)), Vector3(-62.0, -0.35, 36.0)),
		Transform3D(Basis.IDENTITY.scaled(Vector3(14.0, 7.0, 12.0)), Vector3(58.0, -0.35, 28.0)),
		Transform3D(Basis.IDENTITY.scaled(Vector3(22.0, 8.0, 16.0)), Vector3(-28.0, -0.35, 78.0)),
		Transform3D(Basis.IDENTITY.scaled(Vector3(16.0, 6.0, 12.0)), Vector3(36.0, -0.35, 70.0)),
	]
	multi.instance_count = spots.size()
	for index in range(spots.size()):
		multi.set_instance_transform(index, spots[index])
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	instance.material_override = material
	return instance
