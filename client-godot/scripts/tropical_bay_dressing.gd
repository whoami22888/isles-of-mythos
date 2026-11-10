class_name TropicalBayDressing
extends RefCounted
## Original low-poly bay dressing: palms, grass, huts, a volcano and hazy islets.
## No second water or terrain system. The coastal slice still owns the mesh
## and the shore-height contract. Geometry here is first-party.

const PALM_BUDGET := 24
const GRASS_BUDGET := 1800
const FERN_BUDGET := 220
const SHRUB_BUDGET := 120
const CALATHEA_BUDGET := 60
const ANTHURIUM_BUDGET := 32
const URSINIA_BUDGET := 56
const SORREL_BUDGET := 56
const LEDGE_FERN_BUDGET := 96
const VINE_BUDGET := 48
const HERO_FLOWER_BUDGET := 16
const BOULDER_BUDGET := 10
const ROCK07_BUDGET := 10
const MOSS_ROCK_BUDGET := 10
const CANOPY_BUDGET := 8
const CANOPY_B_BUDGET := 6
const CRAG_BUDGET := 7
const CRAG07_BUDGET := 5
const DRIFTWOOD_BUDGET := 8
const BEACH_ROCK_BUDGET := 12
const HUT_UNDERSTORY_BUDGET := 18
const PALM_TRIANGLE_BUDGET := 20000
const PALM_V2 := "res://assets/generated/palm_v2/palm_v2_mobile.glb"
const GRASS_CLUMP := "res://assets/external/polyhaven/grass_bermuda_01/grass_bermuda_01_1k.gltf"
const FERN_PLANT := "res://assets/external/polyhaven/fern_02/fern_02_1k.gltf"
const SHRUB_PLANT := "res://assets/external/polyhaven/shrub_03/shrub_03_1k.gltf"
const CALATHEA_PLANT := "res://assets/external/polyhaven/calathea_orbifolia_01/calathea_orbifolia_01_1k.gltf"
const ANTHURIUM_PLANT := "res://assets/external/polyhaven/anthurium_botany_01/anthurium_botany_01_1k.gltf"
const URSINIA_PLANT := "res://assets/external/polyhaven/flower_ursinia/flower_ursinia_1k.gltf"
const SORREL_PLANT := "res://assets/external/polyhaven/shrub_sorrel_01/shrub_sorrel_01_1k.gltf"
const BOULDER_MOBILE := "res://assets/external/polyhaven/boulder_01/boulder_01_mobile.gltf"
const ROCK07_MOBILE := "res://assets/external/polyhaven/rock_07/rock_07_mobile.gltf"
const MOSS_ROCK := "res://assets/external/polyhaven/rock_moss_set_01/rock_moss_set_01_1k.gltf"
const TREE01_LOD2 := "res://assets/external/generated/foliage/island_tree_01_lod2.glb"
const TREE02_LOD2 := "res://assets/external/generated/foliage/island_tree_02_lod2.glb"
const VINE_ALBEDO := preload("res://assets/generated/foliage/hanging_vines_rgba.png")
const LEAVES_COVERAGE := preload("res://assets/external/generated/foliage/island_tree_leaves_rgba_coverage_1k.png")
const CLIFF_SHADER := preload("res://shaders/cliff_surface.gdshader")
const ROCK_SHADER := preload("res://shaders/rock_surface.gdshader")
const MOSS_ALBEDO := preload("res://assets/external/polyhaven/forrest_ground_01/forrest_ground_01_diff_1k.jpg")
const TERRAIN_SHADER := preload("res://shaders/coastal_terrain_surface.gdshader")
const HUT_SHADER := preload("res://shaders/hut_surface.gdshader")
const COAST_DIFFUSE := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_diff_1k.jpg")
const SAND_ALBEDO := preload("res://assets/external/polyhaven/coast_sand_01/coast_sand_01_diff_1k.jpg")
const SAND_NORMAL := preload("res://assets/external/polyhaven/coast_sand_01/coast_sand_01_nor_gl_1k.jpg")
const SAND_ROUGH := preload("res://assets/external/polyhaven/coast_sand_01/coast_sand_01_rough_1k.jpg")
const GRASS_ALBEDO := preload("res://assets/external/polyhaven/forrest_ground_01/forrest_ground_01_diff_1k.jpg")
const GRASS_NORMAL := preload("res://assets/external/polyhaven/forrest_ground_01/forrest_ground_01_nor_gl_1k.jpg")
const GRASS_ROUGH := preload("res://assets/external/polyhaven/forrest_ground_01/forrest_ground_01_rough_1k.jpg")
const ROCK_ALBEDO := preload("res://assets/external/polyhaven/cliff_side/cliff_side_diff_1k.jpg")
const ROCK_NORMAL := preload("res://assets/external/polyhaven/cliff_side/cliff_side_nor_gl_1k.jpg")
const ROCK_ROUGH := preload("res://assets/external/polyhaven/cliff_side/cliff_side_rough_1k.jpg")
const WOOD_ALBEDO := preload("res://assets/external/polyhaven/brown_planks_08/brown_planks_08_diff_1k.jpg")
const WOOD_NORMAL := preload("res://assets/external/polyhaven/brown_planks_08/brown_planks_08_nor_gl_1k.jpg")
const WOOD_ROUGH := preload("res://assets/external/polyhaven/brown_planks_08/brown_planks_08_rough_1k.jpg")
const THATCH_ALBEDO := preload("res://assets/external/polyhaven/thatch_roof_angled/thatch_roof_angled_diff_1k.jpg")
const THATCH_NORMAL := preload("res://assets/external/polyhaven/thatch_roof_angled/thatch_roof_angled_nor_gl_1k.jpg")
const THATCH_ROUGH := preload("res://assets/external/polyhaven/thatch_roof_angled/thatch_roof_angled_rough_1k.jpg")

# Hut footprints resolved against the current heightfield at attach time so
# path thinning, pier start, and the hut mesh all share the same dry terrace.
static var _hut_spots: Array[Vector2] = []


