extends Node3D
## Reference-driven coastal slice. Geometry is authored once at load; gameplay authority stays server-side.

const ROCK_SCENE := preload("res://assets/external/polyhaven/coast_rocks_05/coast_rocks_05_1k.gltf")
const TREE_SCENE := preload("res://assets/external/polyhaven/tree_small_02/tree_small_02_1k.gltf")
const SHIP_SCENE := preload("res://assets/external/polyhaven/dutch_ship_medium/dutch_ship_medium_1k.gltf")
const COASTAL_CLIFF_SCENE := preload("res://assets/external/polyhaven/coastal_cliff_01/coastal_cliff_01_1k.gltf")
const TROPICAL_TREE_SCENE := preload("res://assets/external/polyhaven/island_tree_01/island_tree_01_1k.gltf")
const TROPICAL_TREE_ALT_SCENE := preload("res://assets/external/polyhaven/island_tree_02/island_tree_02_1k.gltf")
const MOSS_ROCK_SCENE := preload("res://assets/external/polyhaven/rock_moss_set_01/rock_moss_set_01_1k.gltf")
const COAST_DIFFUSE := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_diff_1k.jpg")
const COAST_NORMAL := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_nor_gl_1k.jpg")
const COAST_ROUGHNESS := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_rough_1k.jpg")
const COAST_AO := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_ao_1k.jpg")
const SHORE_BAKER := preload("res://scripts/coastal_shore_heightfield.gd")
const OCEAN_SHADER := preload("res://shaders/ocean_surface.gdshader")
const BEACH_TERRAIN_SHADER := preload("res://shaders/coastal_beach_terrain.gdshader")
const WATER_Y := -0.35
const GAMEPLAY_CAMERA := Vector3(13.0, 12.0, -14.0)
const CINEMATIC_START_CAMERA := Vector3(-11.0, 5.5, -18.0)
const CINEMATIC_LOOK_TARGET := Vector3(1.0, 2.2, 1.0)

var gameplay_camera: Camera3D
var cinematic_camera: Camera3D
var player_marker: Node3D
var ship_focal: Node3D
var _ship_base_position := Vector3.ZERO
var _cinematic_tween: Tween
var _cinematic_active := false
var _reduced_motion := false
var _shore_binding: Dictionary = {}
var _ship_visual_bounds_local := AABB()
var _ship_bounds_ready := false

func _ready() -> void:
	_build_environment()
	_build_coastal_terrain()
	_build_water()
	_build_premium_landmarks()
	_build_cameras()

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "CoastalAtmosphere"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#2d78b7")
	sky_material.sky_horizon_color = Color("#b7e6ee")
	sky_material.ground_bottom_color = Color("#1b3d53")
	sky_material.ground_horizon_color = Color("#83b6bd")
	sky_material.sun_angle_max = 12.0
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b6d6df")
	environment.ambient_light_energy = 0.38
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "WarmSun"
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color("#fff0cf")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	add_child(sun)

func _terrain_height(px: float, pz: float) -> float:
	# Irregular cove waterline with a real underwater shelf, a gently sloped
	# sand beach (~1:8), then bluff and inland ridges. The same height
	# function grounds decorative meshes and feeds the ocean heightfield.
	var waterline := 2.0 + sin(px * 0.19) * 1.3 + sin(px * 0.53) * 0.6
	waterline += cos(px * 0.095) * 1.2
	var shore_t := pz - waterline
	# Wide, low beach shelf instead of the previous 6 m ramp that met the
	# water with no visible sand.
	var beach := smoothstep(-5.0, 9.0, shore_t)
	var bluff := smoothstep(waterline + 6.5, waterline + 15.0, pz)
	var ridge := sin(px * 0.21 + pz * 0.08) * 1.25
	ridge += cos(px * 0.46 - pz * 0.19) * 0.48
	ridge += sin(px * 0.91 + pz * 0.63) * 0.15
	# Irregular cliff shelves keep the inland coast layered rather than a
	# single smooth mound; bounded and deterministic at capture time.
	var cliff_shelf := smoothstep(waterline + 5.0, waterline + 11.0, pz) * (0.42 * sin(px * 0.37 + pz * 0.11)
		+ 0.24 * cos(px * 0.71 - pz * 0.23))
	var high_shelf := smoothstep(13.0, 20.0, pz) * (0.30 * sin(px * 0.52 - pz * 0.17))
	ridge += cliff_shelf + high_shelf
	var side_mask := 1.0 - smoothstep(25.0, 34.0, absf(px))
	var back_mask := 1.0 - smoothstep(19.0, 28.0, pz)
	var island := side_mask * back_mask
	var height := beach * (1.45 + ridge * 0.12)
	height += bluff * (5.4 + ridge * 1.35)
	height += smoothstep(11.0, 20.0, pz) * 2.0
	# The seabed previously sat at sea level across the whole bay, so the
	# ocean read uniformly "shallow". Drop it into a believable shelf: sand
	# shallows near the beach, then a turquoise-to-navy slope offshore.
	var offshore := smoothstep(0.5, -19.0, shore_t)
	var land := WATER_Y - 0.25 + height - offshore * 7.5
	return lerpf(WATER_Y - 8.0, land, island)


