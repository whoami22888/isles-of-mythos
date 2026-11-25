extends Node3D
class_name LodImpostorManager

## Attach to an entity Node3D. mesh_path must identify the entity's full-detail
## MeshInstance3D; use its custom_aabb when the rig contains multiple surfaces.
## The Sprite3D texture is a pre-rendered, row-major octahedral view atlas.
## Row zero represents the top of octahedral UV space.
##
## Visual-only: this controller never changes server-authoritative state.
## The hot path creates no temporary Arrays, Dictionaries, Nodes or Resources.

const HIGH_DETAIL_ENTER_PX: float = 140.0
const IMPOSTOR_ENTER_PX: float = 120.0
const AABB_EPSILON_SQUARED: float = 0.000001

@export var mesh_path: NodePath
@export var impostor_path: NodePath
## Optional explicit camera. When empty, the active viewport Camera3D is used.
@export var camera_path: NodePath
@export_range(2, 64, 1) var atlas_columns: int = 8
@export_range(2, 64, 1) var atlas_rows: int = 8

var _mesh: MeshInstance3D
var _impostor: Sprite3D
var _camera: Camera3D
var _local_bounds: AABB
var _valid: bool = false
var _show_full_detail: bool = true
var _last_frame: int = -1

# Reused scalar scratch state; no per-frame collection construction.
var _screen_min_y: float = 0.0
var _screen_max_y: float = 0.0
var _projected_corners: int = 0
var _behind_corners: int = 0


func _ready() -> void:
	_mesh = get_node_or_null(mesh_path) as MeshInstance3D
	_impostor = get_node_or_null(impostor_path) as Sprite3D

	# Hide any pre-visible impostor before validating the high-detail source.
	# An invalid mesh path must never leave a sprite masquerading as a safe fallback.
	if is_instance_valid(_impostor):
		_impostor.visible = false

	if not is_instance_valid(_mesh):
		push_warning("LodImpostorManager: mesh_path must resolve to a MeshInstance3D.")
		set_process(false)
		return

	_mesh.visible = true

	if not is_instance_valid(_impostor):
		_fail_safe()
		set_process(false)
		return

	if _mesh.mesh == null or not _has_valid_atlas():
		_fail_safe()
		set_process(false)
		return

	_local_bounds = _mesh.custom_aabb
	if _local_bounds.size.length_squared() <= AABB_EPSILON_SQUARED:
		_local_bounds = _mesh.get_aabb()
	if _local_bounds.size.length_squared() <= AABB_EPSILON_SQUARED:
		_fail_safe()
		set_process(false)
		return

	_impostor.hframes = atlas_columns
	_impostor.vframes = atlas_rows
	_impostor.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_impostor.centered = true
	_impostor.rotation = Vector3.ZERO
	if not _configure_impostor_geometry():
		_fail_safe()
		set_process(false)
		return
	_show_full_detail = true
	_valid = true
	set_process(true)

	# Apply the initial state before the first rendered frame when a camera
	# is already active. If it is not, _process keeps the safe 3D mesh visible
	# and resolves the active camera on the next frame.
	_camera = _resolve_camera()
	if is_instance_valid(_camera):
		_update_lod()
	else:
		_fail_safe()


func _process(_delta: float) -> void:
	if not _valid:
		set_process(false)
		return
	if not is_instance_valid(_mesh) or not is_instance_valid(_impostor):
		_fail_safe()
		set_process(false)
		return

	# The active camera can change during a scene transition. Resolving it
	# returns an existing node reference and creates no temporary collection.
	_camera = _resolve_camera()
	if not is_instance_valid(_camera):
		_fail_safe()
		return

	_update_lod()


func _resolve_camera() -> Camera3D:
	if not camera_path.is_empty():
		return get_node_or_null(camera_path) as Camera3D
	var viewport := get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_3d()


func _update_lod() -> void:
	var pixel_height := _projected_pixel_height()
	var next_full_detail := next_full_detail_state(_show_full_detail, pixel_height)
	if next_full_detail != _show_full_detail:
		_show_full_detail = next_full_detail
		_mesh.visible = _show_full_detail
		_impostor.visible = not _show_full_detail
		_last_frame = -1

	if not _show_full_detail:
		_update_impostor_frame()


func _projected_pixel_height() -> float:
	if not is_instance_valid(_camera):
		return INF
	var viewport := _camera.get_viewport()
	if viewport == null:
		return INF
	var viewport_height := viewport.get_visible_rect().size.y
	if viewport_height <= 0.0:
		return INF

	_screen_min_y = INF
	_screen_max_y = -INF
	_projected_corners = 0
	_behind_corners = 0

	# Project all eight transformed AABB corners. Explicit calls avoid a
	# temporary Array/range allocation in the per-frame path.
	var mesh_transform := _mesh.global_transform
	_accumulate_projected_corner(mesh_transform * _local_bounds.get_endpoint(0))
	_accumulate_projected_corner(mesh_transform * _local_bounds.get_endpoint(1))
	_accumulate_projected_corner(mesh_transform * _local_bounds.get_endpoint(2))
	_accumulate_projected_corner(mesh_transform * _local_bounds.get_endpoint(3))
	_accumulate_projected_corner(mesh_transform * _local_bounds.get_endpoint(4))
	_accumulate_projected_corner(mesh_transform * _local_bounds.get_endpoint(5))
	_accumulate_projected_corner(mesh_transform * _local_bounds.get_endpoint(6))
	_accumulate_projected_corner(mesh_transform * _local_bounds.get_endpoint(7))

	if _behind_corners > 0:
		# A corner behind the camera plane means the bounds straddle it or are
		# entirely behind it. Keep the full mesh; an impostor must not pop into
		# view while the camera crosses or looks away from the entity.
		return INF
	if _projected_corners == 0:
		# Defensive fallback for an incomplete projection; prefer full detail.
		return INF
	return maxf(0.0, _screen_max_y - _screen_min_y)


