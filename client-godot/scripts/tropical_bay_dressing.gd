class_name TropicalBayDressing
extends RefCounted
## Original low-poly bay dressing: palms, grass, huts, a volcano and hazy islets.
## No second water or terrain system. The coastal slice still owns the mesh
## and the shore-height contract. Geometry here is first-party.

const PALM_BUDGET := 96
const GRASS_BUDGET := 180
const PALM_TRIANGLE_BUDGET := 120
const TERRAIN_SHADER := preload("res://shaders/coastal_terrain_surface.gdshader")
const COAST_DIFFUSE := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_diff_1k.jpg")
const FOLIAGE_WIND_SHADER := preload("res://shaders/tropical_foliage_wind.gdshader")


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
	# Both meshes keep the same batched draw path. Taller palms bend more
	# slowly than short grass; neither moves at the rooted base.
	instance.material_override = _foliage_material(0.55 if include_beach else 3.4,
		0.065 if include_beach else 0.13)
	return instance


static func _clear_of_ship(px: float, pz: float) -> bool:
	return Vector2(px - 1.0, pz + 5.8).length() > 7.5


static func _foliage_material(height: float, amplitude: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FOLIAGE_WIND_SHADER
	material.set_shader_parameter("canopy_height", height)
	material.set_shader_parameter("wind_strength", amplitude)
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
			colors.append(Color(0.33, 0.27, 0.21).lerp(Color(0.52, 0.45, 0.34), t))
	for segment in range(segments):
		for side in range(sides):
			var next_side := (side + 1) % sides
			var a := segment * sides + side
			var b := segment * sides + next_side
			var c := a + sides
			var d := b + sides
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var frond_root := vertices.size()
	var fronds := 7
	for frond in range(fronds):
		var yaw := TAU * float(frond) / float(fronds) + 0.31 * sin(float(frond) * 2.3)
		var direction := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-direction.z, 0.0, direction.x)
		var base := frond_root + frond * 9
		var droop: Array[float] = [0.30, -0.10, -0.95]
		var reach: Array[float] = [0.30, 1.20, 2.25]
		var half_width: Array[float] = [0.14, 0.46, 0.10]
		var fold := 0.16
		for step in range(3):
			# Midrib plus two leaflet edges folded down: a V cross-section
			# gives each frond a lit and a shaded half instead of a flat card.
			var center := Vector3(0.0, trunk_top, 0.0) + direction * reach[step] + Vector3(0.0, droop[step], 0.0)
			var edge_drop := Vector3(0.0, -fold * half_width[step] * 2.2, 0.0)
			vertices.append(center + side * half_width[step] + edge_drop)
			vertices.append(center)
			vertices.append(center - side * half_width[step] + edge_drop)
			normals.append((Vector3.UP + side * 0.45).normalized())
			normals.append(Vector3.UP)
			normals.append((Vector3.UP - side * 0.45).normalized())
			var t_step := float(step) / 2.0
			var green := Color(0.05, 0.19, 0.06).lerp(Color(0.17, 0.31, 0.08), t_step)
			colors.append(green.darkened(0.12))
			colors.append(green.lightened(0.06))
			colors.append(green.darkened(0.12))
		for step in range(2):
			var r0 := base + step * 3
			var r1 := r0 + 3
			indices.append_array(PackedInt32Array([
				r0, r0 + 1, r1, r0 + 1, r1 + 1, r1,
				r0 + 1, r0 + 2, r1 + 1, r0 + 2, r1 + 2, r1 + 1,
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
	# Three stilted thatch huts merged into one mesh: one draw call, not three.
	var hut_vertices := PackedVector3Array()
	var hut_colors := PackedColorArray()
	var hut_indices := PackedInt32Array()
	for hut in [
		[Vector3(-12.5, 0.0, 3.6), 1.7, Color(0.60, 0.48, 0.31), Color(0.42, 0.31, 0.16)],
		[Vector3(-9.4, 0.0, 5.4), 1.35, Color(0.66, 0.53, 0.34), Color(0.46, 0.34, 0.18)],
		[Vector3(8.8, 0.0, 4.8), 1.5, Color(0.56, 0.45, 0.30), Color(0.39, 0.29, 0.15)],
	]:
		var spot: Vector3 = hut[0]
		var origin := Vector3(spot.x, coast._terrain_height(spot.x, spot.z), spot.z)
		_add_hut(hut_vertices, hut_colors, hut_indices, origin, hut[1], hut[2], hut[3])
	var huts := MeshInstance3D.new()
	huts.name = "StiltedHuts"
	huts.mesh = _colored_mesh(hut_vertices, hut_colors, hut_indices)
	huts.material_override = material
	huts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(huts)
	return root


static func _colored_mesh(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The boxes had no normals, so huts and pier lit as flat blobs. Generate
	# flat per-face normals for crisp faceted wood and thatch.
	var tool := SurfaceTool.new()
	tool.create_from(mesh, 0)
	tool.deindex()
	tool.generate_normals()
	# Re-index so callers that read ARRAY_INDEX (triangle budgets, capture
	# cost reports) still get an indexed surface; faces stay flat-shaded.
	tool.index()
	return tool.commit()


static func _add_hut(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, origin: Vector3, size: float, wall: Color, roof: Color) -> void:
	# Stilted beach hut: four posts, a raised deck, woven walls with a dark
	# doorway and a steep thatch roof that overhangs the deck.
	var post := Color(0.30, 0.21, 0.13)
	var stilt := size * 0.42
	var half_w := size * 0.5
	var half_d := size * 0.4
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_add_box(vertices, colors, indices,
			origin + Vector3(corner.x * half_w, stilt * 0.5, corner.y * half_d),
			Vector3(size * 0.09, stilt + 0.3, size * 0.09), post)
	_add_box(vertices, colors, indices, origin + Vector3(0.0, stilt, 0.0),
		Vector3(size * 1.18, size * 0.07, size * 1.0), post.lightened(0.18))
	var wall_h := size * 0.62
	_add_box(vertices, colors, indices, origin + Vector3(0.0, stilt + wall_h * 0.5, 0.0),
		Vector3(size, wall_h, size * 0.8), wall)
	_add_box(vertices, colors, indices, origin + Vector3(0.0, stilt + size * 0.24, half_d + 0.01),
		Vector3(size * 0.26, size * 0.44, 0.04), Color(0.12, 0.08, 0.05))
	_add_prism_roof(vertices, colors, indices, origin + Vector3(0.0, stilt + wall_h - size * 0.04, 0.0),
		Vector3(size * 1.5, size * 0.78, size * 1.22), roof)


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
	# Clockwise seen from outside, Godot's front face: (c - a) x (b - a) points out.
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
			base + face[0], base + face[1], base + face[2],
			base + face[0], base + face[2], base + face[3],
		]))


static func _volcano() -> Node3D:
	var root := Node3D.new()
	root.name = "DistantVolcano"
	root.position = Vector3(6.0, 0.0, 86.0)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "VolcanoLandmass"
	mesh_instance.mesh = landmass_mesh(19.0, 16.0, 19.0, 3.1, 0.22)
	mesh_instance.material_override = _landmass_material(Color(0.20, 0.30, 0.13), Color(0.30, 0.26, 0.23))
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
	# Emit from the crater floor (the landmass centre vertex), not the old
	# cone tip, so the plume rises out of the crater.
	var crater_floor: Vector3 = (mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0]
	smoke.position = crater_floor + Vector3(0.0, 0.3, 0.0)
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


static func _distant_islands() -> MeshInstance3D:
	# Four sculpted landmasses merged into one mesh: one draw call, no cones.
	var specs := [
		[Vector3(-62.0, 0.0, 36.0), 17.0, 12.0, 7.5, 1.3],
		[Vector3(58.0, 0.0, 28.0), 13.0, 10.0, 5.0, 2.7],
		[Vector3(-28.0, 0.0, 78.0), 21.0, 14.0, 6.0, 4.4],
		[Vector3(36.0, 0.0, 70.0), 15.0, 11.0, 4.2, 5.9],
	]
	var merged := SurfaceTool.new()
	merged.begin(Mesh.PRIMITIVE_TRIANGLES)
	for spec in specs:
		var part: ArrayMesh = landmass_mesh(spec[1], spec[2], spec[3], spec[4], 0.0)
		merged.append_from(part, 0, Transform3D(Basis.IDENTITY, spec[0]))
	var instance := MeshInstance3D.new()
	instance.name = "HazyIslets"
	instance.mesh = merged.commit()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = _landmass_material(Color(0.18, 0.36, 0.12), Color(0.44, 0.40, 0.34))
	return instance


## Irregular island: noisy coastline, ridged slopes, beach shelf and a
## submerged skirt so the ocean shader meets real geometry at sea level.
## Every face is clockwise from above (Godot front face) by construction.
static func landmass_mesh(radius_x: float, radius_z: float, peak: float, seed: float, crater: float, rings: int = 10, sectors: int = 30) -> ArrayMesh:
	const SEA := -0.35
	var vertices := PackedVector3Array()
	vertices.append(Vector3(0.0, SEA + peak * (1.0 - crater), 0.0))
	for ring in range(1, rings + 1):
		var r := float(ring) / float(rings) * 1.2
		for sector in range(sectors):
			var angle := TAU * float(sector) / float(sectors)
			var coast := 1.0 + 0.16 * sin(angle * 3.0 + seed) + 0.09 * sin(angle * 7.0 + seed * 2.3) + 0.05 * sin(angle * 13.0 + seed * 0.7)
			# Profile runs on the normalised radius; the noisy coastline scales the
			# vertex position instead. The outer ring (t = 1.2) is then always past
			# the skirt (t >= 1.15) and every boundary vertex is under the sea.
			var t := r
			var body := pow(clampf(1.0 - t, 0.0, 1.0), 1.7)
			var ridge := 0.12 * sin(angle * 5.0 + seed * 1.9 + r * 6.0) * body
			var height := peak * (body + ridge)
			if crater > 0.0:
				height -= peak * crater * (1.0 - smoothstep(0.0, 0.16, t))
			height += 0.55 * (1.0 - smoothstep(0.88, 1.0, t))
			height -= 2.2 * smoothstep(1.0, 1.15, t)
			vertices.append(Vector3(cos(angle) * r * coast * radius_x, SEA + height, sin(angle) * r * coast * radius_z))
	var indices := PackedInt32Array()
	for sector in range(sectors):
		_add_upward_triangle(vertices, indices, 0, 1 + sector, 1 + (sector + 1) % sectors)
	for ring in range(rings - 1):
		var inner := 1 + ring * sectors
		var outer := inner + sectors
		for sector in range(sectors):
			var next := (sector + 1) % sectors
			_add_upward_triangle(vertices, indices, inner + sector, outer + sector, outer + next)
			_add_upward_triangle(vertices, indices, inner + sector, outer + next, inner + next)
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for t in range(0, indices.size(), 3):
		var a := vertices[indices[t]]
		var face := (vertices[indices[t + 2]] - a).cross(vertices[indices[t + 1]] - a)
		for k in range(3):
			normals[indices[t + k]] += face
	var uvs := PackedVector2Array()
	for i in range(vertices.size()):
		normals[i] = normals[i].normalized()
		uvs.append(Vector2(vertices[i].x, vertices[i].z) * 0.14)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _add_upward_triangle(vertices: PackedVector3Array, indices: PackedInt32Array, a: int, b: int, c: int) -> void:
	# Godot front face is clockwise: (c - a) x (b - a) must point up.
	if (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a]).y < 0.0:
		indices.append_array(PackedInt32Array([a, c, b]))
	else:
		indices.append_array(PackedInt32Array([a, b, c]))


static func _landmass_material(grass: Color, rock: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("detail_albedo", COAST_DIFFUSE)
	material.set_shader_parameter("grass_color", grass)
	material.set_shader_parameter("rock_color", rock)
	material.set_shader_parameter("sea_level", -0.35)
	return material
