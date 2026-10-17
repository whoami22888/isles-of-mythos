extends Node3D
## Independent first-party coastal water prototype; no network or gameplay authority.
@export var water_size := 96.0
@export var sea_level := -0.82
@export var wave_height := 0.08
@export var wave_frequency := 0.12
@export var wave_speed := 0.7
@export var shoreline_radius := 18.0
@export var shoreline_width := 1.2

var _water: MeshInstance3D

func _ready() -> void:
	build_preview()

func build_preview() -> void:
	if _water != null:
		return
	_water = MeshInstance3D.new()
	_water.name = "CoastalWater"
	var plane := PlaneMesh.new()
	plane.size = Vector2(water_size, water_size)
	plane.subdivide_width = 48
	plane.subdivide_depth = 48
	_water.mesh = plane
	_water.position.y = sea_level
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, blend_mix;
uniform vec4 deep_color : source_color = vec4(0.015, 0.18, 0.30, 0.84);
uniform vec4 shallow_color : source_color = vec4(0.08, 0.48, 0.58, 0.84);
uniform float wave_height = 0.08;
uniform float wave_frequency = 0.12;
uniform float wave_speed = 0.7;
void vertex() {
	float phase = VERTEX.x * wave_frequency + TIME * wave_speed;
	float cross_phase = VERTEX.z * wave_frequency * 0.7 - TIME * wave_speed * 0.8;
	VERTEX.y += wave_height * (0.65 * sin(phase) + 0.35 * cos(cross_phase));
}

void fragment() {
	float shallow = smoothstep(0.08, 0.92, UV.y);
	ALBEDO = mix(shallow_color.rgb, deep_color.rgb, shallow);
	ROUGHNESS = 0.24;
	METALLIC = 0.05;
	ALPHA = mix(shallow_color.a, deep_color.a, shallow);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("wave_height", wave_height)
	material.set_shader_parameter("wave_frequency", wave_frequency)
	material.set_shader_parameter("wave_speed", wave_speed)
	_water.material_override = material
	add_child(_water)
	var foam := MeshInstance3D.new()
	foam.name = "ShorelineFoam"
	var foam_mesh := TorusMesh.new()
	foam_mesh.inner_radius = shoreline_radius
	foam_mesh.outer_radius = shoreline_radius + shoreline_width
	foam_mesh.rings = 64
	foam_mesh.ring_segments = 8
	foam.mesh = foam_mesh
	foam.position.y = sea_level + 0.015
	var foam_material := StandardMaterial3D.new()
	foam_material.albedo_color = Color(0.72, 0.91, 0.92, 0.52)
	foam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam_material.roughness = 0.68
	foam.material_override = foam_material
	add_child(foam)

func wave_offset(world_position: Vector2, time_seconds: float) -> float:
	var phase := world_position.x * wave_frequency + time_seconds * wave_speed
	var cross_phase := world_position.y * wave_frequency * 0.7 - time_seconds * wave_speed * 0.8
	return wave_height * (0.65 * sin(phase) + 0.35 * cos(cross_phase))