static func attach(coast: Node3D) -> void:
	_hut_spots = [
		coast.walk_to_gentle(-10.4, 8.6, 1.35),
		coast.walk_to_gentle(-6.4, 9.2, 1.35),
		coast.walk_to_gentle(8.0, 9.0, 1.35),
	]
	var root := Node3D.new()
	root.name = "TropicalBayDressing"
	coast.add_child(root)
	var palm_mesh := _palm_v2_mesh()
	var palm_multi := _scatter_multimesh(coast, palm_mesh, PALM_BUDGET, 2.15, 24.0, 0.9, 1.55, false, false, 2.0)
	palm_multi.name = "TropicalPalmGrove"
	root.add_child(palm_multi)
	var grass_mesh := _compose_plant_mesh(GRASS_CLUMP, PackedStringArray(["medium", "small"]), PackedStringArray(["dead", "seedling"]), Vector3(5.2, 5.2, 5.2), true)
	if grass_mesh == null:
		grass_mesh = _grass_mesh()
	var grass_multi := _scatter_multimesh(coast, grass_mesh, GRASS_BUDGET, 0.36, 24.0, 0.90, 1.40, false, false, 0.6, true, 72.0)
	grass_multi.name = "TropicalGrassTufts"
	root.add_child(grass_multi)
	var fern_mesh := _compose_plant_mesh(FERN_PLANT, PackedStringArray(["fern_02_a"]), PackedStringArray(), Vector3(3.4, 3.4, 3.4), true)
	if fern_mesh:
		var fern_multi := _scatter_multimesh(coast, fern_mesh, FERN_BUDGET, 0.95, 24.0, 1.0, 1.55, false, false, 0.8, true, 68.0)
		fern_multi.name = "TropicalFernClumps"
		root.add_child(fern_multi)
		var ledge_ferns := _scatter_multimesh(coast, fern_mesh, LEDGE_FERN_BUDGET, 1.45, 24.0, 1.0, 1.55, false, false, 8.0, false, 80.0)
		ledge_ferns.name = "CliffLedgeFerns"
		root.add_child(ledge_ferns)
	var shrub_mesh := _compose_plant_mesh(SHRUB_PLANT, PackedStringArray(["shrub_03_a"]), PackedStringArray(), Vector3(2.55, 2.55, 2.55), true)
	if shrub_mesh:
		var shrub_multi := _scatter_multimesh(coast, shrub_mesh, SHRUB_BUDGET, 1.35, 24.0, 0.95, 1.5, false, false, 1.0, true, 70.0)
		shrub_multi.name = "TropicalShrubs"
		root.add_child(shrub_multi)
	var calathea_mesh := _compose_plant_mesh(CALATHEA_PLANT, PackedStringArray(["calathea_orbifolia_01_b"]), PackedStringArray(), Vector3(2.35, 2.35, 2.35), true)
	if calathea_mesh:
		var calathea_multi := _scatter_multimesh(coast, calathea_mesh, CALATHEA_BUDGET, 1.55, 24.0, 1.0, 1.45, false, false, 1.1, true, 64.0)
		calathea_multi.name = "TropicalCalathea"
		root.add_child(calathea_multi)
	var anthurium_mesh := _compose_plant_mesh(ANTHURIUM_PLANT, PackedStringArray(["anthurium_botany_05_e"]), PackedStringArray(), Vector3(2.4, 2.4, 2.4), true)
	if anthurium_mesh:
		var anthurium_multi := _scatter_multimesh(coast, anthurium_mesh, ANTHURIUM_BUDGET, 2.0, 24.0, 1.05, 1.45, false, false, 1.0, true, 60.0)
		anthurium_multi.name = "TropicalAnthurium"
		root.add_child(anthurium_multi)
	var ursinia_mesh := _compose_plant_mesh(URSINIA_PLANT, PackedStringArray(["flower_ursinia_e_lod0", "flower_ursinia_d_lod0"]), PackedStringArray(), Vector3(3.2, 3.2, 3.2), true)
	if ursinia_mesh:
		var flower_multi := _scatter_multimesh(coast, ursinia_mesh, URSINIA_BUDGET, 1.85, 24.0, 1.05, 1.5, false, false, 1.0, true, 58.0)
		flower_multi.name = "TropicalUrsinia"
		root.add_child(flower_multi)
	var sorrel_mesh := _compose_plant_mesh(SORREL_PLANT, PackedStringArray(["shrub_sorrel_01_d", "shrub_sorrel_01_e"]), PackedStringArray(), Vector3(3.5, 3.5, 3.5), true)
	if sorrel_mesh:
		var sorrel_multi := _scatter_multimesh(coast, sorrel_mesh, SORREL_BUDGET, 1.9, 24.0, 1.05, 1.5, false, false, 1.0, true, 58.0)
		sorrel_multi.name = "TropicalSorrel"
		root.add_child(sorrel_multi)
	if anthurium_mesh:
		var hero_red := _scatter_hero_flowers(coast, anthurium_mesh, PackedVector3Array([
			Vector3(10.8, 0.0, 8.2), Vector3(11.4, 0.0, 6.8), Vector3(8.6, 0.0, 7.4),
			Vector3(-10.2, 0.0, 8.0), Vector3(-8.0, 0.0, 7.2), Vector3(-12.2, 0.0, 8.6),
			Vector3(2.0, 0.0, 9.4), Vector3(13.0, 0.0, 10.0), Vector3(6.4, 0.0, 8.2),
			Vector3(11.6, 0.0, 9.2), Vector3(-2.4, 0.0, 9.0), Vector3(7.8, 0.0, 6.6),
			Vector3(4.2, 0.0, 8.8), Vector3(-14.0, 0.0, 9.6), Vector3(15.2, 0.0, 9.2),
			Vector3(-4.8, 0.0, 8.4)
		]), 2.1, 2.8)
		hero_red.name = "HeroAnthurium"
		root.add_child(hero_red)
	if ursinia_mesh:
		var hero_orange := _scatter_hero_flowers(coast, ursinia_mesh, PackedVector3Array([
			Vector3(10.6, 0.0, 7.6), Vector3(8.0, 0.0, 8.4), Vector3(12.8, 0.0, 9.0),
			Vector3(-11.0, 0.0, 7.8), Vector3(-8.4, 0.0, 8.6), Vector3(-6.2, 0.0, 9.2),
			Vector3(0.6, 0.0, 10.0), Vector3(14.0, 0.0, 9.4), Vector3(5.8, 0.0, 7.8),
			Vector3(7.2, 0.0, 9.6), Vector3(9.4, 0.0, 8.0), Vector3(11.8, 0.0, 7.2),
			Vector3(-13.4, 0.0, 8.8), Vector3(3.4, 0.0, 8.6), Vector3(16.0, 0.0, 10.2),
			Vector3(-1.0, 0.0, 8.0)
		]), 2.2, 2.9)
		hero_orange.name = "HeroUrsinia"
		root.add_child(hero_orange)
	var vine_mesh := _vine_card_mesh()
	if vine_mesh:
		var vines := _scatter_cliff_vines(coast, vine_mesh, VINE_BUDGET)
		vines.name = "CliffVines"
		root.add_child(vines)
	var boulder_mesh := _compose_plant_mesh(BOULDER_MOBILE, PackedStringArray(), PackedStringArray(), Vector3.ONE, true)
	if boulder_mesh:
		_apply_rock_shader(boulder_mesh)
		var rocks := _scatter_rock_clusters(coast, boulder_mesh, BOULDER_BUDGET, 1.1, 0.55, 0.95)
		rocks.name = "ShoreBoulders"
		root.add_child(rocks)
	var rock07_mesh := _compose_plant_mesh(ROCK07_MOBILE, PackedStringArray(), PackedStringArray(), Vector3.ONE, true)
	if rock07_mesh:
		_apply_rock_shader(rock07_mesh)
		var rocks07 := _scatter_rock_clusters(coast, rock07_mesh, ROCK07_BUDGET, 2.4, 0.50, 0.90)
		rocks07.name = "ShoreRocks07"
		root.add_child(rocks07)
	var moss_mesh := _compose_plant_mesh(MOSS_ROCK, PackedStringArray(["rock03"]), PackedStringArray(), Vector3.ONE, true)
	if moss_mesh:
		_apply_rock_shader(moss_mesh)
		var moss_rocks := _scatter_rock_clusters(coast, moss_mesh, MOSS_ROCK_BUDGET, 3.7, 0.48, 0.88)
		moss_rocks.name = "ShoreMossRocks"
		root.add_child(moss_rocks)
	var tree01_mesh := _compose_plant_mesh(TREE01_LOD2, PackedStringArray(), PackedStringArray(), Vector3(1.15, 1.15, 1.15), true)
	if tree01_mesh:
		_apply_leaf_scissor(tree01_mesh)
		var canopy := _scatter_multimesh(coast, tree01_mesh, CANOPY_BUDGET, 5.4, 24.0, 1.05, 1.55, false, false, 3.6, false, 88.0)
		canopy.name = "TropicalBroadleafCanopy"
		canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(canopy)
	var tree02_mesh := _compose_plant_mesh(TREE02_LOD2, PackedStringArray(), PackedStringArray(), Vector3(1.1, 1.1, 1.1), true)
	if tree02_mesh:
		_apply_leaf_scissor(tree02_mesh)
		var canopy_b := _scatter_multimesh(coast, tree02_mesh, CANOPY_B_BUDGET, 6.0, 24.0, 1.0, 1.5, false, false, 4.2, false, 88.0)
		canopy_b.name = "TropicalBroadleafCanopyB"
		canopy_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(canopy_b)
	var crag_boulder := _compose_plant_mesh(BOULDER_MOBILE, PackedStringArray(), PackedStringArray(), Vector3.ONE, true)
	if crag_boulder:
		_apply_crag_shader(crag_boulder)
		var crags := _scatter_summit_crags(coast, crag_boulder, CRAG_BUDGET, 1.0, 2.6, 4.4)
		crags.name = "SummitCrags"
		root.add_child(crags)
	var crag_rock07 := _compose_plant_mesh(ROCK07_MOBILE, PackedStringArray(), PackedStringArray(), Vector3.ONE, true)
	if crag_rock07:
		_apply_crag_shader(crag_rock07)
		var crags07 := _scatter_summit_crags(coast, crag_rock07, CRAG07_BUDGET, 2.2, 2.4, 4.0)
		crags07.name = "SummitCrags07"
		root.add_child(crags07)
	var drift_mesh := _driftwood_mesh()
	if drift_mesh:
		var drift := _scatter_beach_props(coast, drift_mesh, DRIFTWOOD_BUDGET, 0.6, 0.85, 1.25, 0.12)
		drift.name = "BeachDriftwood"
		root.add_child(drift)
	if rock07_mesh:
		var beach_rocks := _scatter_beach_props(coast, rock07_mesh, BEACH_ROCK_BUDGET, 1.7, 0.28, 0.55, 0.22)
		beach_rocks.name = "BeachScatterRocks"
		root.add_child(beach_rocks)
	if fern_mesh:
		var hut_plants := _scatter_hut_understory(coast, fern_mesh, HUT_UNDERSTORY_BUDGET)
		hut_plants.name = "HutUnderstory"
		root.add_child(hut_plants)
	root.add_child(_settlement(coast))
	root.add_child(_volcano())
	root.add_child(_distant_islands())