func _accumulate_projected_corner(world_position: Vector3) -> void:
	if _camera.is_position_behind(world_position):
		_behind_corners += 1
		return

	var screen_position := _camera.unproject_position(world_position)
	_screen_min_y = minf(_screen_min_y, screen_position.y)
	_screen_max_y = maxf(_screen_max_y, screen_position.y)
	_projected_corners += 1


func _update_impostor_frame() -> void:
	var object_basis := _mesh.global_transform.basis.orthonormalized()
	var view_direction := object_basis.inverse() * (_camera.global_position - _mesh.global_position)
	var next_frame := octahedral_frame_index(view_direction, atlas_columns, atlas_rows)
	if next_frame != _last_frame:
		_impostor.frame = next_frame
		_last_frame = next_frame


func _configure_impostor_geometry() -> bool:
	# Sprite3D uses one pixel_size for both axes. Fit its frame to the source
	# mesh bounds so the impostor does not collapse to Sprite3D's 0.01 default
	# or change apparent size when the LOD swap occurs.
	var sprite_parent := _impostor.get_parent() as Node3D
	if sprite_parent == null:
		return false
	var parent_transform := sprite_parent.global_transform
	if absf(parent_transform.basis.determinant()) <= AABB_EPSILON_SQUARED:
		return false

	var frame_width := _impostor.texture.get_width() / atlas_columns
	var frame_height := _impostor.texture.get_height() / atlas_rows
	if frame_width <= 0 or frame_height <= 0:
		return false

	# Transform the mesh AABB into the Sprite3D parent's local space. This
	# preserves offsets and non-uniform mesh scale without per-frame work.
	var mesh_to_sprite_parent := parent_transform.affine_inverse() * _mesh.global_transform
	var bounds_min := Vector3(INF, INF, INF)
	var bounds_max := Vector3(-INF, -INF, -INF)
	for corner_index in range(8):
		var corner := mesh_to_sprite_parent * _local_bounds.get_endpoint(corner_index)
		bounds_min = bounds_min.min(corner)
		bounds_max = bounds_max.max(corner)

	var bounds_size := bounds_max - bounds_min
	var vertical_extent := bounds_size.y
	var horizontal_extent := maxf(bounds_size.x, bounds_size.z)
	if vertical_extent <= AABB_EPSILON_SQUARED or horizontal_extent <= AABB_EPSILON_SQUARED:
		return false

	_impostor.position = (bounds_min + bounds_max) * 0.5
	_impostor.pixel_size = vertical_extent / float(frame_height)
	_impostor.scale = Vector3(
		horizontal_extent * float(frame_height) / (vertical_extent * float(frame_width)),
		1.0,
		1.0
	)
	return true


func _has_valid_atlas() -> bool:
	if _impostor.texture == null or atlas_columns < 2 or atlas_rows < 2:
		return false
	var texture_width := _impostor.texture.get_width()
	var texture_height := _impostor.texture.get_height()
	return (
		texture_width >= atlas_columns
		and texture_height >= atlas_rows
		and texture_width % atlas_columns == 0
		and texture_height % atlas_rows == 0
	)


func _fail_safe() -> void:
	if is_instance_valid(_mesh):
		_mesh.visible = true
	if is_instance_valid(_impostor):
		_impostor.visible = false
	_show_full_detail = true
	_last_frame = -1


## The 20 px buffer is 15.38% of the 130 px midpoint.
## Strict comparisons preserve the inclusive 120–140 px hold band.
static func next_full_detail_state(current_full_detail: bool, pixel_height: float) -> bool:
	if pixel_height > HIGH_DETAIL_ENTER_PX:
		return true
	if pixel_height < IMPOSTOR_ENTER_PX:
		return false
	return current_full_detail


static func octahedral_uv(direction: Vector3) -> Vector2:
	var denominator := absf(direction.x) + absf(direction.y) + absf(direction.z)
	if denominator <= AABB_EPSILON_SQUARED:
		return Vector2(0.5, 0.5)

	var projected := direction / denominator
	if projected.z < 0.0:
		var old_x := projected.x
		var old_y := projected.y
		projected.x = (1.0 - absf(old_y)) * (1.0 if old_x >= 0.0 else -1.0)
		projected.y = (1.0 - absf(old_x)) * (1.0 if old_y >= 0.0 else -1.0)

	return Vector2(
		clampf(projected.x * 0.5 + 0.5, 0.0, 1.0),
		clampf(projected.y * 0.5 + 0.5, 0.0, 1.0)
	)


## Row-major frame order; row zero corresponds to octahedral UV y=1 (top).
static func octahedral_frame_index(direction: Vector3, columns: int, rows: int) -> int:
	var safe_columns := maxi(1, columns)
	var safe_rows := maxi(1, rows)
	var uv := octahedral_uv(direction)
	var column := clampi(floori(uv.x * float(safe_columns)), 0, safe_columns - 1)
	var row := clampi(floori((1.0 - uv.y) * float(safe_rows)), 0, safe_rows - 1)
	return row * safe_columns + column
