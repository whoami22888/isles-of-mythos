extends SubViewportContainer
## Low-resolution ocean backdrop for the login screen. One small viewport, no shadows.

const OCEAN_SHADER := preload("res://shaders/ocean_surface.gdshader")

var _camera: Camera3D
var _angle := 0.4

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	var viewport := SubViewport.new()
	viewport.name = "OceanViewport"
	viewport.size = Vector2i(384, 216)
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#8fd4ef")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#fff6e4")
	environment.ambient_light_energy = 0.85
	environment_node.environment = environment
	world.add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, -24.0, 0.0)
	sun.light_color = Color("#fff3d2")
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	world.add_child(sun)

	var ocean := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90.0, 90.0)
	plane.subdivide_width = 20
	plane.subdivide_depth = 20
	ocean.mesh = plane
	var water := ShaderMaterial.new()
	water.shader = OCEAN_SHADER
	water.set_shader_parameter("swell_scale", 0.55)
	water.set_shader_parameter("ripple_detail", 0.45)
	water.set_shader_parameter("foam_amount", 0.35)
	ocean.material_override = water
	ocean.position = Vector3(0.0, -0.35, 0.0)
	world.add_child(ocean)

	var island := MeshInstance3D.new()
	var mound := SphereMesh.new()
	mound.radius = 5.5
	mound.height = 4.2
	mound.radial_segments = 12
	mound.rings = 6
	island.mesh = mound
	island.scale = Vector3(1.7, 0.48, 1.25)
	island.position = Vector3(0.2, 0.35, 0.0)
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color("#f0d59a")
	sand.roughness = 0.9
	island.material_override = sand
	world.add_child(island)

	var greens: Array[Color] = [Color("#2f9d62"), Color("#3cb371"), Color("#237a52")]
	var spots: Array[Vector3] = [Vector3(-2.1, 1.45, 0.3), Vector3(1.5, 1.35, -0.8), Vector3(0.3, 1.55, 1.2)]
	for index in spots.size():
		var tree := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.04
		cone.bottom_radius = 0.62
		cone.height = 1.8
		cone.radial_segments = 6
		tree.mesh = cone
		var leaf := StandardMaterial3D.new()
		leaf.albedo_color = greens[index]
		tree.material_override = leaf
		tree.position = spots[index]
		world.add_child(tree)

	_camera = Camera3D.new()
	_camera.fov = 40.0
	world.add_child(_camera)
	_place_camera()

func _place_camera() -> void:
	var orbit := 18.0
	_camera.position = Vector3(cos(_angle) * orbit, 7.2, sin(_angle) * orbit)
	_camera.look_at(Vector3(0.0, 1.1, 0.0))

func _process(delta: float) -> void:
	_angle += delta * 0.07
	_place_camera()