static func palm_triangle_count() -> int:
	return _count_triangles(_palm_v2_mesh())


static func _count_triangles(mesh: ArrayMesh) -> int:
	var total := 0
	for surface_index in range(mesh.get_surface_count()):
		var indices: PackedInt32Array = mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX]
		total += indices.size() / 3
	return total


static func _scatter_multimesh(coast: Node3D, mesh: ArrayMesh, budget: int, spacing: float, z_limit: float, scale_min: float, scale_max: float, include_beach: bool, use_override: bool = true, z_start: float = -999.0, inland_dense: bool = false, fade_end: float = 72.0) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = budget
	var placed := 0
	var min_height := -0.05 if include_beach else (1.6 if z_start > 8.0 else 1.05)
	var slope_cap := 0.85 if include_beach else (2.85 if z_start > 8.0 else 2.45)
	# Offset passes so an irregular footprint still fills the denser budget.
	for pass_i in range(3):
		if placed >= budget:
			break
		var x := -28.0 + spacing * 0.33 * float(pass_i)
		while x <= 28.0 and placed < budget:
			var z := (z_start if z_start > -900.0 else (-1.0 if include_beach else 1.2)) + spacing * 0.28 * float(pass_i)
			while z <= z_limit and placed < budget:
				var step := spacing
				if inland_dense and z > 3.6:
					step = spacing * 0.32
				var jitter_x := sin(x * 12.1 + z * 4.7 + float(pass_i) * 5.3) * step * 0.35
				var jitter_z := cos(x * 7.3 - z * 9.1 + float(pass_i) * 3.1) * step * 0.35
				var px := x + jitter_x
				var pz := z + jitter_z
				var py: float = coast._terrain_height(px, pz)
				var slope := absf(coast._terrain_height(px + 0.8, pz) - py) + absf(coast._terrain_height(px, pz + 0.8) - py)
				if inland_dense and _on_settlement_path(px, pz) and sin(px * 9.1 + pz * 4.3) > 0.15:
					z += step
					continue
				if coast.is_foliage_ground(px, pz) and py > coast.WATER_Y + min_height and slope < slope_cap and _clear_of_ship(px, pz):
					var yaw := sin(px * 3.7 + pz * 2.2) * TAU
					var scale := lerpf(scale_min, scale_max, 0.5 + 0.5 * sin(px * 5.1 + pz))
					var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale * lerpf(0.85, 1.2, 0.5 + 0.5 * cos(pz)), scale))
					multi.set_instance_transform(placed, Transform3D(basis, Vector3(px, py, pz)))
					placed += 1
				z += step
			x += spacing
	multi.visible_instance_count = placed
	instance.set_meta("placed_count", placed)
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if use_override:
		instance.material_override = _foliage_material()
	_apply_distance_fade(instance, fade_end)
	return instance


static func _clear_of_ship(px: float, pz: float) -> bool:
	return Vector2(px - 1.5, pz + 7.2).length() > 7.5


