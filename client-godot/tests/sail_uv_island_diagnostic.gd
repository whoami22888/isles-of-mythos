extends SceneTree
## Read-only diagnostic of the pinned imported Dutch ship; never alters source geometry.
const SHIP := preload("res://assets/external/polyhaven/dutch_ship_medium/dutch_ship_medium_1k.gltf")

func _init() -> void:
	call_deferred("_run")


func _root_of(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		i = parent[i]
	return i


func _join(parent: Array[int], a: int, b: int) -> void:
	var ra := _root_of(parent, a)
	var rb := _root_of(parent, b)
	if ra != rb:
		parent[rb] = ra


func _run() -> void:
	var ship := SHIP.instantiate()
	root.add_child(ship)
	await process_frame
	var components: Array = []
	var pending: Array[Node] = [ship]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and str(node.name).to_lower().contains("sail"):
			var instance := node as MeshInstance3D
			for surface in range(instance.mesh.get_surface_count()):
				var arrays: Array = instance.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var parent: Array[int] = []
				parent.resize(vertices.size())
				for i in range(parent.size()):
					parent[i] = i
				for t in range(0, idx.size(), 3):
					_join(parent, idx[t], idx[t + 1])
					_join(parent, idx[t], idx[t + 2])
				var groups := {}
				for vertex_index in range(vertices.size()):
					var label := _root_of(parent, vertex_index)
					if not groups.has(label):
						groups[label] = {"min": vertices[vertex_index], "max": vertices[vertex_index],
							"uv_min": uvs[vertex_index], "uv_max": uvs[vertex_index], "vertices": 0,
							"triangles": 0}
					var entry: Dictionary = groups[label]
					entry["min"] = (entry["min"] as Vector3).min(vertices[vertex_index])
					entry["max"] = (entry["max"] as Vector3).max(vertices[vertex_index])
					entry["uv_min"] = (entry["uv_min"] as Vector2).min(uvs[vertex_index])
					entry["uv_max"] = (entry["uv_max"] as Vector2).max(uvs[vertex_index])
					entry["vertices"] += 1
				for t in range(0, idx.size(), 3):
					groups[_root_of(parent, idx[t])]["triangles"] += 1
				for key in groups:
					var entry: Dictionary = groups[key]
					var size: Vector3 = entry["max"] - entry["min"]
					var uv_size: Vector2 = entry["uv_max"] - entry["uv_min"]
					components.append({"vertices": entry["vertices"], "triangles": entry["triangles"],
						"min": entry["min"], "max": entry["max"],
						"size": size, "uv_min": entry["uv_min"], "uv_max": entry["uv_max"],
						"uv_size": uv_size})
		for child in node.get_children():
			pending.append(child)
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["triangles"] > b["triangles"])
	print("SAIL_COMPONENT_COUNT=%d" % components.size())
	for i in range(mini(components.size(), 75)):
		print("SAIL_COMPONENT_%d=%s" % [i, JSON.stringify(components[i])])
	quit(0)
