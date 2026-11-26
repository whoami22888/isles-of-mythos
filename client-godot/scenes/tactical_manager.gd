extends Node3D
class_name TacticalManager
## Prompt 016: top-down tactical defense overlay for base invasions.
##
## Presentation and intent only. The server owns which structures exist, what
## they cost and whether a placement is legal. This node snaps a raycast hit on
## the island terrain plane to the 2.0 m grid, refuses locally occupied cells,
## shows a preview, and emits `placement_requested` for the protocol to send.
## It never spends resources and never commits a structure on its own; the
## authoritative snapshot (`apply_authoritative_structures`) is the only thing
## that fills the occupancy map.

signal tactical_mode_changed(active: bool)
signal placement_requested(kind: String, cell: Vector2i, world_position: Vector3)
signal placement_rejected(reason: String, cell: Vector2i)

const GRID_STEP := 2.0
const RAY_LENGTH := 2000.0
const KIND_CANNON_TOWER := "cannon_tower"
const KIND_BALLISTA := "ballista"
const KIND_MYTHOS_TRAP := "mythos_trap"
const STRUCTURE_KINDS: Array[String] = [KIND_CANNON_TOWER, KIND_BALLISTA, KIND_MYTHOS_TRAP]

const REJECT_INACTIVE := "TACTICAL_MODE_INACTIVE"
const REJECT_UNKNOWN_KIND := "UNKNOWN_STRUCTURE_KIND"
const REJECT_NO_TERRAIN := "NO_TERRAIN_HIT"
const REJECT_OCCUPIED := "CELL_OCCUPIED"
const REJECT_PENDING := "CELL_PENDING"
const REJECT_OUT_OF_BOUNDS := "OUT_OF_BOUNDS"

## Terrain collision layer the placement ray tests against.
@export_flags_3d_physics var terrain_collision_mask: int = 1
## Height of the fallback terrain plane when no collider is hit.
@export var terrain_plane_height: float = 0.0
## Use the analytic plane when the physics ray misses (flat island preview, tests).
@export var use_plane_fallback: bool = true
## Half-extent of the placeable area in grid cells (0 = unbounded).
@export var max_cell_radius: int = 64
## Top-down camera height while tactical mode is active.
@export var overlay_camera_height: float = 60.0

var active := false
var selected_kind: String = KIND_CANNON_TOWER

## cell -> kind, from the server only.
var _occupied: Dictionary = {}
## cell -> kind, sent but not yet confirmed by the server.
var _pending: Dictionary = {}

var _camera: Camera3D
var _preview: MeshInstance3D
var _grid_overlay: MeshInstance3D
var _preview_ok_material: StandardMaterial3D
var _preview_bad_material: StandardMaterial3D


func _ready() -> void:
	_build_overlay_camera()
	_build_preview()
	_build_grid_overlay()
	_apply_active(false)


# ---------------------------------------------------------------------------
# Grid math (static so tests and the server-mirror tooling can share it)
# ---------------------------------------------------------------------------

## Nearest 2.0 m grid cell for a world XZ position. Rounds half away from zero
## so +1.0 and -1.0 land in symmetric cells.
static func world_to_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(_round_half_away(world_position.x / GRID_STEP), _round_half_away(world_position.z / GRID_STEP))


## World-space centre of a grid cell at the given plane height.
static func cell_to_world(cell: Vector2i, height: float = 0.0) -> Vector3:
	return Vector3(float(cell.x) * GRID_STEP, height, float(cell.y) * GRID_STEP)


## Snap a world position onto the 2.0 m grid (Y is preserved).
static func snap_to_grid(world_position: Vector3) -> Vector3:
	var cell := world_to_cell(world_position)
	return Vector3(float(cell.x) * GRID_STEP, world_position.y, float(cell.y) * GRID_STEP)


static func _round_half_away(value: float) -> int:
	return int(signf(value) * floorf(absf(value) + 0.5))