static func _on_settlement_path(px: float, pz: float) -> bool:
	for hut in _hut_spots:
		# Only the hut footprint itself; a foliage ring sits just outside this.
		if Vector2(px, pz).distance_to(hut) < 0.95:
			return true
	# Narrow path from the west hut down to the pier, not a cleared lawn.
	if _hut_spots.size() >= 1:
		var west: Vector2 = _hut_spots[0]
		if absf(px - (west.x + 1.8)) < 1.05 and pz < west.y and pz > west.y - 4.8:
			return true
	return absf(px) < 2.0 and pz > 2.0 and pz < 6.2


static func _foliage_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.86
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _palm_v2_mesh() -> ArrayMesh:
	# Loads the PBR-textured palm_v2_mobile.glb, bakes its node transform into
	# a mesh copy and scales it so the fronds sit ~3.4 tall like the procedural
	# palm. Falls back to the procedural mesh if the asset is missing.
	var packed := load(PALM_V2) as PackedScene
	if packed == null:
		return _palm_mesh()
	var instance := packed.instantiate()
	var mesh_instance := _find_mesh_instance(instance)
	if mesh_instance == null or mesh_instance.mesh == null:
		instance.queue_free()
		return _palm_mesh()
	var source_mesh := mesh_instance.mesh
	# Compose local xforms from the mesh up to the packed root (instance may not be in the tree).
	var xform := Transform3D.IDENTITY
	var walker: Node = mesh_instance
	while walker is Node3D:
		xform = (walker as Node3D).transform * xform
		if walker == instance:
			break
		walker = walker.get_parent()
	xform = Transform3D.IDENTITY.scaled(Vector3(3.0, 3.0, 3.0)) * xform
	var result := ArrayMesh.new()
	for surface_index in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface_index)
		var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var vertex_count := source_vertices.size()
		var vertices := source_vertices.duplicate()
		for i in range(vertex_count):
			vertices[i] = xform * vertices[i]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			if source_normals.size() == vertex_count:
				var normals := source_normals.duplicate()
				for i in range(vertex_count):
					normals[i] = (xform.basis * normals[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := source_mesh.surface_get_material(surface_index)
		if material != null:
			result.surface_set_material(surface_index, material)
	instance.queue_free()
	if result.get_surface_count() == 0:
		return _palm_mesh()
	_soften_mesh_alpha(result)
	return result


static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


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
	var material := _hut_material()
	var pier := MeshInstance3D.new()
	pier.name = "WoodenPier"
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var pier_hint := _hut_spots[0] if _hut_spots.size() > 0 else Vector2(-7.2, 6.0)
	var shore: Vector2 = coast.walk_to_shore(pier_hint.x + 3.6, pier_hint.y, Vector2(0.0, -1.0))
	var pier_x := shore.x
	# Start two planks inland and run out over the water so the deck reaches the bay.
	for plank in range(8):
		var z := shore.y + 1.6 - float(plank) * 0.85
		var deck_y: float = maxf(coast.WATER_Y + 0.35, coast._terrain_height(pier_x, z) + 0.2)
		_add_box(vertices, colors, indices, Vector3(pier_x, deck_y, z), Vector3(1.6, 0.12, 0.72), Color(0.55, 0.38, 0.20))
		var stilt_len: float = maxf(1.0, deck_y - minf(coast._terrain_height(pier_x, z), coast.WATER_Y) + 0.15)
		_add_box(vertices, colors, indices, Vector3(pier_x - 0.7, deck_y - stilt_len * 0.5, z), Vector3(0.12, stilt_len, 0.12), Color(0.38, 0.25, 0.14))
		_add_box(vertices, colors, indices, Vector3(pier_x + 0.7, deck_y - stilt_len * 0.5, z), Vector3(0.12, stilt_len, 0.12), Color(0.38, 0.25, 0.14))
	pier.mesh = _colored_mesh(vertices, colors, indices)
	pier.material_override = material
	pier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(pier)
	# Three stilted thatch huts merged into one mesh: one draw call, not three.
	var hut_vertices := PackedVector3Array()
	var hut_colors := PackedColorArray()
	var hut_indices := PackedInt32Array()
	var hut_styles := [
		[1.7, Color(0.60, 0.48, 0.31), Color(0.42, 0.31, 0.16)],
		[1.35, Color(0.66, 0.53, 0.34), Color(0.46, 0.34, 0.18)],
		[1.5, Color(0.56, 0.45, 0.30), Color(0.39, 0.29, 0.15)],
	]
	for hi in range(mini(_hut_spots.size(), hut_styles.size())):
		var spot: Vector2 = _hut_spots[hi]
		var origin := Vector3(spot.x, coast._terrain_height(spot.x, spot.y), spot.y)
		_add_hut(hut_vertices, hut_colors, hut_indices, origin, hut_styles[hi][0], hut_styles[hi][1], hut_styles[hi][2])
	var huts := MeshInstance3D.new()
	huts.name = "StiltedHuts"
	huts.mesh = _colored_mesh(hut_vertices, hut_colors, hut_indices)
	huts.material_override = material
	huts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
		Vector3(size * 1.5, size * 0.78, size * 1.22), Color(roof.r, roof.g, roof.b, 0.0))


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
	mesh_instance.material_override = _landmass_material(Color(0.20, 0.34, 0.14), Color(0.40, 0.42, 0.48), true)
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
		var part: ArrayMesh = landmass_mesh(spec[1], spec[2], spec[3], spec[4], 0.0, 12, 40)
		merged.append_from(part, 0, Transform3D(Basis.IDENTITY, spec[0]))
	var instance := MeshInstance3D.new()
	instance.name = "HazyIslets"
	instance.mesh = merged.commit()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = _landmass_material(Color(0.18, 0.36, 0.12), Color(0.42, 0.44, 0.50), true)
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
			var coast := 1.0 + 0.34 * sin(angle * 2.0 + seed) + 0.22 * sin(angle * 5.0 + seed * 1.7) + 0.14 * sin(angle * 9.0 + seed * 2.3) + 0.09 * sin(angle * 17.0 + seed * 0.6) + 0.05 * sin(angle * 23.0 + seed * 3.1)
			# Profile runs on the normalised radius; the noisy coastline scales the
			# vertex position instead. The outer ring (t = 1.2) is then always past
			# the skirt (t >= 1.15) and every boundary vertex is under the sea.
			var t := r
			# Green flanks, a sharper rocky crown, then a direct drop into the
			# sea — no sandy terrace that reads as a disc.
			var body := pow(clampf(1.0 - t, 0.0, 1.0), 1.28)
			var shoulder := 0.36 * pow(clampf(1.0 - absf(t - 0.46) / 0.36, 0.0, 1.0), 1.25) * (0.50 + 0.50 * sin(angle * 3.0 + seed * 1.3))
			var ridge := 0.22 * sin(angle * 4.0 + seed * 1.9 + r * 5.0) * body
			var crown := 0.18 * pow(clampf(1.0 - t / 0.34, 0.0, 1.0), 1.1)
			var height := peak * (body * 0.72 + shoulder + ridge + crown)
			if crater > 0.0:
				height -= peak * crater * (1.0 - smoothstep(0.0, 0.16, t))
			height -= 2.5 * smoothstep(0.92, 1.14, t)
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


static func _landmass_material(grass: Color, rock: Color, distant: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("sand_albedo", SAND_ALBEDO)
	material.set_shader_parameter("sand_normal", SAND_NORMAL)
	material.set_shader_parameter("sand_rough", SAND_ROUGH)
	material.set_shader_parameter("grass_albedo", GRASS_ALBEDO)
	material.set_shader_parameter("grass_normal", GRASS_NORMAL)
	material.set_shader_parameter("grass_rough", GRASS_ROUGH)
	material.set_shader_parameter("rock_albedo", ROCK_ALBEDO)
	material.set_shader_parameter("rock_normal", ROCK_NORMAL)
	material.set_shader_parameter("rock_rough", ROCK_ROUGH)
	material.set_shader_parameter("grass_tint", Color(0.42, 0.62, 0.30).lerp(grass, 0.40))
	material.set_shader_parameter("rock_tint", Color(0.84, 0.78, 0.70).lerp(rock, 0.40))
	material.set_shader_parameter("sea_level", -0.35)
	if distant:
		material.set_shader_parameter("distant_cool", 0.72)
		material.set_shader_parameter("rock_bias", 0.18)
		material.set_shader_parameter("sand_bias", -0.90)
	return material


static func _hut_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HUT_SHADER
	material.set_shader_parameter("wood_albedo", WOOD_ALBEDO)
	material.set_shader_parameter("wood_normal", WOOD_NORMAL)
	material.set_shader_parameter("wood_rough", WOOD_ROUGH)
	material.set_shader_parameter("thatch_albedo", THATCH_ALBEDO)
	material.set_shader_parameter("thatch_normal", THATCH_NORMAL)
	material.set_shader_parameter("thatch_rough", THATCH_ROUGH)
	return material


static func _compose_plant_mesh(path: String, name_contains: PackedStringArray, name_excludes: PackedStringArray, bake_scale: Vector3, recenter: bool) -> ArrayMesh:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var instance := packed.instantiate()
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(instance, meshes)
	if meshes.is_empty():
		instance.queue_free()
		return null
	var result := ArrayMesh.new()
	var min_y := 1.0e9
	var baked_surfaces: Array = []
	for mesh_instance in meshes:
		var node_name := String(mesh_instance.name).to_lower()
		if not name_contains.is_empty():
			var allowed := false
			for token in name_contains:
				if node_name.contains(token.to_lower()):
					allowed = true
					break
			if not allowed:
				continue
		var excluded := false
		for token in name_excludes:
			if node_name.contains(token.to_lower()):
				excluded = true
				break
		if excluded:
			continue
		if mesh_instance.mesh == null:
			continue
		var xform := Transform3D.IDENTITY
		var walker: Node = mesh_instance
		while walker is Node3D:
			xform = (walker as Node3D).transform * xform
			if walker == instance:
				break
			walker = walker.get_parent()
		xform = Transform3D.IDENTITY.scaled(bake_scale) * xform
		var source_mesh := mesh_instance.mesh
		for surface_index in range(source_mesh.get_surface_count()):
			var arrays: Array = source_mesh.surface_get_arrays(surface_index)
			var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var vertex_count := source_vertices.size()
			var vertices := source_vertices.duplicate()
			for i in range(vertex_count):
				vertices[i] = xform * vertices[i]
				if vertices[i].y < min_y:
					min_y = vertices[i].y
			arrays[Mesh.ARRAY_VERTEX] = vertices
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				if source_normals.size() == vertex_count:
					var normals := source_normals.duplicate()
					for i in range(vertex_count):
						normals[i] = (xform.basis * normals[i]).normalized()
					arrays[Mesh.ARRAY_NORMAL] = normals
			baked_surfaces.append([arrays, source_mesh.surface_get_material(surface_index)])
	if recenter and min_y < 9.0e8:
		for entry in baked_surfaces:
			var arrays: Array = entry[0]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in range(vertices.size()):
				vertices[i].y -= min_y
			arrays[Mesh.ARRAY_VERTEX] = vertices
	for entry in baked_surfaces:
		var arrays: Array = entry[0]
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if entry[1] != null:
			result.surface_set_material(result.get_surface_count() - 1, entry[1])
	instance.queue_free()
	if result.get_surface_count() == 0:
		return null
	_soften_mesh_alpha(result)
	return result


static func _collect_mesh_instances(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		into.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, into)


static func _scatter_shore_rocks(coast: Node3D, mesh: ArrayMesh, budget: int) -> MultiMeshInstance3D:
	return _scatter_rock_clusters(coast, mesh, budget, 1.0, 0.55, 0.95)


static func _scatter_rock_clusters(coast: Node3D, mesh: ArrayMesh, budget: int, seed: float, scale_min: float, scale_max: float) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = budget
	# A handful of cluster anchors along the beach and cliff toes, 2-3 stones each.
	var anchors: Array[Vector2] = [
		Vector2(-14.0 + seed, 2.8), Vector2(-8.5 + seed * 0.3, 1.4),
		Vector2(-3.2 - seed * 0.2, 3.6), Vector2(3.8 + seed * 0.4, 2.2),
		Vector2(9.2 - seed * 0.25, 4.1), Vector2(14.5 + seed * 0.15, 2.6),
		Vector2(-16.0, 8.5 + seed), Vector2(15.8, 8.2 - seed * 0.3),
		Vector2(-6.4 + seed, 11.5), Vector2(7.1 - seed * 0.4, 12.0),
	]
	var placed := 0
	var member := 0
	for anchor in anchors:
		var group := 2 if placed + 3 > budget else 3
		for i in range(group):
			if placed >= budget:
				break
			var hint: Vector2 = coast.walk_to_land(anchor.x, anchor.y, 0.05)
			var px: float = hint.x + sin(seed * 5.1 + float(member) * 2.3) * 1.15
			var pz: float = hint.y + cos(seed * 3.7 + float(member) * 1.9) * 0.95
			var py: float = coast._terrain_height(px, pz)
			if not coast.is_rock_ground(px, pz):
				var wet: Vector2 = coast.walk_to_land(px, pz, 0.05)
				px = wet.x
				pz = wet.y
				py = coast._terrain_height(px, pz)
			if coast.is_rock_ground(px, pz) and _clear_of_ship(px, pz):
				var yaw := sin(px * 2.4 + pz * 1.7 + seed) * TAU
				var scale := lerpf(scale_min, scale_max, 0.5 + 0.5 * sin(px * 3.2 + pz * 1.1 + seed))
				var bury := scale * lerpf(0.42, 0.58, 0.5 + 0.5 * cos(pz + seed))
				var tilt := sin(pz * 1.9 + seed) * 0.16
				var basis := Basis.from_euler(Vector3(tilt, yaw, -tilt * 0.4)).scaled(Vector3(scale, scale * lerpf(0.72, 1.05, 0.5 + 0.5 * cos(px)), scale))
				multi.set_instance_transform(placed, Transform3D(basis, Vector3(px, py - bury, pz)))
				placed += 1
			member += 1
	multi.visible_instance_count = placed
	instance.set_meta("placed_count", placed)
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_apply_distance_fade(instance, 90.0)
	return instance


static func _apply_distance_fade(instance: GeometryInstance3D, fade_end: float) -> void:
	instance.visibility_range_end = fade_end
	instance.visibility_range_end_margin = maxf(8.0, fade_end * 0.16)
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


static func _apply_rock_shader(mesh: ArrayMesh) -> void:
	for surface_index in range(mesh.get_surface_count()):
		var src := mesh.surface_get_material(surface_index)
		var mat := ShaderMaterial.new()
		mat.shader = ROCK_SHADER
		if src is BaseMaterial3D:
			var base := src as BaseMaterial3D
			mat.set_shader_parameter("albedo_tex", base.albedo_texture)
			mat.set_shader_parameter("normal_tex", base.normal_texture)
			mat.set_shader_parameter("rough_tex", base.roughness_texture)
		mat.set_shader_parameter("moss_tex", MOSS_ALBEDO)
		mat.set_shader_parameter("sea_level", -0.35)
		mesh.surface_set_material(surface_index, mat)


static func landmass_pbr_material() -> ShaderMaterial:
	return _landmass_material(Color(0.62, 0.86, 0.48), Color(0.90, 0.88, 0.84))


static func cliff_pbr_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLIFF_SHADER
	material.set_shader_parameter("rock_albedo", ROCK_ALBEDO)
	material.set_shader_parameter("rock_normal", ROCK_NORMAL)
	material.set_shader_parameter("rock_rough", ROCK_ROUGH)
	material.set_shader_parameter("grass_albedo", GRASS_ALBEDO)
	material.set_shader_parameter("grass_normal", GRASS_NORMAL)
	material.set_shader_parameter("grass_rough", GRASS_ROUGH)
	material.set_shader_parameter("rock_tint", Color(0.84, 0.78, 0.70))
	material.set_shader_parameter("grass_tint", Color(0.34, 0.52, 0.22))
	material.set_shader_parameter("sea_level", -0.35)
	return material


static func cliff_ridge_mesh(length: float, height: float, depth: float, seed: float, layers: int = 8, segments: int = 9) -> ArrayMesh:
	# Steep shore face, a mid-height ledge, gentler vegetated back slope.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for layer in range(layers + 1):
		var row: Array = []
		var v := float(layer) / float(layers)
		for seg in range(segments + 1):
			var u := float(seg) / float(segments)
			row.append(_ridge_point(u, v, length, height, depth, seed))
		grid.append(row)
	for layer in range(layers):
		for seg in range(segments):
			var a: Vector3 = grid[layer][seg]
			var b: Vector3 = grid[layer][seg + 1]
			var c: Vector3 = grid[layer + 1][seg + 1]
			var d: Vector3 = grid[layer + 1][seg]
			_st_tri(st, a, b, c)
			_st_tri(st, a, c, d)
	# End caps so the ridge is a closed, grounded volume.
	for cap_u in [0.0, 1.0]:
		var col := 0 if cap_u == 0.0 else segments
		for layer in range(layers):
			var a: Vector3 = grid[layer][col]
			var b: Vector3 = grid[layer + 1][col]
			var toe := Vector3((cap_u - 0.5) * length, -0.5, 0.0)
			if cap_u == 0.0:
				_st_tri(st, toe, b, a)
			else:
				_st_tri(st, toe, a, b)
	st.generate_tangents()
	st.index()
	return st.commit()


static func _ridge_point(u: float, v: float, length: float, height: float, depth: float, seed: float) -> Vector3:
	var x := (u - 0.5) * length
	var envelope := 1.0 - pow(absf(u - 0.5) * 2.0, 2.15)
	var peaks := 0.58 + 0.42 * (0.50 * sin(u * TAU * 2.15 + seed) + 0.32 * sin(u * TAU * 3.7 + seed * 1.6) + 0.18 * sin(u * TAU * 6.4 + seed * 0.7))
	var crest_h := height * envelope * peaks
	var z := 0.0
	var y := 0.0
	if v < 0.34:
		# Almost-vertical shore face.
		var tv := v / 0.34
		z = -depth * 0.18 + tv * depth * 0.10
		y = lerpf(-0.55, crest_h * 0.84, pow(tv, 0.72))
	elif v < 0.46:
		var tv := (v - 0.34) / 0.12
		z = -depth * 0.08 + tv * depth * 0.06
		y = crest_h * 0.84 + sin(tv * PI) * 0.16
	elif v < 0.62:
		var tv := (v - 0.46) / 0.16
		z = -depth * 0.02 + tv * depth * 0.22
		y = lerpf(crest_h * 0.88, crest_h, tv)
	else:
		var tv := (v - 0.62) / 0.38
		z = depth * 0.20 + tv * depth * 0.42
		y = lerpf(crest_h, -0.40, pow(tv, 1.35))
	y += 0.28 * sin(u * 17.0 + seed) * sin(v * 8.0 + seed * 0.5)
	z += 0.20 * sin(u * 11.0 + seed * 2.0)
	return Vector3(x, y, z)


static func _st_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Per-face normals keep the shore wall from smoothing into a grassy hill.
	# UVs are required for generate_tangents(); the shader is triplanar.
	var normal := (c - a).cross(b - a)
	if normal.length_squared() > 0.000001:
		normal = normal.normalized()
	else:
		normal = Vector3.UP
	st.set_normal(normal)
	st.set_uv(Vector2(a.x, a.z) * 0.12)
	st.add_vertex(a)
	st.set_normal(normal)
	st.set_uv(Vector2(b.x, b.z) * 0.12)
	st.add_vertex(b)
	st.set_normal(normal)
	st.set_uv(Vector2(c.x, c.z) * 0.12)
	st.add_vertex(c)


static func _vine_card_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Crossed hanging cards. Origin is the attachment at the top of the cliff.
	var hw := 0.55
	var drop := 3.6
	for yaw in [0.0, 1.5708]:
		var c := cos(yaw)
		var s := sin(yaw)
		var a := Vector3(-hw * c, 0.05, -hw * s)
		var b := Vector3(hw * c, 0.05, hw * s)
		var c2 := Vector3(hw * c, -drop, hw * s)
		var d := Vector3(-hw * c, -drop, -hw * s)
		_st_tri_uv(st, a, b, c2, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
		_st_tri_uv(st, a, c2, d, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))
	st.generate_normals()
	st.generate_tangents()
	st.index()
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.albedo_texture = VINE_ALBEDO
	material.albedo_color = Color(0.55, 0.62, 0.40, 1.0)
	_soften_foliage_material(material)
	material.roughness = 0.9
	material.metallic = 0.0
	mesh.surface_set_material(0, material)
	return mesh


static func _st_tri_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var normal := (c - a).cross(b - a)
	if normal.length_squared() > 0.000001:
		normal = normal.normalized()
	else:
		normal = Vector3.FORWARD
	st.set_normal(normal)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(normal)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(normal)
	st.set_uv(uc)
	st.add_vertex(c)


static func _scatter_cliff_vines(coast: Node3D, mesh: ArrayMesh, budget: int) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = budget
	var placed := 0
	var x := -24.0
	while x <= 24.0 and placed < budget:
		var z := 0.0
		while z <= 24.0 and placed < budget:
			var px := x + sin(x * 3.7 + z) * 0.6
			var pz := z + cos(x * 2.2) * 0.4
			var py: float = coast._terrain_height(px, pz)
			var gx: float = coast._terrain_height(px + 1.0, pz) - coast._terrain_height(px - 1.0, pz)
			var gz: float = coast._terrain_height(px, pz + 1.0) - coast._terrain_height(px, pz - 1.0)
			var slope := sqrt(gx * gx + gz * gz)
			if coast.is_foliage_ground(px, pz) and py > 2.6 and slope > 1.2:
				var yaw := atan2(gx, gz) + PI + sin(px * 2.1) * 0.25
				var scale := lerpf(1.05, 1.7, 0.5 + 0.5 * sin(px * 4.0 + pz))
				var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
				multi.set_instance_transform(placed, Transform3D(basis, Vector3(px, py + 0.15, pz)))
				placed += 1
			z += 1.6
		x += 1.5
	multi.visible_instance_count = placed
	instance.set_meta("placed_count", placed)
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_distance_fade(instance, 80.0)
	return instance


static func _scatter_hero_flowers(coast: Node3D, mesh: ArrayMesh, anchors: PackedVector3Array, scale_min: float, scale_max: float) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = anchors.size()
	var placed := 0
	for i in range(anchors.size()):
		var anchor: Vector3 = anchors[i]
		var landed: Vector2 = coast.walk_to_land(anchor.x, anchor.z, coast.FOLIAGE_MIN_ABOVE_SEA)
		var px := landed.x
		var pz := landed.y
		if not _clear_of_ship(px, pz) or not coast.is_foliage_ground(px, pz):
			continue
		var py: float = coast._terrain_height(px, pz)
		var yaw := sin(px * 2.8 + pz * 1.3) * 6.28
		var scale := lerpf(scale_min, scale_max, 0.5 + 0.5 * sin(px * 3.3 + pz))
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale * 0.95, scale))
		multi.set_instance_transform(placed, Transform3D(basis, Vector3(px, py, pz)))
		placed += 1
	multi.visible_instance_count = placed
	instance.set_meta("placed_count", placed)
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_distance_fade(instance, 64.0)
	return instance