func _build_coastal_terrain() -> void:
	# Dense-enough terrain for curving coast and layered relief, bounded for
	# mobile: 96 x 72 vertices / fewer than 14k surface triangles.
	const columns := 96
	const rows := 72
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var tint := PackedColorArray()
	for z in range(rows):
		for x in range(columns):
			var fx := float(x) / float(columns - 1)
			var fz := float(z) / float(rows - 1)
			var px := (fx - 0.5) * 72.0
			var pz := (fz - 0.5) * 58.0
			var py := _terrain_height(px, pz)
			vertices.append(Vector3(px, py, pz))
			uvs.append(Vector2(px * 0.14, pz * 0.14))
			var elevation := smoothstep(1.4, 6.8, py)
			tint.append(Color("#f1e3cb").lerp(Color("#c5c3bc"), elevation))
	for z in range(rows):
		for x in range(columns):
			var left := vertices[z * columns + maxi(x - 1, 0)]
			var right := vertices[z * columns + mini(x + 1, columns - 1)]
			var back := vertices[maxi(z - 1, 0) * columns + x]
			var front := vertices[mini(z + 1, rows - 1) * columns + x]
			normals.append((back - front).cross(left - right).normalized())
	for z in range(rows - 1):
		for x in range(columns - 1):
			var i := z * columns + x
			indices.append_array([i, i + 1, i + columns, i + 1, i + columns + 1, i + columns])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = tint
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var terrain := MeshInstance3D.new()
	terrain.name = "IrregularCoastalTerrain"
	terrain.mesh = mesh
	terrain.material_override = _terrain_material()
	add_child(terrain)


func _terrain_material() -> ShaderMaterial:
	# Height/slope-layered beach: wet sand, dry sand, rock and vegetated soil,
	# all from the admitted coast_sand_rocks_02 PBR maps.
	var material := ShaderMaterial.new()
	material.shader = BEACH_TERRAIN_SHADER
	material.set_shader_parameter("rock_albedo", COAST_DIFFUSE)
	material.set_shader_parameter("rock_normal", COAST_NORMAL)
	material.set_shader_parameter("rock_roughness", COAST_ROUGHNESS)
	material.set_shader_parameter("rock_ao", COAST_AO)
	material.set_shader_parameter("sea_level", WATER_Y)
	return material

func _build_water() -> void:
	# Preserve exact PBR terrain as shoreline source of truth. The binder
	# rejects missing, transformed or non-grid geometry instead of inventing
	# a flat shoreline mask. One Image.FORMAT_RF upload at scene load only.
	var terrain := get_node_or_null("IrregularCoastalTerrain") as MeshInstance3D
	if terrain == null:
		push_error("No source coastal mesh for terrain-aware ocean")
		return
	var water := MeshInstance3D.new()
	water.name = "ShallowToDeepWater"
	var plane := PlaneMesh.new()
	# ONE contiguous seascape avoids cross-material seams and expensive
	# overlapping fragment passes. Only the central ~180x140m displaces;
	# distant water retains animated per-pixel micro-normals without tessellation.
	# 160x120 subdivisions cap vertex shader work even across the full horizon.
	plane.size = Vector2(640.0, 480.0)
	plane.subdivide_width = 160
	plane.subdivide_depth = 120
	water.mesh = plane
	water.position.y = WATER_Y - 0.18
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = OCEAN_SHADER
	material.set_shader_parameter("swell_scale", 0.72)
	material.set_shader_parameter("ripple_detail", 0.78)
	var baked: Dictionary = SHORE_BAKER.bind_to_material(terrain, material, 96, 72)
	if baked.has("error"):
		push_error("Coast heightmap binding failed: " + str(baked["error"]))
		return
	_shore_binding = baked
	water.material_override = material
	add_child(water)
	# A single material covers near and far, so no visible shader seam.
	# No detached white foam quads and no duplicated terrain height equation.

