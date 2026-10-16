extends Node3D
## Independent first-party coastal water prototype; no network or gameplay authority.
@export var water_size := 96.0
@export var sea_level := -0.82
@export var wave_height := 0.08
@export var wave_frequency := 0.12
@export var wave_speed := 0.7

var _water: MeshInstance3D

func _ready() -> void:
    _water = MeshInstance3D.new()
    _water.name = "CoastalWater"
    var plane := PlaneMesh.new()
    plane.size = Vector2(water_size, water_size)
    plane.subdivide_width = 48
    plane.subdivide_depth = 48
    _water.mesh = plane
    _water.position.y = sea_level
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.045, 0.30, 0.43, 0.84)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.roughness = 0.24
    material.metallic = 0.05
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    _water.material_override = material
    add_child(_water)

func wave_offset(world_position: Vector2, time_seconds: float) -> float:
    var phase := world_position.x * wave_frequency + time_seconds * wave_speed
    var cross_phase := world_position.y * wave_frequency * 0.7 - time_seconds * wave_speed * 0.8
    return wave_height * (0.65 * sin(phase) + 0.35 * cos(cross_phase))

func _process(delta: float) -> void:
    # Keep mesh static for mobile; animate the material in a later measured shader pass.
    pass