static func _apply_crag_shader(mesh: ArrayMesh) -> void:
	for surface_index in range(mesh.get_surface_count()):
		var src := mesh.surface_get_material(surface_index)
		var mat := ShaderMaterial.new()
		mat.shader = CLIFF_SHADER
		if src is BaseMaterial3D:
			var base := src as BaseMaterial3D
			mat.set_shader_parameter("rock_albedo", base.albedo_texture if base.albedo_texture else ROCK_ALBEDO)
			mat.set_shader_parameter("rock_normal", base.normal_texture if base.normal_texture else ROCK_NORMAL)
			mat.set_shader_parameter("rock_rough", base.roughness_texture if base.roughness_texture else ROCK_ROUGH)
		else:
			mat.set_shader_parameter("rock_albedo", ROCK_ALBEDO)
			mat.set_shader_parameter("rock_normal", ROCK_NORMAL)
			mat.set_shader_parameter("rock_rough", ROCK_ROUGH)
		mat.set_shader_parameter("grass_albedo", GRASS_ALBEDO)
		mat.set_shader_parameter("grass_normal", GRASS_NORMAL)
		mat.set_shader_parameter("grass_rough", GRASS_ROUGH)
		mat.set_shader_parameter("rock_tint", Color(0.86, 0.80, 0.72))
		mat.set_shader_parameter("grass_tint", Color(0.38, 0.56, 0.26))
		mat.set_shader_parameter("sea_level", -0.35)
		mesh.surface_set_material(surface_index, mat)

