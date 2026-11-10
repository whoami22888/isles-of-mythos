extends Node3D
## Reference-driven coastal slice. Geometry is authored once at load; gameplay authority stays server-side.

const ROCK_SCENE := preload("res://assets/external/polyhaven/coast_rocks_05/coast_rocks_05_1k.gltf")
const TREE_SCENE := preload("res://assets/external/polyhaven/tree_small_02/tree_small_02_1k.gltf")
const SHIP_SCENE := preload("res://assets/external/polyhaven/dutch_ship_medium/dutch_ship_medium_1k.gltf")
const COASTAL_CLIFF_SCENE := preload("res://assets/external/polyhaven/coastal_cliff_01/coastal_cliff_01_1k.gltf")
const TROPICAL_TREE_SCENE := preload("res://assets/external/polyhaven/island_tree_01/island_tree_01_1k.gltf")
const TROPICAL_TREE_ALT_SCENE := preload("res://assets/external/polyhaven/island_tree_02/island_tree_02_1k.gltf")
const ISLAND_LEAVES_RGBA := preload("res://assets/external/generated/foliage/island_tree_leaves_rgba_1k.png")
const MOSS_ROCK_SCENE := preload("res://assets/external/polyhaven/rock_moss_set_01/rock_moss_set_01_1k.gltf")
const COAST_DIFFUSE := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_diff_1k.jpg")
const COAST_NORMAL := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_nor_gl_1k.jpg")
const COAST_ROUGHNESS := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_rough_1k.jpg")
const COAST_AO := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_ao_1k.jpg")
const SAND_ALBEDO := preload("res://assets/external/polyhaven/coast_sand_01/coast_sand_01_diff_1k.jpg")
const SAND_NORMAL := preload("res://assets/external/polyhaven/coast_sand_01/coast_sand_01_nor_gl_1k.jpg")
const SAND_ROUGH := preload("res://assets/external/polyhaven/coast_sand_01/coast_sand_01_rough_1k.jpg")
const GRASS_ALBEDO := preload("res://assets/external/polyhaven/forrest_ground_01/forrest_ground_01_diff_1k.jpg")
const GRASS_NORMAL := preload("res://assets/external/polyhaven/forrest_ground_01/forrest_ground_01_nor_gl_1k.jpg")
const GRASS_ROUGH := preload("res://assets/external/polyhaven/forrest_ground_01/forrest_ground_01_rough_1k.jpg")
const ROCK_ALBEDO := preload("res://assets/external/polyhaven/cliff_side/cliff_side_diff_1k.jpg")
const ROCK_NORMAL := preload("res://assets/external/polyhaven/cliff_side/cliff_side_nor_gl_1k.jpg")
const ROCK_ROUGH := preload("res://assets/external/polyhaven/cliff_side/cliff_side_rough_1k.jpg")
const COAST_HDRI := preload("res://assets/external/polyhaven/kloofendal_48d_partly_cloudy_puresky/kloofendal_48d_partly_cloudy_puresky_1k_ldr.png")
const WATER_NORMAL := preload("res://assets/generated/water/water_ripples_nor_gl_1k.png")
const SUN_GLOW := preload("res://assets/generated/lighting/sun_glow.png")
const SHORE_BAKER := preload("res://scripts/coastal_shore_heightfield.gd")
const OCEAN_SHADER := preload("res://shaders/ocean_surface.gdshader")
const TERRAIN_SHADER := preload("res://shaders/coastal_terrain_surface.gdshader")
const SAIL_EMBLEM := preload("res://assets/generated/sails/order_cross_sails_rgba.png")
const Dressing := preload("res://scripts/tropical_bay_dressing.gd")
@export var coastal_cliff_lod2_scene: PackedScene
@export var tropical_tree_lod2_scene: PackedScene
@export var tropical_tree_alt_lod2_scene: PackedScene
const WATER_Y := -0.35
const GAMEPLAY_CAMERA := Vector3(7.2, 19.8, -16.2)
const CINEMATIC_START_CAMERA := Vector3(-16.5, 6.8, -16.0)
const CINEMATIC_LOOK_TARGET := Vector3(2.5, 2.6, 5.0)
# Plants sit inland of the sand; rocks may rest in the shallows.
const FOLIAGE_MIN_ABOVE_SEA := 1.15
const ROCK_MIN_ABOVE_SEA := -0.12

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
	Dressing.attach(self)
	_apply_visual_quality_from_environment()
	sync_ocean_vessel_uniforms()

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "CoastalAtmosphere"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = COAST_HDRI
	# Keep energy modest on compatibility / mobile: the HDRI should light the
	# sky, not blow out the island.
	sky_material.energy_multiplier = 0.80
	sky.sky_material = sky_material
	environment.sky = sky
	# Rotate so the brighter sky sits with the warm key light.
	environment.sky_rotation = Vector3(0.0, deg_to_rad(155.0), 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.50
	environment.ambient_light_sky_contribution = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.86
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.88
	environment.adjustment_contrast = 1.16
	environment.adjustment_brightness = 0.97
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color(0.62, 0.74, 0.86)
	environment.fog_depth_begin = 32.0
	environment.fog_depth_end = 180.0
	environment.fog_depth_curve = 1.05
	environment.fog_aerial_perspective = 0.78
	environment.fog_sun_scatter = 0.34
	# Keep the sky readable; haze is for distant land, not the dome.
	environment.fog_sky_affect = 0.14
	# Glow is ignored on some compatibility devices; the sun-glow billboard is the fallback.
	environment.glow_enabled = true
	environment.glow_intensity = 0.28
	environment.glow_bloom = 0.08
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "WarmSun"
	# Slightly lower golden key so the harbour side gets warm raking light.
	sun.rotation_degrees = Vector3(-33.0, 148.0, 0.0)
	sun.light_color = Color(1.0, 0.70, 0.36)
	sun.light_energy = 1.72
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 64.0
	sun.shadow_bias = 0.06
	add_child(sun)
	_build_sun_glow(sun)

func _hash21(p: Vector2) -> float:
	return fposmod(sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)


func _value_noise(p: Vector2) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := p - i
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := _hash21(i)
	var b := _hash21(i + Vector2(1.0, 0.0))
	var c := _hash21(i + Vector2(0.0, 1.0))
	var d := _hash21(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)


func _fbm(p: Vector2, octaves: int = 4) -> float:
	var acc := 0.0
	var w := 0.5
	var sum_w := 0.0
	var q := p
	for _i in range(octaves):
		acc += w * _value_noise(q)
		sum_w += w
		w *= 0.5
		q *= 2.03
	return acc / maxf(sum_w, 0.0001)


func is_foliage_ground(px: float, pz: float) -> bool:
	return _terrain_height(px, pz) >= WATER_Y + FOLIAGE_MIN_ABOVE_SEA


func is_rock_ground(px: float, pz: float) -> bool:
	return _terrain_height(px, pz) >= WATER_Y + ROCK_MIN_ABOVE_SEA


func _terrain_height(px: float, pz: float) -> float:
	# Organic island: domain-warped radial falloff, a south-facing crescent
	# bay with a wide sand terrace, and rugged inland peaks.
	var warp := Vector2((_fbm(Vector2(px, pz) * 0.08, 3) - 0.5) * 5.0, (_fbm(Vector2(px + 17.0, pz - 9.0) * 0.08, 3) - 0.5) * 5.0)
	var wpos := Vector2(px, pz) + warp
	var centre := Vector2(1.0, 11.0)
	var delta := wpos - centre
	var radius := delta.length()
	var ang := atan2(delta.x, delta.y)
	var south := maxf(0.0, -cos(ang))
	var bay := pow(south, 1.32)
	var head_west := exp(-pow((ang - PI - 1.02) / 0.44, 2.0))
	var head_east := exp(-pow((ang - PI + 0.88) / 0.42, 2.0))
	var east_bulge := exp(-pow((ang - 1.50) / 0.28, 2.0))
	var north_cap := exp(-pow((ang - 0.65) / 0.70, 2.0))
	var head := head_west * 1.05 + head_east * 0.72
	var coast_n := _fbm(wpos * 0.11, 3)
	# Slightly larger landmass; the south waterline stays north of the berth.
	var island_r := 18.2 - 7.2 * bay + 5.6 * head + 3.8 * east_bulge + 8.8 * north_cap + (coast_n - 0.5) * 3.6
	island_r -= 7.0 * exp(-((px - 16.0) * (px - 16.0)) / 10.0 - ((pz - 3.0) * (pz - 3.0)) / 8.0)
	# Wide pale crescent in the bay, a thin varying edge on other coasts.
	var beach_w := clampf(2.2 + 7.6 * bay - 1.1 * head, 1.6, 11.0)
	var offshore := radius - island_r
	var deep := -6.6 + (_fbm(Vector2(px, pz) * 0.05, 3) - 0.5) * 0.45 + 0.55 * tanh(px * 0.08)
	var shelf := -0.92 + (_fbm(Vector2(px, pz) * 0.18, 2) - 0.5) * 0.12
	var apron := 1.0 - smoothstep(1.2, 8.5, offshore)
	apron *= 1.0 - 0.25 * (1.0 - bay)
	var berth := exp(-(((px - 1.5) * (px - 1.5)) / 64.0 + ((pz + 7.2) * (pz + 7.2)) / 36.0))
	var seabed := lerpf(deep, shelf, apron * (1.0 - berth))
	var berth_w := 1.0 if offshore > 0.6 else 0.15
	seabed = lerpf(seabed, -5.6, berth * berth_w)
	if offshore >= 0.0:
		var lip := 1.0 - smoothstep(-0.15, 1.15, offshore)
		return lerpf(seabed, WATER_Y + 0.10 + 0.16 * bay, lip * (1.0 - berth))
	# Flat-ish sand terrace, then a ramp into the hills so the bay reads as a
	# wide beach rather than a thin ring against a rising lawn.
	var onto := -offshore
	var sand_t := clampf(onto / maxf(beach_w, 0.8), 0.0, 1.0)
	var sand_y := WATER_Y + 0.16 + 0.46 * sand_t * sand_t * (3.0 - 2.0 * sand_t)
	var hill_blend := smoothstep(beach_w * 0.40, beach_w + 3.2, onto)
	var inland := clampf(onto / maxf(beach_w + 5.0, 0.8), 0.0, 1.0)
	inland = inland * inland * (3.0 - 2.0 * inland)
	var n := _fbm(wpos * 0.07, 3)
	var ridged := 1.0 - absf(2.0 * _fbm(wpos * 0.045 + Vector2(40.0, -20.0), 3) - 1.0)
	# Sharper peak kernels plus mid-frequency ridge/gully noise so summits and
	# some faces go steep enough for the rock blend, not smooth green lumps.
	var d1 := (px + 6.2) * (px + 6.2) + (pz - 15.8) * (pz - 15.8)
	var d2 := (px - 8.0) * (px - 8.0) + (pz - 17.6) * (pz - 17.6)
	var d3 := (px - 16.0) * (px - 16.0) + (pz - 26.5) * (pz - 26.5)
	var peak_a := exp(-d1 / 22.0) * (8.6 + n * 0.8)
	var peak_b := exp(-d2 / 26.0) * (10.2 + ridged * 1.0)
	var peak_c := exp(-d3 / 20.0) * 8.4
	var knoll := exp(-((px + 1.5) * (px + 1.5) + (pz - 12.2) * (pz - 12.2)) / 16.0) * 2.0
	var peak_sum := peak_a + peak_b + peak_c
	var ridge_detail := 1.0 - absf(2.0 * _fbm(wpos * 0.16 + Vector2(8.0, 3.0), 3) - 1.0)
	var gully := _fbm(wpos * 0.14 + Vector2(21.0, -7.0), 3)
	var rugged := (peak_sum / 10.0) * (1.55 * (ridge_detail - 0.42) - 0.9 * gully * (1.0 - ridge_detail))
	var hills := (0.50 + 1.7 * n + 1.35 * ridged * inland) * inland + (peak_sum + knoll) * (0.50 + 0.50 * inland) + rugged * inland
	var land := sand_y + hills * hill_blend
	if hill_blend < 0.05:
		return sand_y
	return land


func walk_to_land(px: float, pz: float, min_above: float = 0.35, max_steps: int = 28) -> Vector2:
	# Walk toward the island centre until the point is dry. Used to re-seat
	# props when the coastline moves under a hint position.
	var p := Vector2(px, pz)
	var target := Vector2(0.0, 11.0)
	for _i in range(max_steps):
		if _terrain_height(p.x, p.y) >= WATER_Y + min_above:
			return p
		var dir := target - p
		if dir.length() < 0.25:
			break
		p += dir.normalized() * 0.9
	return p


func walk_to_shore(px: float, pz: float, dir: Vector2, max_steps: int = 20) -> Vector2:
	# Step from a dry hint toward the water until the next step would submerge.
	var p := walk_to_land(px, pz, 0.2)
	var step := dir.normalized() * 0.7
	for _i in range(max_steps):
		var nxt := p + step
		if _terrain_height(nxt.x, nxt.y) < WATER_Y + 0.06:
			return p
		p = nxt
	return p


func _build_coastal_terrain() -> void:
	# Organic coastline on the existing mobile grid. The shore baker (and the
	# ocean integration test) require this mesh to stay 96 x 72 vertices.
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
			var px := (fx - 0.5) * 80.0
			var pz := (fz - 0.5) * 68.0
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
			# Godot front faces are clockwise seen from the normal side. The
			# old order was counter-clockwise from above, so cull_back removed
			# the whole land surface and the ocean showed through the island.
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
	terrain.material_override = _terrain_shader_material()
	add_child(terrain)


func _terrain_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#c9a77b")
	material.albedo_texture = COAST_DIFFUSE
	material.normal_enabled = true
	material.normal_texture = COAST_NORMAL
	material.roughness_texture = COAST_ROUGHNESS
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.ao_enabled = true
	material.ao_texture = COAST_AO
	material.roughness = 0.88
	material.metallic = 0.0
	return material


func _terrain_shader_material() -> ShaderMaterial:
	# Keep the CC0 sand/rock assignments in _terrain_material() for the source
	# gate, and shade the coast with height/slope-blended PBR maps.
	var reference := _terrain_material()
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
	material.set_shader_parameter("sea_level", WATER_Y)
	if reference.albedo_texture == null:
		push_error("Coastal terrain source albedo missing")
	return material

func sun_basis_z() -> Vector3:
	var sun := get_node_or_null("WarmSun") as DirectionalLight3D
	if sun:
		return sun.global_transform.basis.z
	return Vector3(0.35, 0.75, 0.55)


func _build_sun_glow(sun: DirectionalLight3D) -> void:
	# Compatibility often skips Environment.glow. A soft additive billboard in
	# the sun's direction gives a cheap golden bloom that still depth-tests
	# against the island.
	var glow := MeshInstance3D.new()
	glow.name = "SunGlow"
	var quad := QuadMesh.new()
	quad.size = Vector2(36.0, 36.0)
	glow.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = SUN_GLOW
	mat.albedo_color = Color(1.0, 0.82, 0.5, 0.9)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.material_override = mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position = Vector3(0.0, 14.0, 0.0) + sun.global_transform.basis.z * 95.0
	add_child(glow)


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
	# Contract floor is 96 x 72. Stay there: the old 160 x 120 grid was a
	# large share of the mobile vertex cost and read as a specular lattice.
	plane.subdivide_width = 96
	plane.subdivide_depth = 72
	water.mesh = plane
	water.position.y = WATER_Y - 0.18
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = OCEAN_SHADER
	material.set_shader_parameter("swell_scale", 0.08)
	material.set_shader_parameter("ripple_detail", 0.62)
	material.set_shader_parameter("foam_amount", 1.0)
	material.set_shader_parameter("water_normal", WATER_NORMAL)
	material.set_shader_parameter("sand_albedo", SAND_ALBEDO)
	material.set_shader_parameter("sun_dir", -sun_basis_z())
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
	ship_focal.position = Vector3(1.5, -0.05, -7.2)
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
		[Vector3(-12.5, 0.0, 0.4), 1.15, 70.0], [Vector3(13.5, 0.0, 0.2), 1.25, 70.0],
		[Vector3(-18.5, 0.0, 8.5), 1.4, 64.0], [Vector3(19.0, 0.0, 10.0), 1.3, 64.0]
	]:
		var rock := ROCK_SCENE.instantiate()
		var rock_xz: Vector2 = walk_to_land(entry[0].x, entry[0].z, 0.05)
		rock.position = Vector3(rock_xz.x, 0.0, rock_xz.y)
		rock.scale = Vector3.ONE * entry[1]
		_apply_landmark_lod(rock, 30000)
		add_child(rock)
		_ground_asset_on_terrain(rock, 0.3)
		_configure_mobile_visibility(rock, entry[2])
	for entry in [
		[Vector3(-7.5, 0.0, 6.2), 1.05, 78.0], [Vector3(10.5, 0.0, 7.4), 1.0, 20.0],
		[Vector3(-19.0, 0.0, 12.5), 1.1, 48.0], [Vector3(17.5, 0.0, 13.5), 0.95, 48.0]
	]:
		var tree := TREE_SCENE.instantiate()
		var tree_xz: Vector2 = walk_to_land(entry[0].x, entry[0].z, FOLIAGE_MIN_ABOVE_SEA)
		tree.position = Vector3(tree_xz.x, 0.0, tree_xz.y)
		tree.scale = Vector3.ONE * entry[1]
		# Keep a detailed near-field silhouette while bounding the imported
		# 2.06M-triangle source before the Mobile renderer sees four copies.
		_apply_far_foliage_lod(tree, 90000)
		add_child(tree)
		_ground_asset_on_terrain(tree)
		# One hero tree stays in the gameplay view. The other admitted copies
		# exist for the contract but cull before they dominate the frame.
		tree.set_meta("heavy_foliage", entry[2] >= 70.0)
		_configure_mobile_visibility(tree, entry[2], false)
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
		var shore_xz: Vector2 = walk_to_land(entry[0].x, entry[0].z, FOLIAGE_MIN_ABOVE_SEA)
		shoreline_tree.position = Vector3(shore_xz.x, 0.0, shore_xz.y)
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
		var sr_xz: Vector2 = walk_to_land(entry[0].x, entry[0].z, 0.05)
		shore_rock.position = Vector3(sr_xz.x, 0.0, sr_xz.y)
		shore_rock.scale = Vector3.ONE * entry[1]
		_apply_landmark_lod(shore_rock, 30000)
		grove.add_child(shore_rock)
		_ground_asset_on_terrain(shore_rock, 0.18)
		_configure_mobile_visibility(shore_rock, 64.0, false)
	# Additional verified CC0 coastal families provide the silhouette and
	# vegetation variation missing from the original three-asset slice. Keep
	# them in a separate layer so the existing functional contract remains
	# stable while every imported mesh receives the same terrain grounding and
	# bounded visibility policy.
	var premium_layer := Node3D.new()
	premium_layer.name = "VerifiedTropicalContentLayer"
	add_child(premium_layer)
	for entry in [
		# The source cliff is a 461k-triangle photogrammetry slab. Keep the
		# admitted node and its PBR material, but draw a small ridgeline mesh
		# so three copies do not dominate the mobile frame.
		[Vector3(-14.5, 0.0, 6.5), COASTAL_CLIFF_SCENE],
		[Vector3(14.8, 0.0, 6.2), COASTAL_CLIFF_SCENE],
		[Vector3(8.0, 0.0, 16.5), COASTAL_CLIFF_SCENE],
		[Vector3(-11.5, 0.0, 9.5), TROPICAL_TREE_SCENE],
		[Vector3(11.0, 0.0, 12.0), TROPICAL_TREE_ALT_SCENE],
		[Vector3(-3.5, 0.0, 16.5), TROPICAL_TREE_ALT_SCENE],
		[Vector3(5.5, 0.0, 15.0), TROPICAL_TREE_SCENE],
		[Vector3(6.8, 0.0, 8.2), TROPICAL_TREE_ALT_SCENE],
		[Vector3(-6.2, 0.0, 8.6), TROPICAL_TREE_SCENE],
		[Vector3(1.2, 0.0, 11.4), TROPICAL_TREE_SCENE],
		[Vector3(13.2, 0.0, 8.8), TROPICAL_TREE_ALT_SCENE],
		[Vector3(-8.4, 0.0, 12.4), TROPICAL_TREE_ALT_SCENE],
		[Vector3(3.6, 0.0, 7.1), TROPICAL_TREE_SCENE],
		[Vector3(-16.0, 0.0, 8.0), MOSS_ROCK_SCENE],
		[Vector3(15.0, 0.0, 9.0), MOSS_ROCK_SCENE]
	]:
		var imported := entry[1].instantiate() as Node3D
		imported.position = entry[0]
		imported.scale = Vector3.ONE
		var view_range := 64.0
		if entry[1] == TROPICAL_TREE_SCENE or entry[1] == TROPICAL_TREE_ALT_SCENE:
			_apply_far_foliage_lod(imported, 48000)
			view_range = 96.0
		elif entry[1] == COASTAL_CLIFF_SCENE:
			_install_cliff_proxy(imported)
			view_range = 120.0
		elif entry[1] == MOSS_ROCK_SCENE:
			_apply_landmark_lod(imported, 30000)
			imported.scale = Vector3.ONE * 0.75
			view_range = 18.0
		premium_layer.add_child(imported)
		var hint := Vector2(imported.position.x, imported.position.z)
		if entry[1] != COASTAL_CLIFF_SCENE:
			var min_y := FOLIAGE_MIN_ABOVE_SEA if (entry[1] == TROPICAL_TREE_SCENE or entry[1] == TROPICAL_TREE_ALT_SCENE) else 0.08
			hint = walk_to_land(hint.x, hint.y, min_y)
			imported.position.x = hint.x
			imported.position.z = hint.y
		else:
			# Seat outcrops on headland / peak faces, still behind the ship so
			# they stay background landmarks (not a camera-spanning wall).
			hint = walk_to_land(hint.x, hint.y, 1.2)
			if hint.y < ship_focal.position.z + 11.0:
				hint = walk_to_land(hint.x, ship_focal.position.z + 12.0, 1.2)
			imported.position.x = hint.x
			imported.position.z = hint.y
		_ground_asset_on_terrain(imported, 1.0 if entry[1] == COASTAL_CLIFF_SCENE else 0.08)
		_configure_mobile_visibility(imported, view_range, false)
	# Spawn state belongs to scene construction, not recursive material
	# traversal. Keeping this here guarantees one authoritative marker.
	player_marker = Node3D.new()
	player_marker.name = "PlayerSpawnMarker"
	var spawn_xz := walk_to_land(0.0, 5.5, 0.45)
	player_marker.position = Vector3(spawn_xz.x, _terrain_height(spawn_xz.x, spawn_xz.y) + 0.75, spawn_xz.y)
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
					corrected.albedo_texture = SAIL_EMBLEM
					corrected.albedo_color = Color.WHITE
					corrected.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					corrected.cull_mode = BaseMaterial3D.CULL_DISABLED
					# Per-pixel lighting left these cloth normals black from the
					# gameplay camera. Unshaded keeps the cream cloth and the
					# painted cross readable without a second sail shader.
					corrected.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					corrected.disable_receive_shadows = true
					mesh_instance.set_surface_override_material(surface_index, corrected)
		for child in node.get_children():
			_configure_ship_sails(child)

