extends SceneTree

const SCENES := [
	"res://scenes/realistic_coastal_slice.tscn",
	"res://scenes/realistic_coastal_fx_slice.tscn",
]

func _init() -> void:
	call_deferred("_audit")

func _audit() -> void:
	var report := {}
	var ship_motion_verified := false
	for scene_path in SCENES:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			printerr("RUNTIME_GRAPHICS_FAIL: cannot load " + scene_path)
			quit(1)
			return
		var scene := packed.instantiate()
		root.add_child(scene)
		await process_frame
		await process_frame
		var meshes := []
		var pending: Array[Node] = [scene]
		while not pending.is_empty():
			var node: Node = pending.pop_back()
			if node is MeshInstance3D and (node as MeshInstance3D).mesh:
				var mesh_node := node as MeshInstance3D
				var surfaces := []
				for i in range(mesh_node.mesh.get_surface_count()):
					var arrays: Array = mesh_node.mesh.surface_get_arrays(i)
					var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var triangles := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
					var material := mesh_node.get_active_material(i) as BaseMaterial3D
					var texture := material.albedo_texture if material else null
					var alpha := false
					if texture is Texture2D:
						var image := texture.get_image()
						alpha = image != null and image.detect_alpha() != Image.ALPHA_NONE
					surfaces.append({
						"triangles": triangles,
						"material": str(material.resource_name) if material else "",
						"transparency": material.transparency if material else -1,
						"albedo_alpha": alpha,
						"texture": texture.resource_path if texture else "",
					})
				meshes.append({"node": str(scene.get_path_to(node)), "surfaces": surfaces})
			for child in node.get_children():
				pending.append(child)
		report[scene_path] = meshes
		if scene_path.ends_with("realistic_coastal_fx_slice.tscn"):
			var fx := scene.get_node_or_null("CoastalShipEffects")
			if fx != null and fx.components_ready():
				var vessel := fx.vessel as Node3D
				var start := vessel.position
				fx.start_visual_demo()
				fx.advance_visual_demo(0.1)
				ship_motion_verified = vessel.position.distance_to(start) > 0.01
				fx.stop_visual_demo()
				ship_motion_verified = ship_motion_verified and vessel.position.distance_to(start) < 0.001
		scene.queue_free()
		await process_frame
	report["__ship_motion_verified__"] = ship_motion_verified
	print("RUNTIME_GRAPHICS_JSON=" + JSON.stringify(report))
	quit(0)