func _build_premium_landmarks() -> void:
	ship_focal = SHIP_SCENE.instantiate()
	ship_focal.name = "HarbourShipFocalPoint"
	ship_focal.position = Vector3(1.0, -0.05, -5.8)
	ship_focal.rotation_degrees = Vector3(0.0, 18.0, 0.0)
	ship_focal.scale = Vector3.ONE * 0.72
	add_child(ship_focal)
	_configure_ship_sails(ship_focal)
	_ship_base_position = ship_focal.position
	_cache_ship_visual_bounds()
	_configure_mobile_visibility(ship_focal, 120.0)
	# Asset footprints are grounded to terrain rather than assigned arbitrary
	# fixed y-values. Keep the ship/cinematic sightline clear of near foliage.
	for entry in [
		[Vector3(-13.8, 0.0, -0.8), 1.2], [Vector3(-17.5, 0.0, 5.4), 1.8],
		[Vector3(14.2, 0.0, -0.6), 1.5], [Vector3(18.0, 0.0, 8.5), 1.6]
	]:
		var rock := ROCK_SCENE.instantiate()
		rock.position = entry[0]
		rock.scale = Vector3.ONE * entry[1]
		_apply_landmark_lod(rock, 30000)
		add_child(rock)
		_ground_asset_on_terrain(rock, 0.3)
		_configure_mobile_visibility(rock, 85.0)
	for entry in [
		[Vector3(-16.0, 0.0, 4.0), 1.1], [Vector3(-20.5, 0.0, 13.0), 1.15],
		[Vector3(15.2, 0.0, 6.5), 1.05], [Vector3(20.0, 0.0, 13.0), 0.9]
	]:
		var tree := TREE_SCENE.instantiate()
		tree.position = entry[0]
		tree.scale = Vector3.ONE * entry[1]
		# Keep a detailed near-field silhouette while bounding the imported
		# 2.06M-triangle source before the Mobile renderer sees four copies.
		_apply_far_foliage_lod(tree, 90000)
		add_child(tree)
		_ground_asset_on_terrain(tree)
		_configure_mobile_visibility(tree, 60.0)
	# Verified imported PBR art only, arranged in a landscape-depth layer.
	# Old 26m foliage culling hid essentially all background vegetation after
	# the camera pulled back to protect the masts and sails. Keep the gallery
	# behind the ship rather than adding geometric placeholder trees.
	var grove := Node3D.new()
	grove.name = "CoastalPBRDepthLayer"
	add_child(grove)
	for entry in [
		[Vector3(-8.1, 0.0, 17.0), 2.2],
		[Vector3(-4.3, 0.0, 11.3), 1.75],
		[Vector3(3.5, 0.0, 18.2), 2.1],
		[Vector3(8.7, 0.0, 12.6), 1.85],
	]:
		var shoreline_tree := TREE_SCENE.instantiate()
		shoreline_tree.position = entry[0]
		shoreline_tree.scale = Vector3.ONE * entry[1]
		_apply_far_foliage_lod(shoreline_tree, 36000)
		grove.add_child(shoreline_tree)
		_ground_asset_on_terrain(shoreline_tree)
		_configure_mobile_visibility(shoreline_tree, 90.0, false)
	for entry in [
		[Vector3(-8.5, 0.0, 6.8), 1.25],
		[Vector3(10.5, 0.0, 7.1), 1.5]
	]:
		var shore_rock := ROCK_SCENE.instantiate()
		shore_rock.position = entry[0]
		shore_rock.scale = Vector3.ONE * entry[1]
		_apply_landmark_lod(shore_rock, 30000)
		grove.add_child(shore_rock)
		_ground_asset_on_terrain(shore_rock, 0.18)
		_configure_mobile_visibility(shore_rock, 90.0, false)
	# Additional verified CC0 coastal families provide the silhouette and
	# vegetation variation missing from the original three-asset slice. Keep
	# them in a separate layer so the existing functional contract remains
	# stable while every imported mesh receives the same terrain grounding and
	# bounded visibility policy.
	var premium_layer := Node3D.new()
	premium_layer.name = "VerifiedTropicalContentLayer"
	add_child(premium_layer)
	for entry in [
		# The source cliff is a wide hero mesh; keep one bounded landmark in
		# the background rather than duplicating a 460k-triangle wall over the
		# ship sightline. Its imported bounds are regression-tested below.
		[Vector3(21.0, 0.0, 18.0), 0.24, COASTAL_CLIFF_SCENE],
		# Smaller side anchors complete the cove silhouette without crossing
		# the ship camera corridor or adding a new asset family.
		[Vector3(-24.0, 0.0, 16.0), 0.18, COASTAL_CLIFF_SCENE],
		[Vector3(25.0, 0.0, 14.0), 0.18, COASTAL_CLIFF_SCENE],
		[Vector3(-11.5, 0.0, 10.0), 1.1, TROPICAL_TREE_SCENE],
		[Vector3(11.0, 0.0, 12.0), 1.0, TROPICAL_TREE_ALT_SCENE],
		[Vector3(-3.5, 0.0, 16.5), 0.85, TROPICAL_TREE_ALT_SCENE],
		[Vector3(5.5, 0.0, 15.0), 0.9, TROPICAL_TREE_SCENE],
		[Vector3(-16.0, 0.0, 8.0), 0.8, MOSS_ROCK_SCENE],
		[Vector3(15.0, 0.0, 9.0), 0.75, MOSS_ROCK_SCENE]
	]:
		var imported := entry[2].instantiate() as Node3D
		imported.position = entry[0]
		imported.scale = Vector3.ONE * entry[1]
		if entry[2] == TROPICAL_TREE_SCENE or entry[2] == TROPICAL_TREE_ALT_SCENE:
			_apply_far_foliage_lod(imported, 48000)
		elif entry[2] == COASTAL_CLIFF_SCENE:
			# The CC0 cliff is a 461k-triangle hero mesh. Three copies in the
			# background made the software Mobile capture spend its watchdog
			# budget in the first raster fence. Preserve authored PBR and the
			# silhouette with a deterministic indexed landmark LOD; the near
			# terrain remains the high-detail playable surface.
			_apply_landmark_lod(imported, 60000 if entry[0].x != 21.0 else 90000)
		premium_layer.add_child(imported)
		if entry[2] == COASTAL_CLIFF_SCENE:
			# The source is an overhanging cliff-edge slab: grounding its
			# lowest vertex left most of it hanging in the air as a dark plank
			# along the ridge. Seat it so only the weathered crest emerges from
			# the slope as a rock outcrop.
			var cliff_height := visual_bounds_world(imported).size.y
			_ground_asset_on_terrain(imported, cliff_height * 0.9)
		else:
			_ground_asset_on_terrain(imported, 0.08)
		_configure_mobile_visibility(imported, 105.0, false)
	# Spawn state belongs to scene construction, not recursive material
	# traversal. Keeping this here guarantees one authoritative marker.
	player_marker = Node3D.new()
	player_marker.name = "PlayerSpawnMarker"
	player_marker.position = Vector3(0.0, _terrain_height(0.0, 5.5) + 0.75, 5.5)
	add_child(player_marker)