static func _apply_leaf_scissor(mesh: ArrayMesh) -> void:
	for surface_index in range(mesh.get_surface_count()):
		var mat := mesh.surface_get_material(surface_index) as StandardMaterial3D
		if mat == null:
			continue
		var n := str(mat.resource_name).to_lower()
		if not (n.contains("leaf") or n.contains("leaves")):
			continue
		var foliage := mat.duplicate() as StandardMaterial3D
		_soften_foliage_material(foliage)
		mesh.surface_set_material(surface_index, foliage)


static func _driftwood_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two slightly offset tapered logs, origin at the underside so they rest on sand.
	for log_i in range(2):
		var ox := -0.15 + float(log_i) * 0.55
		var oz := float(log_i) * 0.18
		var yaw := 0.35 if log_i == 0 else -0.55
		var c := cos(yaw)
		var s := sin(yaw)
		var length := 1.7 if log_i == 0 else 1.05
		var rad := 0.13 if log_i == 0 else 0.10
		for seg in range(5):
			var t0 := float(seg) / 5.0
			var t1 := float(seg + 1) / 5.0
			var r0 := rad * lerpf(1.0, 0.55, t0)
			var r1 := rad * lerpf(1.0, 0.55, t1)
			var x0 := (t0 - 0.5) * length
			var x1 := (t1 - 0.5) * length
			var y0 := 0.08 + 0.04 * sin(t0 * PI)
			var y1 := 0.08 + 0.04 * sin(t1 * PI)
			# Square cross-section, cheap on mobile.
			var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
			for k in range(4):
				var a: Vector2 = corners[k]
				var b: Vector2 = corners[(k + 1) % 4]
				var p0 := Vector3((x0 * c - (a.x * r0 + oz) * s) + ox, y0 + a.y * r0, x0 * s + (a.x * r0 + oz) * c)
				var p1 := Vector3((x1 * c - (a.x * r1 + oz) * s) + ox, y1 + a.y * r1, x1 * s + (a.x * r1 + oz) * c)
				var p2 := Vector3((x1 * c - (b.x * r1 + oz) * s) + ox, y1 + b.y * r1, x1 * s + (b.x * r1 + oz) * c)
				var p3 := Vector3((x0 * c - (b.x * r0 + oz) * s) + ox, y0 + b.y * r0, x0 * s + (b.x * r0 + oz) * c)
				_st_tri(st, p0, p1, p2)
				_st_tri(st, p0, p2, p3)
	st.generate_tangents()
	st.index()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = WOOD_ALBEDO
	mat.normal_texture = WOOD_NORMAL
	mat.roughness_texture = WOOD_ROUGH
	mat.albedo_color = Color(0.72, 0.58, 0.42)
	mat.roughness = 0.92
	mat.metallic = 0.0
	mesh.surface_set_material(0, mat)
	return mesh


