extends SceneTree
## Budget and quality contract for the tropical bay dressing. Not a visual-parity claim.

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var scene: Node3D = load("res://scenes/realistic_coastal_slice.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var ok := true
	var dressing := scene.get_node_or_null("TropicalBayDressing")
	ok = _check(dressing != null, "dressing node") and ok
	var palms := dressing.get_node_or_null("TropicalPalmGrove") as MultiMeshInstance3D if dressing else null
	var grass := dressing.get_node_or_null("TropicalGrassTufts") as MultiMeshInstance3D if dressing else null
	ok = _check(palms != null and palms.multimesh != null, "palm multimesh") and ok
	ok = _check(grass != null and grass.multimesh != null, "grass multimesh") and ok
	if palms and palms.multimesh:
		ok = _check(palms.multimesh.visible_instance_count >= 24, "enough palms for a grove") and ok
		ok = _check(palms.multimesh.visible_instance_count <= 96, "palm instance cap") and ok
	var dressing_script = load("res://scripts/tropical_bay_dressing.gd")
	ok = _check(dressing_script.palm_triangle_count() < 120, "palm mesh stays cheap") and ok
	ok = _check(scene.get_node_or_null("TropicalBayDressing/DistantVolcano") != null, "volcano landmark") and ok
	ok = _check(scene.get_node_or_null("TropicalBayDressing/HazyIslets") != null, "distant islets") and ok
	var premium := scene.get_node_or_null("VerifiedTropicalContentLayer")
	if premium:
		for child in premium.get_children():
			if child.scene_file_path.ends_with("coastal_cliff_01_1k.gltf"):
				var triangles := 0
				for mesh_node in child.find_children("*", "MeshInstance3D", true, false):
					var mesh_instance := mesh_node as MeshInstance3D
					if mesh_instance.mesh == null:
						continue
					for surface_index in range(mesh_instance.mesh.get_surface_count()):
						var indices: PackedInt32Array = mesh_instance.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX]
						triangles += indices.size() / 3
				ok = _check(triangles < 200, "cliff proxy triangle budget") and ok
	scene.apply_visual_quality(0)
	if palms and palms.multimesh:
		ok = _check(palms.multimesh.visible_instance_count <= 32, "low quality reduces palms") and ok
		ok = _check(grass.multimesh.visible_instance_count == 0, "low quality drops grass cards") and ok
	var sun := scene.get_node_or_null("WarmSun") as DirectionalLight3D
	ok = _check(sun != null and not sun.shadow_enabled, "low quality disables shadows") and ok
	scene.apply_visual_quality(2)
	ok = _check(sun.shadow_enabled, "high quality restores shadows") and ok
	print("Tropical bay dressing test: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

func _check(condition: bool, label: String) -> bool:
	if not condition:
		printerr("FAILED: " + label)
	return condition