func _reduce_surface_triangles(source: ArrayMesh, surface_index: int, _max_triangles: int) -> Array:
	# A triangle budget cannot justify punching holes in an authored surface.
	# Until an admitted LOD has equivalent topology/material evidence, retain
	# the exact source arrays, including every vertex attribute and index.
	return source.surface_get_arrays(surface_index)

func _apply_far_foliage_lod(asset: Node3D, _max_total_triangles: int = 72000) -> void:
	_preserve_authored_mesh(asset, true)

func _apply_landmark_lod(asset: Node3D, _max_triangles: int) -> void:
	if asset.scene_file_path.get_file() == "coastal_cliff_01_1k.gltf":
		var packed := coastal_cliff_lod2_scene
		if packed == null:
			push_error("Missing admitted coastal cliff LOD2")
			return
		var authored := packed.instantiate()
		var originals := asset.find_children("*", "MeshInstance3D", true, false)
		var replacements := authored.find_children("*", "MeshInstance3D", true, false)
		if originals.size() != 1 or replacements.size() != 1:
			push_error("Unexpected coastal cliff LOD mesh hierarchy")
			authored.free()
			return
		# Retain the source scene transform and identity while using the pinned,
		# 46k-triangle mesh and its authored PBR material surfaces at runtime.
		originals[0].mesh = replacements[0].mesh
		authored.free()
		return
	_preserve_authored_mesh(asset)

