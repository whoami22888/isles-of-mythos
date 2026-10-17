extends SceneTree
## Structural regression for the dedicated coastal scene.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/coastal_vertical_slice.tscn") as PackedScene
	if packed == null:
		_fail("coastal scene failed to load")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var terrain := scene.get_node_or_null("Terrain/SculptedCoast") as MeshInstance3D
	var water := scene.get_node_or_null("Water") as MeshInstance3D
	var camera := scene.get_node_or_null("IslandCamera") as Camera3D
	var environment := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if terrain == null or terrain.mesh == null:
		_fail("coastal terrain geometry missing")
		return
	if terrain.material_override == null or not terrain.material_override is StandardMaterial3D:
		_fail("coastal terrain PBR material missing")
		return
	var terrain_material := terrain.material_override as StandardMaterial3D
	if terrain_material.albedo_texture == null or terrain_material.normal_texture == null or terrain_material.roughness_texture == null:
		_fail("coastal terrain texture maps missing")
		return
	if water == null or water.mesh == null or not water.material_override is ShaderMaterial:
		_fail("coastal water shader surface missing")
		return
	if camera == null or not camera.current:
		_fail("coastal camera is not active")
		return
	if environment == null or environment.environment == null or not environment.environment.fog_enabled:
		_fail("coastal atmosphere is not active")
		return
	print("PASS coastal vertical slice structure")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
