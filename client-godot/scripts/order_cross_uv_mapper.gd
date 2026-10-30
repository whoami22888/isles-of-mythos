extends RefCounted
## Derive independent emblem coordinates from disconnected imported sail panels.
## Original TEXCOORD_0, geometry, indices and authored PBR textures are unchanged.
## The source Dutch ship has exactly four components: two furled upper pieces
## and two larger lower sail panels. Do not stamp emblems onto small flags.

const MIN_PANEL_HEIGHT := 1.8
const MIN_PANEL_WIDTH := 3.0
const MIN_PANEL_TRIANGLES := 250
const UNUSED_UV := Vector2(-1.0, -1.0)


static func _root_of(parent: Array[int], vertex: int) -> int:
	while parent[vertex] != vertex:
		vertex = parent[vertex]
	return vertex


static func _join(parent: Array[int], first: int, second: int) -> void:
	var a := _root_of(parent, first)
	var b := _root_of(parent, second)
	if a != b:
		parent[b] = a


static func generate(arrays: Array) -> Dictionary:
	if arrays.size() != Mesh.ARRAY_MAX:
		return {"error": "Malformed sail surface arrays"}
	if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
		return {"error": "Missing sail positions"}
	if not arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
		return {"error": "Missing original sail atlas UV"}
	if not arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		return {"error": "Sail surface must be indexed"}
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var atlas_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.is_empty() or atlas_uv.size() != vertices.size():
		return {"error": "Sail vertices/atlas UV count mismatch"}
	if indices.is_empty() or indices.size() % 3 != 0:
		return {"error": "Non-triangular sail geometry"}
	if arrays[Mesh.ARRAY_TEX_UV2] is PackedVector2Array:
		var old_uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		if not old_uv2.is_empty():
			return {"error": "Refusing to overwrite existing lightmap UV2"}
	for index in indices:
		if index < 0 or index >= vertices.size():
			return {"error": "Out-of-bounds sail triangle index"}

	var parent: Array[int] = []
	parent.resize(vertices.size())
	for i in range(parent.size()):
		parent[i] = i
	for t in range(0, indices.size(), 3):
		_join(parent, indices[t], indices[t + 1])
		_join(parent, indices[t], indices[t + 2])
	var bounds: Dictionary = {}
	for vertex_index in range(vertices.size()):
		var label := _root_of(parent, vertex_index)
		if not bounds.has(label):
			bounds[label] = {
				"min": vertices[vertex_index],
				"max": vertices[vertex_index],
				"triangles": 0
			}
		var b: Dictionary = bounds[label]
		b["min"] = (b["min"] as Vector3).min(vertices[vertex_index])
		b["max"] = (b["max"] as Vector3).max(vertices[vertex_index])
	for t in range(0, indices.size(), 3):
		bounds[_root_of(parent, indices[t])]["triangles"] += 1

	var decorated: Dictionary = {}
	for label in bounds:
		var b: Dictionary = bounds[label]
		var extent: Vector3 = b["max"] - b["min"]
		var width := maxf(extent.x, extent.z)
		if extent.y >= MIN_PANEL_HEIGHT and width >= MIN_PANEL_WIDTH and b["triangles"] >= MIN_PANEL_TRIANGLES:
			decorated[label] = b
	# Fail closed if the upstream asset layout changes. Do not paint the
	# entire texture atlas or rigging as a fallback.
	if bounds.size() != 4 or decorated.size() != 2:
		return {"error": "Unexpected imported Dutch sail layout: %d components, %d usable panels" % [
			bounds.size(), decorated.size()
		]}

	var uv2 := PackedVector2Array()
	uv2.resize(vertices.size())
	uv2.fill(UNUSED_UV)
	for vertex_index in range(vertices.size()):
		var label := _root_of(parent, vertex_index)
		if not decorated.has(label):
			continue
		var b: Dictionary = decorated[label]
		var minimum: Vector3 = b["min"]
		var extent: Vector3 = b["max"] - minimum
		var v: Vector3 = vertices[vertex_index]
		var horizontal := (v.z - minimum.z) / extent.z if extent.z >= extent.x else (v.x - minimum.x) / extent.x
		var vertical := (v.y - minimum.y) / extent.y
		uv2[vertex_index] = Vector2(clampf(horizontal, 0.0, 1.0), clampf(vertical, 0.0, 1.0))
	return {
		"uv2": uv2,
		"components": bounds.size(),
		"decorated_panels": decorated.size(),
		"vertex_count": vertices.size(),
		"index_count": indices.size(),
	}


static func create_mesh(source: ArrayMesh, surface_index: int) -> Dictionary:
	if source == null or surface_index < 0 or surface_index >= source.get_surface_count():
		return {"error": "Invalid imported sail mesh"}
	if source.get_blend_shape_count() != 0:
		return {"error": "Animated source blend shapes need explicit preservation"}
	var output := ArrayMesh.new()
	for surface in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface)
		if surface == surface_index:
			var mapping := generate(arrays)
			if mapping.has("error"):
				return mapping
			arrays[Mesh.ARRAY_TEX_UV2] = mapping["uv2"]
		output.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
		output.surface_set_material(surface, source.surface_get_material(surface))
		output.surface_set_name(surface, source.surface_get_name(surface))
	output.resource_name = "DutchShip_OrderCrossUV2"
	return {"mesh": output, "decorated_panels": 2}
