extends Node3D
## Reference-driven coastal slice. Geometry is authored once at load; gameplay authority stays server-side.

const ROCK_SCENE := preload("res://assets/external/polyhaven/coast_rocks_05/coast_rocks_05_1k.gltf")
const TREE_SCENE := preload("res://assets/external/polyhaven/tree_small_02/tree_small_02_1k.gltf")
const SHIP_SCENE := preload("res://assets/external/polyhaven/dutch_ship_medium/dutch_ship_medium_1k.gltf")
const COAST_DIFFUSE := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_diff_1k.jpg")
const COAST_NORMAL := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_nor_gl_1k.jpg")
const COAST_ROUGHNESS := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_rough_1k.jpg")
const COAST_AO := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_ao_1k.jpg")
const SHORE_BAKER := preload("res://scripts/coastal_shore_heightfield.gd")
const OCEAN_SHADER := preload("res://shaders/ocean_surface.gdshader")
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
	# Irregular cove waterline and broad uplift, with layered beach, bluff
	# and inland ridges. The same height function grounds decorative meshes.
	var waterline := -7.1 + sin(px * 0.19) * 1.3 + sin(px * 0.53) * 0.6
	waterline += cos(px * 0.095) * 1.2
	var beach := smoothstep(waterline - 2.4, waterline + 3.8, pz)
	var bluff := smoothstep(1.4, 12.5, pz)
	var ridge := sin(px * 0.21 + pz * 0.08) * 1.25
	ridge += cos(px * 0.46 - pz * 0.19) * 0.48
	ridge += sin(px * 0.91 + pz * 0.63) * 0.15
	var side_mask := 1.0 - smoothstep(25.0, 34.0, absf(px))
	var back_mask := 1.0 - smoothstep(19.0, 28.0, pz)
	var island := side_mask * back_mask
	var height := beach * (1.65 + ridge * 0.22)
	height += bluff * (4.2 + ridge * 1.10)
	height += smoothstep(8.0, 18.0, pz) * 1.15
	return WATER_Y - 0.75 + island * (height + 0.75)


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
			indices.append_array([i, i + columns, i + 1, i + 1, i + columns, i + columns + 1])
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
	var material := _terrain_material()
	material.vertex_color_use_as_albedo = true
	terrain.material_override = material
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
	plane.size = Vector2(160.0, 120.0)
	plane.subdivide_width = 160
	plane.subdivide_depth = 120
	water.mesh = plane
	water.position.y = WATER_Y
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = OCEAN_SHADER
	var baked: Dictionary = SHORE_BAKER.bind_to_material(terrain, material, 96, 72)
	if baked.has("error"):
		push_error("Coast heightmap binding failed: " + str(baked["error"]))
		return
	_shore_binding = baked
	water.material_override = material
	add_child(water)
	# Contact foam and depth transitions are now sampled from the ACTUAL
	# indexed coastline mesh. The three old detached white strips are gone.


func _build_premium_landmarks() -> void:
	ship_focal = SHIP_SCENE.instantiate()
	ship_focal.name = "HarbourShipFocalPoint"
	ship_focal.position = Vector3(1.0, -0.05, -5.8)
	ship_focal.rotation_degrees = Vector3(0.0, 18.0, 0.0)
	ship_focal.scale = Vector3.ONE * 0.72
	add_child(ship_focal)
	_ship_base_position = ship_focal.position
	_cache_ship_visual_bounds()
	_configure_mobile_visibility(ship_focal, 42.0)
	# Asset footprints are grounded to terrain rather than assigned arbitrary
	# fixed y-values. Keep the ship/cinematic sightline clear of near foliage.
	for entry in [
		[Vector3(-13.8, 0.0, -0.8), 1.2], [Vector3(-17.5, 0.0, 5.4), 1.8],
		[Vector3(14.2, 0.0, -0.6), 1.5], [Vector3(18.0, 0.0, 8.5), 1.6]
	]:
		var rock := ROCK_SCENE.instantiate()
		rock.position = entry[0]
		rock.scale = Vector3.ONE * entry[1]
		add_child(rock)
		_ground_asset_on_terrain(rock, 0.3)
		_configure_mobile_visibility(rock, 30.0)
	for entry in [
		[Vector3(-16.0, 0.0, 4.0), 1.1], [Vector3(-20.5, 0.0, 13.0), 1.15],
		[Vector3(15.2, 0.0, 6.5), 1.05], [Vector3(20.0, 0.0, 13.0), 0.9]
	]:
		var tree := TREE_SCENE.instantiate()
		tree.position = entry[0]
		tree.scale = Vector3.ONE * entry[1]
		add_child(tree)
		_ground_asset_on_terrain(tree)
		_configure_mobile_visibility(tree, 26.0)
	player_marker = Node3D.new()
	player_marker.name = "PlayerSpawnMarker"
	player_marker.position = Vector3(0.0, _terrain_height(0.0, 5.5) + 0.75, 5.5)
	add_child(player_marker)

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
					var local := bounds.position + Vector3(
						bounds.size.x if corner & 1 else 0.0,
						bounds.size.y if corner & 2 else 0.0,
						bounds.size.z if corner & 4 else 0.0
					)
					lowest = minf(lowest, mesh_instance.to_global(local).y)
		for child in node.get_children():
			pending.append(child)
	if lowest != INF:
		asset.position.y += _terrain_height(asset.position.x, asset.position.z) - lowest - burial


func _configure_mobile_visibility(root: Node, max_distance: float) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			child.visibility_range_end = max_distance
			child.visibility_range_end_margin = 4.0
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if child.get_child_count() > 0:
			_configure_mobile_visibility(child, max_distance)

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
	var bounds := ship_visual_bounds_world()
	if bounds.size.length_squared() < 0.00001:
		return false
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
	camera.global_position = centre + away * maxf(distance, needed)
	camera.look_at(centre)
	return true


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
	_cinematic_tween.tween_property(cinematic_camera, "position", Vector3(-7.0, 4.8, -17.0), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cinematic_tween.tween_property(cinematic_camera, "position", Vector3(-2.5, 5.2, -21.0), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
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