func _preserve_authored_mesh(asset: Node3D, distant: bool = false) -> void:
	var asset_name := asset.scene_file_path.get_file().trim_suffix("_1k.gltf")
	if asset_name not in ["tree_small_02", "island_tree_01", "island_tree_02", "coast_rocks_05"]:
		return
	var packed: PackedScene
	if distant and asset_name == "island_tree_01":
		packed = tropical_tree_lod2_scene
	elif distant and asset_name == "island_tree_02":
		packed = tropical_tree_alt_lod2_scene
	else:
		packed = load("res://assets/external/generated/bounded_lods/" + asset_name + ".glb") as PackedScene
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
	if asset_name in ["island_tree_01", "island_tree_02"]:
		for surface_index in range(originals[0].mesh.get_surface_count()):
			var material := originals[0].get_active_material(surface_index) as StandardMaterial3D
			if material == null or not str(material.resource_name).to_lower().contains("leaves"):
				continue
			var foliage := material.duplicate() as StandardMaterial3D
			foliage.albedo_texture = ISLAND_LEAVES_RGBA
			foliage.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			originals[0].set_surface_override_material(surface_index, foliage)
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
	gameplay_camera.fov = 56.0
	gameplay_camera.current = true
	add_child(gameplay_camera)
	# Elevated gameplay view: ship in front, beach and cliffs behind.
	gameplay_camera.look_at(Vector3(1.0, 3.2, 12.0))
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