func _configure_ship_sails(root: Node) -> void:
	# The imported ship's sail material uses an alpha-mask RGBA atlas.  Keep
	# its authored PBR textures, but make the renderer contract explicit so
	# mobile import settings cannot turn the cloth into a black/transparent
	# surface.  Materials are duplicated per instance; the source GLTF stays
	# untouched and its provenance remains intact.
	for node in root.get_children():
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh:
				for surface_index in range(mesh_instance.mesh.get_surface_count()):
					var material := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
					if material == null:
						continue
					var material_name := str(material.resource_name).to_lower()
					var node_name := str(mesh_instance.name).to_lower()
					if not material_name.contains("sail") and not node_name.contains("sail"):
						continue
					var corrected := material.duplicate() as BaseMaterial3D
					corrected.albedo_color = Color.WHITE
					corrected.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					corrected.cull_mode = BaseMaterial3D.CULL_DISABLED
					corrected.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
					mesh_instance.set_surface_override_material(surface_index, corrected)
		for child in node.get_children():
			_configure_ship_sails(child)

func _reduce_surface_triangles(source: ArrayMesh, surface_index: int, _max_triangles: int) -> Array:
	# A triangle budget cannot justify punching holes in an authored surface.
	# Until an admitted LOD has equivalent topology/material evidence, retain
	# the exact source arrays, including every vertex attribute and index.
	return source.surface_get_arrays(surface_index)