# ---------------------------------------------------------------------------
# Mode / selection
# ---------------------------------------------------------------------------

func set_tactical_mode(enabled: bool) -> void:
	if enabled == active:
		return
	_apply_active(enabled)
	tactical_mode_changed.emit(active)


func select_structure(kind: String) -> bool:
	if not STRUCTURE_KINDS.has(kind):
		return false
	selected_kind = kind
	return true


func is_cell_occupied(cell: Vector2i) -> bool:
	return _occupied.has(cell)


func is_cell_pending(cell: Vector2i) -> bool:
	return _pending.has(cell)


func occupied_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in _occupied.keys():
		out.append(cell)
	return out


# ---------------------------------------------------------------------------
# Raycast target selection
# ---------------------------------------------------------------------------

## Ray from a screen point through `camera` onto the terrain. Returns
## {"hit": bool, "position": Vector3}. Physics colliders on `terrain_collision_mask`
## win; otherwise the analytic plane y = terrain_plane_height is used.
func raycast_terrain(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	if camera == null:
		return {"hit": false, "position": Vector3.ZERO}
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	return raycast_terrain_from(origin, direction)


func raycast_terrain_from(origin: Vector3, direction: Vector3) -> Dictionary:
	if direction.length_squared() < 0.000001:
		return {"hit": false, "position": Vector3.ZERO}
	var dir := direction.normalized()
	if is_inside_tree():
		var world := get_world_3d()
		if world != null and world.direct_space_state != null:
			var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * RAY_LENGTH, terrain_collision_mask)
			query.collide_with_areas = false
			var hit := world.direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				return {"hit": true, "position": hit["position"]}
	if use_plane_fallback:
		var plane := Plane(Vector3.UP, terrain_plane_height)
		var point = plane.intersects_ray(origin, dir)
		if point != null:
			return {"hit": true, "position": point}
	return {"hit": false, "position": Vector3.ZERO}


# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

## Validate a placement at a world point and, if legal locally, emit the intent.
## Returns the rejection reason, or "" when an intent was emitted.
func request_placement_at_world(world_position: Vector3, kind: String = "") -> String:
	var structure := selected_kind if kind.is_empty() else kind
	var cell := world_to_cell(world_position)
	var reason := validate_placement(cell, structure)
	if not reason.is_empty():
		placement_rejected.emit(reason, cell)
		return reason
	_pending[cell] = structure
	placement_requested.emit(structure, cell, cell_to_world(cell, world_position.y))
	_update_preview(cell, world_position.y)
	return ""


## Raycast from a screen point and request placement on the hit cell.
func request_placement_at_screen(camera: Camera3D, screen_position: Vector2, kind: String = "") -> String:
	if not active:
		placement_rejected.emit(REJECT_INACTIVE, Vector2i.ZERO)
		return REJECT_INACTIVE
	var hit := raycast_terrain(camera, screen_position)
	if not bool(hit["hit"]):
		placement_rejected.emit(REJECT_NO_TERRAIN, Vector2i.ZERO)
		return REJECT_NO_TERRAIN
	return request_placement_at_world(hit["position"], kind)


func validate_placement(cell: Vector2i, kind: String) -> String:
	if not active:
		return REJECT_INACTIVE
	if not STRUCTURE_KINDS.has(kind):
		return REJECT_UNKNOWN_KIND
	if max_cell_radius > 0 and (absi(cell.x) > max_cell_radius or absi(cell.y) > max_cell_radius):
		return REJECT_OUT_OF_BOUNDS
	if _occupied.has(cell):
		return REJECT_OCCUPIED
	if _pending.has(cell):
		return REJECT_PENDING
	return ""