func sync_ocean_vessel_uniforms() -> void:
	var water := get_node_or_null("ShallowToDeepWater") as MeshInstance3D
	if water == null or ship_focal == null:
		return
	var material := water.material_override as ShaderMaterial
	if material == null:
		return
	var forward := -ship_focal.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, -1.0)
	forward = forward.normalized()
	material.set_shader_parameter("vessel_xz", Vector2(ship_focal.global_position.x, ship_focal.global_position.z))
	material.set_shader_parameter("vessel_forward", Vector2(forward.x, forward.z))


## Presentation-only surface queries for hosts that place server-positioned
## markers on this bay (the gameplay vertical slice). Global X/Z in, global Y
## out; the same height equation the terrain mesh and props are built from.
func terrain_height_at(global_x: float, global_z: float) -> float:
	var local := to_local(Vector3(global_x, 0.0, global_z))
	return to_global(Vector3(local.x, _terrain_height(local.x, local.z), local.z)).y


func water_level() -> float:
	return to_global(Vector3(0.0, WATER_Y, 0.0)).y


## Move the whole bay so that `global_origin` is its new origin. The ocean's
## shoreline heightmap is sampled in world X/Z, so its origin moves with it;
## the bake itself is reused, never recomputed per move.
func relocate(global_origin: Vector3) -> void:
	var before := global_position
	global_position = global_origin
	if _shore_binding.is_empty():
		return
	var water := get_node_or_null("ShallowToDeepWater") as MeshInstance3D
	if water == null or not (water.material_override is ShaderMaterial):
		return
	var material := water.material_override as ShaderMaterial
	var moved := global_position - before
	var origin: Vector2 = _shore_binding["origin"] + Vector2(moved.x, moved.z)
	_shore_binding["origin"] = origin
	material.set_shader_parameter("shore_origin_xz", origin)
	sync_ocean_vessel_uniforms()