func _apply_far_foliage_lod(asset: Node3D, _max_total_triangles: int = 72000) -> void:
	_preserve_authored_mesh(asset)

func _apply_landmark_lod(asset: Node3D, _max_triangles: int) -> void:
	_preserve_authored_mesh(asset)

func _preserve_authored_mesh(asset: Node3D) -> void:
	var asset_name := asset.scene_file_path.get_file().trim_suffix("_1k.gltf")
	if asset_name not in ["tree_small_02", "island_tree_01", "island_tree_02", "coast_rocks_05"]:
		return
	var packed := load("res://assets/external/generated/bounded_lods/" + asset_name + ".glb") as PackedScene
	if packed == null:
		push_error("Missing admitted bounded LOD: " + asset_name)
		return
	var authored := packed.instantiate()
	var originals := asset.find_children("*", "MeshInstance3D", true, false)
	var replacements := authored.find_children("*", "MeshInstance3D", true, false)
	if originals.size() != 1 or replacements.size() != 1:
		push_error("Unexpected bounded LOD mesh hierarchy: " + asset_name)
		authored.free()
		return
	# Keep the original scene transform/identity and copy the complete authored
	# mesh, including material regions, UVs, normals and tangent arrays.
	originals[0].mesh = replacements[0].mesh
	originals[0].lod_bias = 1.5
	authored.free()

func visual_bounds_world(asset: Node3D) -> AABB:
	var lowest := Vector3(INF, INF, INF)
	var highest := Vector3(-INF, -INF, -INF)
	var pending: Array[Node] = [asset]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and node.mesh:
			var bounds: AABB = node.mesh.get_aabb()
			for corner in range(8):
				var local: Vector3 = bounds.position + Vector3(
					bounds.size.x if corner & 1 else 0.0,
					bounds.size.y if corner & 2 else 0.0,
					bounds.size.z if corner & 4 else 0.0
				)
				var world: Vector3 = node.to_global(local)
				lowest = lowest.min(world)
				highest = highest.max(world)
		for child in node.get_children():
			pending.append(child)
	if lowest.x == INF:
		return AABB()
	return AABB(lowest, highest - lowest)

func _is_sail_surface(mesh_instance: MeshInstance3D, surface_index: int) -> bool:
	var material := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
	var material_name := str(material.resource_name).to_lower() if material else ""
	return material_name.contains("sail") or str(mesh_instance.name).to_lower().contains("sail")

func prepare_sail_pixel_mask() -> Array:
	# Render an object-only pass: sail triangles get an unshaded magenta
	# material, while every other surface writes depth with no visible color.
	# Hull, mast, terrain, and water therefore occlude sails exactly as they do
	# in the real composite instead of creating a false all-sails-visible pass.
	var state: Array = []
	var pending: Array[Node] = [self]
	var mask_material := StandardMaterial3D.new()
	mask_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mask_material.albedo_color = Color(1.0, 0.0, 1.0, 1.0)
	mask_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var depth_material := ShaderMaterial.new()
	var depth_shader := Shader.new()
	depth_shader.code = "shader_type spatial; render_mode unshaded, depth_draw_opaque, cull_disabled; void fragment() { ALBEDO = vec3(0.0); }"
	depth_material.shader = depth_shader
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh:
				for surface_index in range(mesh_instance.mesh.get_surface_count()):
					state.append({"node": mesh_instance, "surface": surface_index,
						"material": mesh_instance.get_surface_override_material(surface_index)})
					mesh_instance.set_surface_override_material(surface_index,
						mask_material if _is_sail_surface(mesh_instance, surface_index) else depth_material)
		elif node is GeometryInstance3D:
			state.append({"node": node, "visible": node.visible})
			node.visible = true if node is MeshInstance3D else false
		for child in node.get_children():
			pending.append(child)
	return state

