extends SceneTree
## Deterministic coastal water scene and shoreline readability regression.

func _init() -> void:
	var packed: PackedScene = load("res://scenes/coastal_water_preview.tscn")
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var water := scene.get_node_or_null("CoastalWater") as MeshInstance3D
	var foam := scene.get_node_or_null("ShorelineFoam") as MeshInstance3D
	var camera := scene.get_node_or_null("Camera") as Camera3D
	var valid := water != null and water.mesh is PlaneMesh and foam != null and foam.mesh is TorusMesh
	valid = valid and camera != null and camera.current
	if valid:
		var water_mesh := water.mesh as PlaneMesh
		var foam_mesh := foam.mesh as TorusMesh
		valid = water_mesh.subdivide_width == 48 and water_mesh.subdivide_depth == 48
		valid = valid and foam_mesh.outer_radius > foam_mesh.inner_radius
	var water_script := scene as Node
	var first_wave: float = water_script.wave_offset(Vector2(4.0, -2.0), 1.5)
	var second_wave: float = water_script.wave_offset(Vector2(4.0, -2.0), 1.5)
	valid = valid and is_equal_approx(first_wave, second_wave)
	valid = valid and absf(first_wave) <= water_script.wave_height
	if not valid:
		push_error("Coastal water scene lacks bounded water, foam, or active camera")
		quit(1)
		return
	print("PASS coastal water mesh, shoreline foam, subdivisions and camera")
	quit(0)
