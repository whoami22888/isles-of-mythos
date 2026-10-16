extends Node3D
## First-party visual/navigation prototype. No authoritative gameplay state is mutated.

const MOVE_SPEED := 5.0
const ISLAND_RADIUS := 9.0

var _player: Node3D
var _camera: Camera3D
var _touch_target := Vector3.ZERO
var _touch_active := false


func _ready() -> void:
	_build_environment()
	_player = Node3D.new()
	_player.name = "PreviewPlayer"
	add_child(_player)
	_add_mesh(_player, SphereMesh.new(), Vector3(0.0, 0.68, 0.0), Vector3(0.55, 0.7, 0.55), Color(0.95, 0.68, 0.31))
	_camera = Camera3D.new()
	_camera.name = "IslandCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 24.0
	_camera.position = Vector3(15.0, 19.0, 15.0)
	add_child(_camera)
	_camera.look_at(Vector3.ZERO)
	_camera.current = true


func _build_environment() -> void:
	var ocean := BoxMesh.new()
	ocean.size = Vector3(90.0, 0.12, 90.0)
	_add_mesh(self, ocean, Vector3(0.0, -0.85, 0.0), Vector3.ONE, Color(0.05, 0.39, 0.57))
	var coast := _build_coast_mesh()
	var beach := _add_mesh(self, coast, Vector3.ZERO, Vector3.ONE, Color(0.84, 0.72, 0.44))
	beach.name = "CoastalShoreline"
	var grass := CylinderMesh.new()
	grass.top_radius = ISLAND_RADIUS - 1.2
	grass.bottom_radius = ISLAND_RADIUS - 0.95
	grass.height = 0.12
	_add_mesh(self, grass, Vector3(0.0, 0.14, 0.0), Vector3.ONE, Color(0.25, 0.51, 0.27))
	for location in [Vector3(-5.5, 0.0, -3.0), Vector3(5.1, 0.0, -2.8), Vector3(-3.0, 0.0, 5.0), Vector3(4.7, 0.0, 4.2)]:
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.18
		trunk.bottom_radius = 0.29
		trunk.height = 2.3
		_add_mesh(self, trunk, location + Vector3(0.0, 1.25, 0.0), Vector3.ONE, Color(0.38, 0.24, 0.13))
		_add_mesh(self, SphereMesh.new(), location + Vector3(0.0, 2.65, 0.0), Vector3(1.5, 1.05, 1.5), Color(0.11, 0.41, 0.22))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, 28.0, 0.0)
	light.light_energy = 1.3
	add_child(light)



func _coast_radius(angle: float) -> float:
	## Fixed harmonic coastline avoids random scene changes between screenshots.
	return ISLAND_RADIUS + 0.55 * sin(3.0 * angle + 0.4) + 0.35 * sin(7.0 * angle)


func _build_coast_mesh() -> ArrayMesh:
	## Three continuous rings: inner dry sand, shoreline and submerged slope.
	const SEGMENTS := 64
	var radii := PackedFloat32Array([0.0, 0.78, 1.0, 1.18])
	var heights := PackedFloat32Array([-0.04, -0.02, -0.16, -0.88])
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(radii.size() - 1):
		for sector in range(SEGMENTS):
			var a0 := TAU * float(sector) / SEGMENTS
			var a1 := TAU * float(sector + 1) / SEGMENTS
			var vertices := [
				Vector3(cos(a0) * _coast_radius(a0) * radii[ring], heights[ring], sin(a0) * _coast_radius(a0) * radii[ring]),
				Vector3(cos(a1) * _coast_radius(a1) * radii[ring], heights[ring], sin(a1) * _coast_radius(a1) * radii[ring]),
				Vector3(cos(a0) * _coast_radius(a0) * radii[ring + 1], heights[ring + 1], sin(a0) * _coast_radius(a0) * radii[ring + 1]),
				Vector3(cos(a1) * _coast_radius(a1) * radii[ring + 1], heights[ring + 1], sin(a1) * _coast_radius(a1) * radii[ring + 1])
			]
			for corner in [0, 1, 2, 1, 3, 2]:
				var vertex: Vector3 = vertices[corner]
				tool.set_uv(Vector2(vertex.x, vertex.z) / (ISLAND_RADIUS * 2.0) + Vector2(0.5, 0.5))
				tool.add_vertex(vertex)
	tool.generate_normals()
	return tool.commit()


func _add_mesh(parent: Node3D, geometry: Mesh, location: Vector3, scale_value: Vector3, tint: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = geometry
	instance.position = location
	instance.scale = scale_value
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.9
	instance.material_override = material
	parent.add_child(instance)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_set_touch_target(event.position)
	elif event is InputEventScreenDrag:
		_set_touch_target(event.position)


func _set_touch_target(screen_position: Vector2) -> void:
	if _camera == null:
		return
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return
	var distance_to_ground := -origin.y / direction.y
	if distance_to_ground <= 0.0:
		return
	_touch_target = origin + direction * distance_to_ground
	_touch_target.y = 0.0
	_touch_target = _touch_target.limit_length(ISLAND_RADIUS - 1.1)
	_touch_active = true


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	var movement := Vector3.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		movement.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		movement.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		movement.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		movement.z += 1.0
	if movement.length_squared() > 0.0:
		_touch_active = false
		movement = movement.normalized()
	elif _touch_active:
		movement = _touch_target - _player.position
		if movement.length() < 0.12:
			_touch_active = false
			return
		movement = movement.normalized()
	var next_position := _player.position + movement * MOVE_SPEED * delta
	next_position.y = 0.0
	_player.position = next_position.limit_length(ISLAND_RADIUS - 1.1)
