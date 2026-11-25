class_name IslesNavalBroadsideFx
extends Node3D

## Presentation-only GPU bursts for an acknowledged server broadside. No gameplay authority.

const SMOKE_SHADER: Shader = preload("res://shaders/naval_cannon_smoke.gdshader")
const SPLINTER_SHADER: Shader = preload("res://shaders/naval_wood_splinter.gdshader")

var port_smoke: GPUParticles3D
var starboard_smoke: GPUParticles3D
var splinters: GPUParticles3D

func _ready() -> void:
	port_smoke = _make_smoke("PortCannonSmoke", Vector3(1.6, 1.1, 0.0))
	starboard_smoke = _make_smoke("StarboardCannonSmoke", Vector3(-1.6, 1.1, 0.0))
	splinters = _make_splinters("WoodSplinterBurst")
	add_child(port_smoke)
	add_child(starboard_smoke)
	add_child(splinters)

func play_fire(side: String) -> void:
	var emitter := port_smoke if side == "port" else starboard_smoke
	_restart(emitter)

func play_impact() -> void:
	_restart(splinters)

func is_ready() -> bool:
	return is_instance_valid(port_smoke) and is_instance_valid(starboard_smoke) and is_instance_valid(splinters)

func _restart(emitter: GPUParticles3D) -> void:
	if not is_instance_valid(emitter):
		return
	emitter.restart()
	emitter.emitting = true

func _make_smoke(node_name: String, local_offset: Vector3) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.position = local_offset
	particles.amount = 48
	particles.lifetime = 0.85
	particles.explosiveness = 0.92
	particles.one_shot = true
	particles.emitting = false
	particles.fixed_fps = 30
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-8.0, -3.0, -8.0), Vector3(16.0, 10.0, 16.0))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(signf(local_offset.x), 0.45, 0.0)
	process.spread = 28.0
	process.initial_velocity_min = 2.4
	process.initial_velocity_max = 5.2
	process.gravity = Vector3(0.0, 0.6, 0.0)
	process.scale_min = 0.7
	process.scale_max = 1.4
	process.damping_min = 0.8
	process.damping_max = 1.6
	process.color = Color(0.78, 0.74, 0.68, 0.85)
	particles.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.7, 0.7)
	var material := ShaderMaterial.new()
	material.shader = SMOKE_SHADER
	mesh.material = material
	particles.draw_pass_1 = mesh
	return particles

func _make_splinters(node_name: String) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.position = Vector3(0.0, 1.2, 0.0)
	particles.amount = 36
	particles.lifetime = 0.7
	particles.explosiveness = 1.0
	particles.one_shot = true
	particles.emitting = false
	particles.fixed_fps = 30
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-6.0, -2.0, -6.0), Vector3(12.0, 8.0, 12.0))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 70.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 7.5
	process.gravity = Vector3(0.0, -12.0, 0.0)
	process.scale_min = 0.08
	process.scale_max = 0.18
	process.angular_velocity_min = -18.0
	process.angular_velocity_max = 18.0
	particles.process_material = process
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.04, 0.03)
	var material := ShaderMaterial.new()
	material.shader = SPLINTER_SHADER
	mesh.material = material
	particles.draw_pass_1 = mesh
	return particles