static func _scatter_beach_props(coast: Node3D, mesh: ArrayMesh, budget: int, seed: float, scale_min: float, scale_max: float, bury: float) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = budget
	var anchors: Array[Vector2] = [
		Vector2(-12.5 + seed, 3.4), Vector2(-8.2, 2.6 + seed * 0.2),
		Vector2(-3.6 - seed * 0.15, 3.8), Vector2(1.4 + seed * 0.2, 2.8),
		Vector2(5.8, 3.6 - seed * 0.1), Vector2(10.4 + seed * 0.1, 3.1),
		Vector2(14.2, 4.0), Vector2(-14.8, 5.2),
		Vector2(-5.0 + seed, 4.6), Vector2(7.6 - seed * 0.2, 4.8),
		Vector2(12.8, 5.4), Vector2(-1.2, 4.2),
	]
	var placed := 0
	for i in range(anchors.size()):
		if placed >= budget:
			break
		var hint: Vector2 = coast.walk_to_land(anchors[i].x, anchors[i].y, 0.08)
		var px: float = hint.x + sin(seed * 4.1 + float(i) * 2.2) * 0.8
		var pz: float = hint.y + cos(seed * 3.3 + float(i) * 1.6) * 0.55
		if not coast.is_beach_ground(px, pz):
			var wet: Vector2 = coast.walk_to_shore(px, pz, Vector2(0.0, -1.0))
			px = wet.x
			pz = wet.y
		if not coast.is_beach_ground(px, pz) or not _clear_of_ship(px, pz):
			continue
		var py: float = coast._terrain_height(px, pz)
		var yaw := sin(px * 1.7 + pz * 2.1 + seed) * TAU
		var scale := lerpf(scale_min, scale_max, 0.5 + 0.5 * sin(px * 2.4 + pz + seed))
		var tilt := sin(pz * 1.4 + seed) * 0.18
		var basis := Basis.from_euler(Vector3(tilt, yaw, -tilt * 0.3)).scaled(Vector3(scale, scale, scale))
		multi.set_instance_transform(placed, Transform3D(basis, Vector3(px, py - bury * scale, pz)))
		placed += 1
	multi.visible_instance_count = placed
	instance.set_meta("placed_count", placed)
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_apply_distance_fade(instance, 70.0)
	return instance


