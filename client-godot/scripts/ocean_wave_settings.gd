extends Node
## Scene-owned controls for the terrain-sampled mobile ocean.
## Deferred application is required because the parent builds the ocean in _ready().

@export_range(0.1, 5.0, 0.05) var wave_speed: float = 1.45
@export_range(0.0, 1.0, 0.01) var wave_amplitude: float = 0.65
@export_range(0.05, 0.6, 0.01) var wave_frequency: float = 0.18
@export_range(0.0, 1.0, 0.01) var wave_steepness_a: float = 0.68
@export_range(0.0, 1.0, 0.01) var wave_steepness_b: float = 0.52


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
	# Keep the world-anchored wake on the exact same wave parameters.
	# Deferred because CoastalShipEffects binds its runtime wake in _ready().
	call_deferred("_sync_wake_material", coast, material)


func _sync_wake_material(coast: Node, ocean_material: ShaderMaterial) -> void:
	var effects := coast.get_node_or_null("CoastalShipEffects")
	if effects == null:
		return
	var wake: Variant = effects.get("wake")
	if is_instance_valid(wake) and wake.has_method("sync_ocean_wave_parameters"):
		wake.call("sync_ocean_wave_parameters", ocean_material)
