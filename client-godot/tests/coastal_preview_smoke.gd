extends SceneTree
## Composition scaffolding check; this does not grant premium-art acceptance.

func _init() -> void:
	call_deferred("run")


func run() -> void:
	var packed := load("res://scenes/coastal_preview.tscn") as PackedScene
	if packed == null:
		push_error("Coastal preview scene could not be loaded")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	var island := scene.get_node_or_null("Island")
	var props := scene.get_node_or_null("CoastalProps")
	var camera := root.get_viewport().get_camera_3d()
	var ok := island != null and props != null and camera != null and camera.current
	if ok:
		ok = props.get_child_count() == 9 and island.get_node_or_null("PreviewPlayer") != null
		for index in range(6):
			var rock := props.get_node_or_null("CoastalRock_%02d" % index) as MeshInstance3D
			ok = ok and rock != null
			if rock != null:
				ok = ok and rock.mesh != null and rock.material_override != null and rock.position.is_finite()
		for index in range(6, 9):
			var palm := props.get_node_or_null("Palm_%d" % index)
			ok = ok and palm != null
			if palm != null:
				ok = ok and palm.get_child_count() == 12
				for child in palm.get_children():
					ok = ok and child is MeshInstance3D
					if child is MeshInstance3D:
						ok = ok and child.mesh != null and child.material_override != null and child.position.is_finite()
	if not ok:
		push_error("Coastal preview composition, materials or active camera check failed")
	scene.queue_free()
	print("Coastal preview scaffolding smoke: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
