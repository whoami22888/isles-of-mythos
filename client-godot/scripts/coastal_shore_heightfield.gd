extends RefCounted
## One-time coastal heightfield bridge for the server-independent Godot visual client.
##
## Samples the ACTUAL authored terrain ArrayMesh, not a copied terrain equation.
## Only the real terrain owner creates/modifies the mesh; the ocean owner consumes
## the resulting float texture via coastal_shore_sampler.gdshaderinc.
## No per-frame CPU tessellation or readback, gameplay physics, or network authority.

const MAX_SAMPLES := 262144
const GRID_EPSILON := 0.012

static func bake(terrain: MeshInstance3D, columns: int, rows: int) -> Dictionary:
	if terrain == null or terrain.mesh == null:
		return {"error": "Missing terrain mesh"}
	if columns < 2 or rows < 2 or columns * rows > MAX_SAMPLES:
		return {"error": "Invalid or unbounded terrain grid"}
	if terrain.mesh.get_surface_count() != 1:
		return {"error": "Expected one indexed terrain surface"}
	if terrain.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		return {"error": "Terrain must contain indexed triangles"}

	var arrays := terrain.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() != columns * rows:
		return {"error": "Terrain vertex count does not match grid dimensions"}
	if indices.size() != (columns - 1) * (rows - 1) * 6:
		return {"error": "Terrain triangle count does not match grid topology"}

	# Revalidate the indices: unrelated triangle layouts are unsafe to sample as
	# a regular heightfield even if they have the expected vertex count.
	for z in range(rows - 1):
		for x in range(columns - 1):
			var i := z * columns + x
			var expected := [i, i + 1, i + columns, i + columns + 1]
			var offset := (z * (columns - 1) + x) * 6
			for j in range(6):
				if not expected.has(indices[offset + j]):
					return {"error": "Terrain has non-grid triangle topology"}

	var transform := terrain.global_transform
	var first: Vector3 = transform * vertices[0]
	var last_x: Vector3 = transform * vertices[columns - 1]
	var last_z: Vector3 = transform * vertices[(rows - 1) * columns]
	var origin := Vector2(first.x, first.z)
	var extent := Vector2(last_x.x - first.x, last_z.z - first.z)
	if extent.x < GRID_EPSILON or extent.y < GRID_EPSILON:
		return {"error": "Terrain grid must be ascending and non-degenerate in world X/Z"}

	# The one-time float texture is 4 bytes per vertex (about 27 KiB at
	# 96 x 72). Never bake every frame and never store positions twice on GPU.
	var image := Image.create(columns, rows, false, Image.FORMAT_RF)
	for z in range(rows):
		for x in range(columns):
			var point: Vector3 = transform * vertices[z * columns + x]
			var expected_x := origin.x + extent.x * float(x) / float(columns - 1)
			var expected_z := origin.y + extent.y * float(z) / float(rows - 1)
			if absf(point.x - expected_x) > GRID_EPSILON or absf(point.z - expected_z) > GRID_EPSILON:
				return {"error": "Terrain grid is rotated, reordered, or irregularly spaced in world X/Z"}
			image.set_pixel(x, z, Color(point.y, 0.0, 0.0, 1.0))

	return {
		"image": image,
		"origin": origin,
		"extent": extent,
		"resolution": Vector2i(columns, rows)
	}


static func uv_for_world(baked: Dictionary, point_xz: Vector2) -> Vector2:
	# A grid vertex must map to the CENTRE of its height texel, not to a
	# texture edge; that half-texel correction prevents displaced foam edges.
	var origin: Vector2 = baked["origin"]
	var extent: Vector2 = baked["extent"]
	var size: Vector2i = baked["resolution"]
	var uv := (point_xz - origin) / extent
	return uv * Vector2(float(size.x - 1) / float(size.x), float(size.y - 1) / float(size.y)) 		+ Vector2(0.5 / float(size.x), 0.5 / float(size.y))


static func sample_height(baked: Dictionary, point_xz: Vector2) -> float:
	# A deterministic CPU contract for tests and non-rendering diagnostic use.
	# The GPU uses equivalent bilinear texel-centre mapping in the shader include.
	var image: Image = baked["image"]
	var origin: Vector2 = baked["origin"]
	var extent: Vector2 = baked["extent"]
	var size: Vector2i = baked["resolution"]
	var p := ((point_xz - origin) / extent) * Vector2(size.x - 1, size.y - 1)
	p = p.clamp(Vector2.ZERO, Vector2(size.x - 1, size.y - 1))
	var x0 := int(floorf(p.x))
	var z0 := int(floorf(p.y))
	var x1 := mini(x0 + 1, size.x - 1)
	var z1 := mini(z0 + 1, size.y - 1)
	var lo := lerpf(image.get_pixel(x0, z0).r, image.get_pixel(x1, z0).r, p.x - float(x0))
	var hi := lerpf(image.get_pixel(x0, z1).r, image.get_pixel(x1, z1).r, p.x - float(x0))
	return lerpf(lo, hi, p.y - float(z0))


static func bind_to_material(terrain: MeshInstance3D, ocean: ShaderMaterial, columns: int, rows: int) -> Dictionary:
	if ocean == null or ocean.shader == null:
		return {"error": "Ocean must have an existing ShaderMaterial"}
	var code: String = ocean.shader.code
	if not code.contains("shore_heightmap") and not code.contains("coastal_shore_sampler.gdshaderinc"):
		return {"error": "Ocean shader has no shoreline heightfield sampling contract"}
	var baked := bake(terrain, columns, rows)
	if baked.has("error"):
		return baked
	var texture := ImageTexture.create_from_image(baked["image"])
	ocean.set_shader_parameter("shore_heightmap", texture)
	ocean.set_shader_parameter("shore_origin_xz", baked["origin"])
	ocean.set_shader_parameter("shore_extent_xz", baked["extent"])
	ocean.set_shader_parameter("shore_texture_size", Vector2(columns, rows))
	# Return the binding so callers can retain it and CI can inspect contents.
	return {
		"texture": texture,
		"origin": baked["origin"],
		"extent": baked["extent"],
		"resolution": baked["resolution"]
	}
