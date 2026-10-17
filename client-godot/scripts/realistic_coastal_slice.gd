extends Node3D
## Reference-driven coastal slice. Geometry is authored once at load; gameplay authority stays server-side.

const ROCK_SCENE := preload("res://assets/external/polyhaven/coast_rocks_05/coast_rocks_05_1k.gltf")
const TREE_SCENE := preload("res://assets/external/polyhaven/tree_small_02/tree_small_02_1k.gltf")
const SHIP_SCENE := preload("res://assets/external/polyhaven/dutch_ship_medium/dutch_ship_medium_1k.gltf")
const COAST_DIFFUSE := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_diff_1k.jpg")
const COAST_NORMAL := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_nor_gl_1k.jpg")
const COAST_ROUGHNESS := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_rough_1k.jpg")
const COAST_AO := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_ao_1k.jpg")
const WATER_Y := -0.35
const GAMEPLAY_CAMERA := Vector3(9.5, 5.2, 8.5)

var gameplay_camera: Camera3D
var cinematic_camera: Camera3D
var player_marker: Node3D
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
	plane.size = Vector2(70.0, 54.0)
	water.mesh = plane
	water.position.y = WATER_Y
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform vec4 shallow : source_color = vec4(0.025, 0.19, 0.29, 1.0);
uniform vec4 deep : source_color = vec4(0.005, 0.035, 0.11, 1.0);
void fragment() {
    float depth_band = clamp(UV.x * 0.34 + UV.y * 0.22, 0.0, 1.0);
    ALBEDO = mix(shallow.rgb, deep.rgb, depth_band);
    ROUGHNESS = 0.22;
    SPECULAR = 0.8;
}
"""
	material.shader = shader
	water.material_override = material
	add_child(water)
	# Authored shoreline foam bands: bounded geometry, no per-frame generation.
	for location in [Vector3(-7.5, WATER_Y + 0.015, -3.4), Vector3(1.0, WATER_Y + 0.015, -4.0), Vector3(8.0, WATER_Y + 0.015, -2.7)]:
		var foam := MeshInstance3D.new()
		var foam_mesh := QuadMesh.new()
		foam_mesh.size = Vector2(5.0, 0.22)
		foam.mesh = foam_mesh
		foam.position = location
		foam.rotation_degrees.x = -90.0
		var foam_mat := StandardMaterial3D.new()
		foam_mat.albedo_color = Color(0.92, 0.98, 0.94, 0.72)
		foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		foam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		foam.material_override = foam_mat
		add_child(foam)

func _build_premium_landmarks() -> void:
	var ship := SHIP_SCENE.instantiate()
	ship.name = "HarbourShipFocalPoint"
	ship.position = Vector3(2.0, -0.05, -7.5)
	ship.rotation_degrees = Vector3(0.0, 18.0, 0.0)
	ship.scale = Vector3.ONE * 0.72
	add_child(ship)
	for entry in [
		[Vector3(-8.0, 0.35, -2.1), 1.9], [Vector3(-2.0, 0.25, -1.4), 1.35],
		[Vector3(6.8, 0.48, -2.7), 1.65], [Vector3(11.0, 1.05, 3.5), 2.4]
	]:
		var rock := ROCK_SCENE.instantiate()
		rock.position = entry[0]
		rock.scale = Vector3.ONE * entry[1]
		add_child(rock)
	for entry in [
		[Vector3(-9.0, 1.0, 2.5), 1.2], [Vector3(-5.5, 1.05, 5.0), 1.0],
		[Vector3(3.5, 1.0, 4.5), 1.15], [Vector3(9.0, 1.0, 6.0), 0.9]
	]:
		var tree := TREE_SCENE.instantiate()
		tree.position = entry[0]
		tree.scale = Vector3.ONE * entry[1]
		add_child(tree)
	player_marker = Node3D.new()
	player_marker.name = "PlayerSpawnMarker"
	player_marker.position = Vector3(0.0, 0.7, 5.5)
	add_child(player_marker)

func _build_cameras() -> void:
	gameplay_camera = Camera3D.new()
	gameplay_camera.name = "GameplayCamera"
	gameplay_camera.position = GAMEPLAY_CAMERA
	gameplay_camera.current = true
	add_child(gameplay_camera)
	gameplay_camera.look_at(Vector3(1.0, 0.8, -3.0))
	cinematic_camera = Camera3D.new()
	cinematic_camera.name = "CinematicRevealCamera"
	cinematic_camera.position = Vector3(-8.0, 4.5, 9.0)
	cinematic_camera.current = false
	add_child(cinematic_camera)
	cinematic_camera.look_at(Vector3(0.0, 0.5, -2.0))

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
	if _cinematic_active and cinematic_camera and cinematic_camera.current:
		cinematic_camera.look_at(Vector3(1.0, 0.8, -3.0))
	if _cinematic_active and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel")):
		skip_cinematic()
