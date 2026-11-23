extends RefCounted
## Builds a camera-only collision surface from the existing coastal heightfield.
## The collision layer is queried by CameraZoomController only; gameplay bodies
## retain their existing server-authoritative movement and collision behaviour.

const SAMPLE_COLUMNS := 73
const SAMPLE_ROWS := 59


static func build_for(coastal: Node3D, collision_layer: int) -> StaticBody3D:
	if coastal == null or not coastal.has_method("_terrain_height"):
		push_error("Camera terrain collision requires a coastal heightfield source")
		return null
	if collision_layer <= 0:
		push_error("Camera terrain collision requires a non-zero presentation layer")
		return null

	var heights := PackedFloat32Array()
	heights.resize(SAMPLE_COLUMNS * SAMPLE_ROWS)
	for z in range(SAMPLE_ROWS):
		var pz := float(z) - float(SAMPLE_ROWS - 1) * 0.5
		for x in range(SAMPLE_COLUMNS):
			var px := float(x) - float(SAMPLE_COLUMNS - 1) * 0.5
			var sample: Variant = coastal.call("_terrain_height", px, pz)
			if typeof(sample) != TYPE_FLOAT and typeof(sample) != TYPE_INT:
				push_error("Camera terrain collision received a non-numeric height sample")
				return null
			var height := float(sample)
			if is_nan(height) or is_inf(height):
				push_error("Camera terrain collision received a non-finite height sample")
				return null
			heights[z * SAMPLE_COLUMNS + x] = height

	var heightmap := HeightMapShape3D.new()
	heightmap.map_width = SAMPLE_COLUMNS
	heightmap.map_depth = SAMPLE_ROWS
	heightmap.map_data = heights

	var collision_body := StaticBody3D.new()
	collision_body.name = "CameraTerrainCollision"
	collision_body.collision_layer = collision_layer
	collision_body.collision_mask = 0
	collision_body.input_ray_pickable = false
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CameraTerrainHeightmapShape"
	collision_shape.shape = heightmap
	collision_body.add_child(collision_shape)
	return collision_body
