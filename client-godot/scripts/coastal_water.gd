extends Node3D
## First-party ocean prototype. Visual-only; no gameplay authority.
@export var water_extent := 90.0
@export var sea_level := -0.8
@export var wave_amplitude := 0.12
@export var wave_speed := 0.7
var _surface: MeshInstance3D

func _ready() -> void:
    _surface = MeshInstance3D.new()
    _surface.name = "CoastalWater"
    var plane := PlaneMesh.new()
    plane.size = Vector2(water_extent, water_extent)
    _surface.mesh = plane
    _surface.position.y = sea_level
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.045, 0.31, 0.42, 0.82)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.roughness = 0.24
    material.metallic = 0.08
    _surface.material_override = material
    add_child(_surface)

func _process(delta: float) -> void:
    if _surface == null:
        return
    _surface.position.y = sea_level + sin(Time.get_ticks_msec() * 0.001 * wave_speed) * wave_amplitude