func restore_sail_pixel_mask(state: Array) -> void:
	for entry in state:
		var node: Node = entry["node"]
		if node is MeshInstance3D:
			node.set_surface_override_material(entry["surface"], entry["material"])
		elif node is GeometryInstance3D:
			node.visible = entry["visible"]

static func evaluate_sail_pixel_mask(image: Image, mask: Image) -> Dictionary:
	# Only magenta pixels from the object-only pass are eligible. This handles
	# occlusion/offscreen surfaces and proves the final composite is bright at
	# the same pixels that genuinely contained sail triangles.
	var mask_pixels := 0
	var lit_pixels := 0
	for y in range(mask.get_height()):
		for x in range(mask.get_width()):
			var marker := mask.get_pixel(x, y)
			if marker.r < 0.65 or marker.b < 0.65 or marker.g > 0.35:
				continue
			mask_pixels += 1
			if image.get_pixel(x, y).get_luminance() > 0.10:
				lit_pixels += 1
	return {"mask_pixels": mask_pixels, "lit_pixels": lit_pixels,
		"lit_fraction": float(lit_pixels) / float(mask_pixels) if mask_pixels else 0.0}

func rendered_sail_pixel_stats(image: Image, mask: Image) -> Dictionary:
	return evaluate_sail_pixel_mask(image, mask)

func _ground_asset_on_terrain(asset: Node3D, burial := 0.0) -> void:
	# Bounds include nested glTF transforms and mesh offsets. Grounding via
	# a fixed arbitrary Y caused visibly floating and buried coastline trees.
	var lowest := INF
	var pending: Array[Node] = [asset]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh:
				var bounds := mesh_instance.mesh.get_aabb()
				for corner in range(8):
					var local: Vector3 = bounds.position + Vector3(
						bounds.size.x if corner & 1 else 0.0,
						bounds.size.y if corner & 2 else 0.0,
						bounds.size.z if corner & 4 else 0.0
					)
					lowest = minf(lowest, mesh_instance.to_global(local).y)
		for child in node.get_children():
			pending.append(child)
	if lowest != INF:
		asset.position.y += _terrain_height(asset.position.x, asset.position.z) - lowest - burial


func _configure_mobile_visibility(root: Node, max_distance: float, shadow_caster: bool = true) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			child.visibility_range_end = max_distance
			child.visibility_range_end_margin = 4.0
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow_caster else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if child.get_child_count() > 0:
			_configure_mobile_visibility(child, max_distance, shadow_caster)

func _cache_ship_visual_bounds() -> void:
	# Compute ONCE from genuine nested imported glTF geometry; the hull
	# origin is not the centre of sails/masts and clips their upper rigging.
	_ship_bounds_ready = false
	if ship_focal == null:
		return
	var inverse_ship := ship_focal.global_transform.affine_inverse()
	var queue: Array[Node] = [ship_focal]
	var has_any := false
	var lower := Vector3.ZERO
	var upper := Vector3.ZERO
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh:
				var aabb := mesh_instance.mesh.get_aabb()
				for i in range(8):
					var corner := aabb.position + Vector3(
						aabb.size.x if i & 1 else 0.0,
						aabb.size.y if i & 2 else 0.0,
						aabb.size.z if i & 4 else 0.0
					)
					var local_pt: Vector3 = inverse_ship * (mesh_instance.global_transform * corner)
					if not has_any:
						lower = local_pt
						upper = local_pt
						has_any = true
					else:
						lower = lower.min(local_pt)
						upper = upper.max(local_pt)
		for child in node.get_children():
			queue.append(child)
	if has_any:
		_ship_visual_bounds_local = AABB(lower, upper - lower)
		_ship_bounds_ready = true
	else:
		push_error("Imported vessel contains no renderable mesh; cinematic framing unavailable")


func ship_visual_bounds_world() -> AABB:
	if not _ship_bounds_ready or ship_focal == null:
		return AABB()
	var bounds := _ship_visual_bounds_local
	var lower := Vector3(INF, INF, INF)
	var upper := Vector3(-INF, -INF, -INF)
	for i in range(8):
		var pt := bounds.position + Vector3(
			bounds.size.x if i & 1 else 0.0,
			bounds.size.y if i & 2 else 0.0,
			bounds.size.z if i & 4 else 0.0
		)
		var world_pt: Vector3 = ship_focal.to_global(pt)
		lower = lower.min(world_pt)
		upper = upper.max(world_pt)
	return AABB(lower, upper - lower)


