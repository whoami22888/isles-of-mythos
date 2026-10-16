extends WorldEnvironment
## Deterministic coastal lighting baseline for Godot mobile renderer.
@export var horizon_color := Color(0.57, 0.73, 0.82)
@export var sky_color := Color(0.23, 0.46, 0.69)
@export var ambient_energy := 0.65

func _ready() -> void:
    var coastal_environment := Environment.new()
    coastal_environment.background_mode = Environment.BG_COLOR
    coastal_environment.background_color = sky_color
    coastal_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    coastal_environment.ambient_light_color = horizon_color
    coastal_environment.ambient_light_energy = ambient_energy
    coastal_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment = coastal_environment
