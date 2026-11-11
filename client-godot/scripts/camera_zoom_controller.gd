extends Camera3D
## PROMPT_007: client-only camera. Gameplay positions remain server-authoritative.
signal camera_mode_changed(is_top_down: bool)

@export var focus_point: Vector3 = Vector3.ZERO
@export_range(1.0, 100.0) var smoothing: float = 10.0
@export_range(0.001, 0.2) var zoom_sensitivity: float = 0.015
@export_range(0.001, 1.0) var pan_sensitivity: float = 0.025
@export_range(0.1, 10.0) var collision_clearance: float = 0.5
@export_flags_3d_physics var terrain_collision_mask: int = 1

const NEAR_DISTANCE: float = 10.0
const FAR_DISTANCE: float = 120.0
const NEAR_PITCH: float = -45.0
const FAR_PITCH: float = -85.0
const MODE_THRESHOLD: float = 0.5

var _zoom_fraction: float = 0.0
var _rendered_distance: float = NEAR_DISTANCE
var _rendered_pitch: float = NEAR_PITCH
var _touches: Dictionary = {}
var _top_down: bool = false


func _ready() -> void:
	top_level = true
	_apply_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		var old_positions: Dictionary = _touches.duplicate()
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var indices: Array = _touches.keys()
			indices.sort()
			var first: int = indices[0]
			var second: int = indices[1]
			var old_distance: float = (old_positions[first] as Vector2).distance_to(old_positions[second] as Vector2)
			var new_distance: float = (_touches[first] as Vector2).distance_to(_touches[second] as Vector2)
			_set_zoom(_zoom_fraction - (new_distance - old_distance) * zoom_sensitivity)
			var old_midpoint: Vector2 = ((old_positions[first] as Vector2) + (old_positions[second] as Vector2)) * 0.5
			var new_midpoint: Vector2 = ((_touches[first] as Vector2) + (_touches[second] as Vector2)) * 0.5
			_pan(new_midpoint - old_midpoint)
		else:
			_pan(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom_fraction - 0.06)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom_fraction + 0.06)


func _physics_process(delta: float) -> void:
	var weight: float = clampf(1.0 - exp(-smoothing * maxf(delta, 0.0)), 0.0, 1.0)
	_rendered_distance = lerpf(_rendered_distance, lerpf(NEAR_DISTANCE, FAR_DISTANCE, _zoom_fraction), weight)
	_rendered_pitch = lerpf(_rendered_pitch, lerpf(NEAR_PITCH, FAR_PITCH, _zoom_fraction), weight)
	_apply_camera_transform()


func _set_zoom(value: float) -> void:
	_zoom_fraction = clampf(value, 0.0, 1.0)
	var next_mode: bool = _zoom_fraction >= MODE_THRESHOLD
	if next_mode != _top_down:
		_top_down = next_mode
		camera_mode_changed.emit(_top_down)


func _pan(motion: Vector2) -> void:
	var scale_factor: float = pan_sensitivity * _rendered_distance
	var yaw: float = rotation.y
	var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	focus_point += (-right * motion.x + forward * motion.y) * scale_factor


func _apply_camera_transform() -> void:
	rotation.x = deg_to_rad(_rendered_pitch)
	var pitch_radians: float = deg_to_rad(-_rendered_pitch)
	var offset: Vector3 = Vector3(0.0, sin(pitch_radians), cos(pitch_radians)) * _rendered_distance
	offset = offset.rotated(Vector3.UP, rotation.y)
	var desired: Vector3 = focus_point + offset
	if is_inside_tree() and terrain_collision_mask != 0:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(focus_point, desired, terrain_collision_mask)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var hit_distance: float = focus_point.distance_to(hit["position"])
			desired = focus_point + offset.normalized() * maxf(0.1, hit_distance - collision_clearance)
	global_position = desired