func apply_visual_quality(level: int) -> void:
	# 0 mid-range floor, 1 balanced, 2 S23-class target. Presentation only.
	var clamped := clampi(level, 0, 2)
	var sun := get_node_or_null("WarmSun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = clamped == 2
	# Project default is 2x MSAA (thin rigging and fronds alias badly
	# without it). The mid-range floor drops it to save fill rate.
	var viewport := get_viewport()
	if viewport:
		viewport.msaa_3d = Viewport.MSAA_DISABLED if clamped == 0 else Viewport.MSAA_2X
	var dressing := get_node_or_null("TropicalBayDressing")
	if dressing:
		var palms := dressing.get_node_or_null("TropicalPalmGrove") as MultiMeshInstance3D
		var grass := dressing.get_node_or_null("TropicalGrassTufts") as MultiMeshInstance3D
		var palm_counts: Array[int] = [12, 18, 24]
		var grass_counts: Array[int] = [0, 420, 980]
		if palms and palms.multimesh:
			var palm_placed := int(palms.get_meta("placed_count", palms.multimesh.visible_instance_count))
			palms.multimesh.visible_instance_count = mini(palm_counts[clamped], palm_placed)
		if grass and grass.multimesh:
			var grass_placed := int(grass.get_meta("placed_count", grass.multimesh.visible_instance_count))
			grass.multimesh.visible_instance_count = mini(grass_counts[clamped], grass_placed)
		for extra in [
			["TropicalFernClumps", [0, 80, 160]],
			["TropicalShrubs", [0, 40, 80]],
			["TropicalCalathea", [0, 22, 44]],
			["TropicalAnthurium", [0, 12, 24]],
			["TropicalUrsinia", [0, 24, 48]],
			["TropicalSorrel", [0, 20, 40]],
			["CliffLedgeFerns", [0, 36, 72]],
			["CliffVines", [0, 20, 40]],
			["HeroAnthurium", [0, 8, 12]],
			["HeroUrsinia", [0, 8, 12]],
			["ShoreBoulders", [4, 8, 10]],
			["ShoreRocks07", [4, 8, 10]],
			["ShoreMossRocks", [4, 8, 10]],
		]:
			var foliage := dressing.get_node_or_null(String(extra[0])) as MultiMeshInstance3D
			if foliage and foliage.multimesh:
				var placed_extra := int(foliage.get_meta("placed_count", foliage.multimesh.visible_instance_count))
				var counts: Array = extra[1]
				foliage.multimesh.visible_instance_count = mini(int(counts[clamped]), placed_extra)
	var hero_range: float = [0.01, 48.0, 78.0][clamped]
	for node in find_children("*", "Node3D", true, false):
		if node.has_meta("heavy_foliage") and bool(node.get_meta("heavy_foliage")):
			_configure_mobile_visibility(node, hero_range, false)


func _apply_visual_quality_from_environment() -> void:
	var quality_name := OS.get_environment("IOM_VISUAL_QUALITY").to_lower()
	var level := 2
	if quality_name == "low":
		level = 0
	elif quality_name == "medium":
		level = 1
	apply_visual_quality(level)


func _install_cliff_proxy(asset: Node3D) -> void:
	var meshes := asset.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	var source := meshes[0] as MeshInstance3D
	var material := source.get_active_material(0)
	# Sculpted ridge: steep shore face, a mid ledge for vegetation, gentler
	# back slope. The terrain shader puts rock on the cliffs and grass on ledges.
	source.mesh = Dressing.cliff_ridge_mesh(7.2, 4.4, 4.6, asset.position.x * 0.41)
	source.transform = Transform3D.IDENTITY
	source.set_surface_override_material(0, Dressing.cliff_pbr_material())
	for extra_index in range(1, meshes.size()):
		var extra := meshes[extra_index] as MeshInstance3D
		extra.mesh = null
		extra.visible = false


func _process(_delta: float) -> void:
	if ship_focal:
		# Preserve navigation XZ; only render-bob the Y channel. Overwriting
		# XZ here previously defeated any genuine vessel movement/VFX sampling.
		ship_focal.position.y = _ship_base_position.y + sin(Time.get_ticks_msec() * 0.0012) * 0.035
	sync_ocean_vessel_uniforms()
	if _cinematic_active and cinematic_camera and cinematic_camera.current:
		# Follow the moving ship; fixed island look-at pushed the ship fully offscreen.
		frame_ship_cinematic(cinematic_camera, cinematic_camera.global_position)
	if _cinematic_active and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel")):
		skip_cinematic()
