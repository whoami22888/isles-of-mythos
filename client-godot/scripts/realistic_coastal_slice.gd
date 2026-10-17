extends Node3D
## Reference-driven coastal slice. Geometry is authored once at load; gameplay authority stays server-side.

const ROCK_SCENE := preload("res://assets/external/polyhaven/coast_rocks_05/coast_rocks_05_1k.gltf")
const TREE_SCENE := preload("res://assets/external/polyhaven/tree_small_02/tree_small_02_1k.gltf")
const SHIP_SCENE := preload("res://assets/external/polyhaven/dutch_ship_medium/dutch_ship_medium_1k.gltf")
const COAST_DIFFUSE := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_diff_1k.jpg")
const COAST_NORMAL := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_nor_gl_1k.jpg")
const COAST_ROUGHNESS := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_rough_1k.jpg")
const COAST_AO := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_ao_1k.jpg")
const OCEAN_SHADER := preload("res://shaders/ocean_surface.gdshader")
const WATER_Y := -0.35
const GAMEPLAY_CAMERA := Vector3(10.5, 6.0, 10.0)
const CINEMATIC_START_CAMERA := Vector3(-8.0, 4.5, 9.0)

var gameplay_camera: Camera3D
var cinematic_camera: Camera3D
var player_marker: Node3D
var ship_focal: Node3D
var _ship_base_position := Vector3.ZERO
var _cinematic_tween: Tween
var _cinematic_active := false
var _reduced_motion := false

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

func _build_coastal_terrain() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const columns := 24
	const rows := 18
	for z in range(rows):
		for x in range(columns):
			var fx := float(x) / float(columns - 1)
			var fz := float(z) / float(rows - 1)
			var px := (fx - 0.5) * 34.0
			var pz := (fz - 0.5) * 26.0
			var shore := smoothstep(-10.0, -2.0, pz)
			var ridge := sin(px * 0.37) * 0.8 + cos(pz * 0.31) * 0.55
			var cliff := maxf(0.0, (pz + 1.0) * 0.16) * shore
			var py := WATER_Y + shore * (1.25 + cliff) + ridge * 0.12
			vertices.append(Vector3(px, py, pz))
			uvs.append(Vector2(fx * 3.0, fz * 3.0))
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
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var terrain := MeshInstance3D.new()
	terrain.name = "IrregularCoastalTerrain"
	terrain.mesh = mesh
	terrain.material_override = _terrain_material()
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
	var water := MeshInstance3D.new()
	water.name = "ShallowToDeepWater"
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 120.0)
	# Only the long swells need vertex geometry. Fine ripples run in the
	# fragment shader; avoid tessellating every tiny normal detail on Android.
	plane.subdivide_width = 160
	plane.subdivide_depth = 120
	water.mesh = plane
	water.position.y = WATER_Y
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = OCEAN_SHADER
	water.material_override = material
	add_child(water)
	# Contact foam is now evaluated against the actual terrain-height equation
	# inside the ocean shader, rather than being three disconnected quad strips.


func _build_premium_landmarks() -> void:
	ship_focal = SHIP_SCENE.instantiate()
	ship_focal.name = "HarbourShipFocalPoint"
	ship_focal.position = Vector3(1.0, -0.05, -5.8)
	ship_focal.rotation_degrees = Vector3(0.0, 18.0, 0.0)
	ship_focal.scale = Vector3.ONE * 0.72
	add_child(ship_focal)
	_ship_base_position = ship_focal.position
	_configure_mobile_visibility(ship_focal, 42.0)
	for entry in [
		[Vector3(-8.0, 0.35, -2.1), 1.45], [Vector3(-2.0, 0.25, -1.4), 1.1],
		[Vector3(6.8, 0.48, -2.7), 1.25], [Vector3(11.0, 0.65, 3.5), 1.55]
	]:
		var rock := ROCK_SCENE.instantiate()
		rock.position = entry[0]
		rock.scale = Vector3.ONE * entry[1]
		add_child(rock)
		_configure_mobile_visibility(rock, 30.0)
	for entry in [
		[Vector3(-9.0, 0.35, 2.5), 1.2], [Vector3(-5.5, 0.4, 5.0), 1.0],
		[Vector3(6.0, 0.4, 4.5), 1.05], [Vector3(9.0, 0.45, 6.0), 0.85]
	]:
		var tree := TREE_SCENE.instantiate()
		tree.position = entry[0]
		tree.scale = Vector3.ONE * entry[1]
		add_child(tree)
		_configure_mobile_visibility(tree, 26.0)
	player_marker = Node3D.new()
	player_marker.name = "PlayerSpawnMarker"
	player_marker.position = Vector3(0.0, 0.7, 5.5)
	add_child(player_marker)

func _configure_mobile_visibility(root: Node, max_distance: float) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			child.visibility_range_end = max_distance
			child.visibility_range_end_margin = 4.0
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if child.get_child_count() > 0:
			_configure_mobile_visibility(child, max_distance)

func _build_cameras() -> void:
	gameplay_camera = Camera3D.new()
	gameplay_camera.name = "GameplayCamera"
	gameplay_camera.position = GAMEPLAY_CAMERA
	gameplay_camera.current = true
	add_child(gameplay_camera)
	gameplay_camera.look_at(Vector3(1.0, 1.6, -3.0))
	cinematic_camera = Camera3D.new()
	cinematic_camera.name = "CinematicRevealCamera"
	cinematic_camera.position = CINEMATIC_START_CAMERA
	cinematic_camera.current = false
	add_child(cinematic_camera)
	cinematic_camera.look_at(Vector3(0.0, 1.4, -2.0))

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
	if _reduced_motion:
		set_gameplay_view()
		return
	_cinematic_tween = create_tween()
	_cinematic_tween.tween_property(cinematic_camera, "position", Vector3(-3.0, 3.5, 6.0), 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cinematic_tween.tween_property(cinematic_camera, "position", GAMEPLAY_CAMERA, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cinematic_tween.finished.connect(set_gameplay_view)

func skip_cinematic() -> void:
	set_gameplay_view()

func _process(_delta: float) -> void:
	if ship_focal:
		ship_focal.position = _ship_base_position + Vector3(0.0, sin(Time.get_ticks_msec() * 0.0012) * 0.035, 0.0)
	if _cinematic_active and cinematic_camera and cinematic_camera.current:
		cinematic_camera.look_at(Vector3(1.0, 1.6, -3.0))
	if _cinematic_active and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel")):
		skip_cinematic()