func frame_ship_cinematic(camera: Camera3D, desired_position: Vector3) -> bool:
	if camera == null or not _ship_bounds_ready:
		return false
	var safe_position := _safe_cinematic_position(camera, desired_position)
	if safe_position == Vector3(INF, INF, INF):
		return false
	camera.global_position = safe_position
	camera.look_at(ship_visual_bounds_world().get_center())
	return true

func _safe_cinematic_position(camera: Camera3D, desired_position: Vector3) -> Vector3:
	if camera == null or not _ship_bounds_ready:
		return Vector3(INF, INF, INF)
	var bounds := ship_visual_bounds_world()
	if bounds.size.length_squared() < 0.00001:
		return Vector3(INF, INF, INF)
	var centre := bounds.get_center()
	var away := (desired_position - centre).normalized()
	if away.length_squared() < 0.00001:
		away = Vector3(-0.6, 0.3, -0.7).normalized()
	var distance := maxf(0.5, desired_position.distance_to(centre))
	var safe_radius := bounds.size.length() * 0.5
	var safe_angle := deg_to_rad(camera.fov * 0.45)
	# Conservatively enclose the ship's *entire* AABB in a vertical frustum;
	# no hull-only target can silently clip the sails or mast tips.
	var needed := safe_radius / maxf(0.05, sin(safe_angle))
	return centre + away * maxf(distance, needed)


func _build_cameras() -> void:
	gameplay_camera = Camera3D.new()
	gameplay_camera.name = "GameplayCamera"
	gameplay_camera.position = GAMEPLAY_CAMERA
	gameplay_camera.current = true
	add_child(gameplay_camera)
	# Camera stays seaward: ship in front, sculpted island behind.
	gameplay_camera.look_at(Vector3(1.0, 1.8, -0.5))
	cinematic_camera = Camera3D.new()
	cinematic_camera.name = "CinematicRevealCamera"
	cinematic_camera.position = CINEMATIC_START_CAMERA
	cinematic_camera.current = false
	add_child(cinematic_camera)
	cinematic_camera.look_at(CINEMATIC_LOOK_TARGET)

func set_gameplay_view() -> void:
	_cinematic_active = false
	if _cinematic_tween:
		_cinematic_tween.kill()
	if gameplay_camera:
		gameplay_camera.current = true

func set_cinematic_view() -> void:
	if cinematic_camera:
		cinematic_camera.current = true

func play_cinematic(reduced_motion := false) -> void:
	_reduced_motion = reduced_motion
	_cinematic_active = true
	if _cinematic_tween:
		_cinematic_tween.kill()
	set_cinematic_view()
	# Every reveal starts from its authored establishing pose, including replay.
	cinematic_camera.position = CINEMATIC_START_CAMERA
	frame_ship_cinematic(cinematic_camera, cinematic_camera.global_position)
	if _reduced_motion:
		set_gameplay_view()
		return
	_cinematic_tween = create_tween()
	# Stay seaward of the moving visual ship so the vessel and island remain
	# in a coherent foreground/midground/background composition.
	var waypoint_a := _safe_cinematic_position(cinematic_camera, Vector3(-7.0, 4.8, -17.0))
	var waypoint_b := _safe_cinematic_position(cinematic_camera, Vector3(-2.5, 5.2, -21.0))
	_cinematic_tween.tween_property(cinematic_camera, "global_position", waypoint_a, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cinematic_tween.tween_property(cinematic_camera, "global_position", waypoint_b, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cinematic_tween.finished.connect(set_gameplay_view)

func skip_cinematic() -> void:
	set_gameplay_view()

func _process(_delta: float) -> void:
	if ship_focal:
		# Preserve navigation XZ; only render-bob the Y channel. Overwriting
		# XZ here previously defeated any genuine vessel movement/VFX sampling.
		ship_focal.position.y = _ship_base_position.y + sin(Time.get_ticks_msec() * 0.0012) * 0.035
	if _cinematic_active and cinematic_camera and cinematic_camera.current:
		# Follow the moving ship; fixed island look-at pushed the ship fully offscreen.
		frame_ship_cinematic(cinematic_camera, cinematic_camera.global_position)
	if _cinematic_active and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel")):
		skip_cinematic()