## Replace local occupancy with the server's structure list.
## Each entry: {"kind": String, "cell": [x, z]} or {"kind", "x", "z"} in metres.
func apply_authoritative_structures(structures: Array) -> void:
	_occupied.clear()
	for entry in structures:
		if not (entry is Dictionary):
			continue
		var kind := str(entry.get("kind", ""))
		if not STRUCTURE_KINDS.has(kind):
			continue
		var cell: Vector2i
		if entry.has("cell") and entry["cell"] is Array and (entry["cell"] as Array).size() == 2:
			cell = Vector2i(int(entry["cell"][0]), int(entry["cell"][1]))
		elif entry.has("x") and entry.has("z"):
			cell = world_to_cell(Vector3(float(entry["x"]), 0.0, float(entry["z"])))
		else:
			continue
		_occupied[cell] = kind
		_pending.erase(cell)


## The server refused or timed out a pending placement; free the cell.
func clear_pending(cell: Vector2i) -> void:
	_pending.erase(cell)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var screen := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		screen = event.position
		pressed = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		screen = event.position
		pressed = true
	elif event is InputEventMouseMotion:
		var hover := raycast_terrain(_active_camera(), event.position)
		if bool(hover["hit"]):
			_update_preview(world_to_cell(hover["position"]), (hover["position"] as Vector3).y)
		return
	if pressed:
		request_placement_at_screen(_active_camera(), screen)
		get_viewport().set_input_as_handled()


func _active_camera() -> Camera3D:
	if _camera != null and _camera.current:
		return _camera
	return get_viewport().get_camera_3d() if is_inside_tree() else null


# ---------------------------------------------------------------------------
# Visuals (primitive fallbacks; no asset dependency)
# ---------------------------------------------------------------------------

func _apply_active(enabled: bool) -> void:
	active = enabled
	if _camera != null:
		_camera.current = enabled
	if _grid_overlay != null:
		_grid_overlay.visible = enabled
	if _preview != null:
		_preview.visible = false


func _build_overlay_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "TacticalCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = float(max_cell_radius) * GRID_STEP * 0.5 if max_cell_radius > 0 else 64.0
	_camera.position = Vector3(0.0, overlay_camera_height, 0.0)
	_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_camera.current = false
	add_child(_camera)


func _build_preview() -> void:
	_preview_ok_material = StandardMaterial3D.new()
	_preview_ok_material.albedo_color = Color(0.25, 0.85, 0.4, 0.55)
	_preview_ok_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_ok_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_bad_material = _preview_ok_material.duplicate()
	_preview_bad_material.albedo_color = Color(0.9, 0.2, 0.2, 0.55)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(GRID_STEP * 0.9, 0.4, GRID_STEP * 0.9)
	_preview = MeshInstance3D.new()
	_preview.name = "PlacementPreview"
	_preview.mesh = mesh
	_preview.material_override = _preview_ok_material
	_preview.visible = false
	add_child(_preview)


func _build_grid_overlay() -> void:
	var radius := max_cell_radius if max_cell_radius > 0 else 32
	var extent := (float(radius) + 0.5) * GRID_STEP
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-radius, radius + 2):
		var t := (float(i) - 0.5) * GRID_STEP
		im.surface_add_vertex(Vector3(t, 0.02, -extent))
		im.surface_add_vertex(Vector3(t, 0.02, extent))
		im.surface_add_vertex(Vector3(-extent, 0.02, t))
		im.surface_add_vertex(Vector3(extent, 0.02, t))
	im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.85, 0.5, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grid_overlay = MeshInstance3D.new()
	_grid_overlay.name = "GridOverlay"
	_grid_overlay.mesh = im
	_grid_overlay.material_override = mat
	_grid_overlay.position.y = terrain_plane_height
	_grid_overlay.visible = false
	add_child(_grid_overlay)


func _update_preview(cell: Vector2i, height: float) -> void:
	if _preview == null:
		return
	_preview.visible = active
	_preview.position = cell_to_world(cell, height + 0.2)
	var legal := validate_placement(cell, selected_kind).is_empty()
	_preview.material_override = _preview_ok_material if legal else _preview_bad_material