static func _scatter_summit_crags(coast: Node3D, mesh: ArrayMesh, budget: int, seed: float, scale_min: float, scale_max: float) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = budget
	# Stacked, buried, scaled-up mobile rocks on the two main summits and the saddle.
	var anchors: Array[Vector2] = [
		Vector2(-6.2, 15.8), Vector2(-5.1, 15.1), Vector2(-7.0, 16.4),
		Vector2(8.0, 17.6), Vector2(7.0, 16.8), Vector2(9.1, 18.2),
		Vector2(0.9, 16.7), Vector2(-1.2, 16.2), Vector2(6.2, 15.6),
		Vector2(-4.4, 17.0), Vector2(8.8, 16.4), Vector2(-6.8, 14.8),
	]
	var placed := 0
	for i in range(anchors.size()):
		if placed >= budget:
			break
		var px: float = anchors[i].x + sin(seed * 2.7 + float(i)) * 0.35
		var pz: float = anchors[i].y + cos(seed * 1.9 + float(i)) * 0.30
		var py: float = coast._terrain_height(px, pz)
		if not coast.is_rock_ground(px, pz) or py < 4.0:
			continue
		var yaw := sin(px * 1.1 + pz + seed) * TAU
		var scale := lerpf(scale_min, scale_max, 0.5 + 0.5 * sin(px * 0.7 + pz * 0.4 + seed))
		var bury := scale * lerpf(0.48, 0.62, 0.5 + 0.5 * cos(pz + seed))
		var tilt := 0.08 + 0.10 * sin(pz * 0.8 + seed)
		var basis := Basis.from_euler(Vector3(tilt, yaw, -tilt * 0.35)).scaled(Vector3(scale, scale * lerpf(0.95, 1.22, 0.5 + 0.5 * sin(px)), scale))
		multi.set_instance_transform(placed, Transform3D(basis, Vector3(px, py - bury, pz)))
		placed += 1
	multi.visible_instance_count = placed
	instance.set_meta("placed_count", placed)
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	instance.material_overlay = null
	_apply_distance_fade(instance, 110.0)
	return instance


static func _scatter_hut_understory(coast: Node3D, mesh: ArrayMesh, budget: int) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = budget
	var placed := 0
	for hut in _hut_spots:
		for i in range(6):
			if placed >= budget:
				break
			var ang := float(i) * TAU / 6.0 + sin(hut.x * 2.1) * 0.3
			var radius := 1.15 + 0.45 * (0.5 + 0.5 * sin(float(i) * 2.4 + hut.y))
			var px: float = hut.x + cos(ang) * radius
			var pz: float = hut.y + sin(ang) * radius
			if not coast.is_foliage_ground(px, pz) or not _clear_of_ship(px, pz):
				continue
			if Vector2(px, pz).distance_to(hut) < 0.95:
				continue
			var py: float = coast._terrain_height(px, pz)
			var yaw := ang + 0.4
			var scale := lerpf(0.85, 1.25, 0.5 + 0.5 * sin(px * 3.1 + pz))
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
			multi.set_instance_transform(placed, Transform3D(basis, Vector3(px, py, pz)))
			placed += 1
	multi.visible_instance_count = placed
	instance.set_meta("placed_count", placed)
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_distance_fade(instance, 58.0)
	return instance


static func _soften_foliage_material(material: StandardMaterial3D) -> void:
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.62
	material.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE_AND_TO_ONE
	material.alpha_antialiasing_edge = 0.35
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.cull_mode = BaseMaterial3D.CULL_DISABLED


static func _soften_mesh_alpha(mesh: ArrayMesh) -> void:
	if mesh == null:
		return
	for surface_index in range(mesh.get_surface_count()):
		var mat := mesh.surface_get_material(surface_index) as StandardMaterial3D
		if mat == null:
			continue
		var n := str(mat.resource_name).to_lower()
		var uses_cutout := mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or n.contains("leaf") or n.contains("leaves") or n.contains("frond") or n.contains("fern") or n.contains("grass")
		var foliage := mat.duplicate() as StandardMaterial3D
		if uses_cutout:
			_soften_foliage_material(foliage)
			if n.contains("leaf") or n.contains("leaves"):
				foliage.albedo_texture = LEAVES_COVERAGE
		else:
			foliage.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mesh.surface_set_material(surface_index, foliage)
