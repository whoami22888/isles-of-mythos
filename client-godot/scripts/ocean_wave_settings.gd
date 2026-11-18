extends Node
## Scene-owned controls for the terrain-sampled mobile ocean.
## Deferred application is required because the parent builds the ocean in _ready().

@export_range(0.1, 5.0, 0.05) var wave_speed: float = 1.25
@export_range(0.0, 1.0, 0.01) var wave_amplitude: float = 0.4
@export_range(0.05, 0.6, 0.01) var wave_frequency: float = 0.18
@export_range(0.0, 1.0, 0.01) var wave_steepness_a: float = 0.55
@export_range(0.0, 1.0, 0.01) var wave_steepness_b: float = 0.40


func _ready() -> void:
	await get_tree().process_frame
	_apply_to_ocean()


func _apply_to_ocean() -> void:
	var coast := get_parent()
	if coast == null:
		push_error("Ocean wave settings require the coastal scene parent")
		return
	var ocean := coast.get_node_or_null("ShallowToDeepWater") as MeshInstance3D
	if ocean == null:
		push_error("Ocean wave settings could not find ShallowToDeepWater")
		return
	var material := ocean.material_override as ShaderMaterial
	if material == null or material.shader == null:
		push_error("Ocean wave settings require the existing ShaderMaterial")
		return
	material.set_shader_parameter("wave_speed", wave_speed)
	material.set_shader_parameter("wave_amplitude", wave_amplitude)
	material.set_shader_parameter("wave_frequency", wave_frequency)
	material.set_shader_parameter("wave_steepness_a", wave_steepness_a)
	material.set_shader_parameter("wave_steepness_b", wave_steepness_b)
