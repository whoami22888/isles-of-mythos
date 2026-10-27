extends Node3D
## Lightweight visual-only distance LOD controller.
## Attach to a parent with high and low MeshInstance3D children.
@export var high_detail_path: NodePath
@export var low_detail_path: NodePath
@export var camera_path: NodePath
@export_range(5.0, 500.0, 1.0) var switch_distance := 45.0
@export_range(0.0, 30.0, 0.5) var hysteresis := 5.0
var _high: MeshInstance3D
var _low: MeshInstance3D
var _camera: Camera3D
var _is_high := true

func _ready() -> void:
    _high = get_node_or_null(high_detail_path) as MeshInstance3D
    _low = get_node_or_null(low_detail_path) as MeshInstance3D
    _camera = get_node_or_null(camera_path) as Camera3D
    set_process(_high != null and _low != null and _camera != null)

func _process(_delta: float) -> void:
    var distance := global_position.distance_to(_camera.global_position)
    _is_high = next_detail_state(_is_high, distance, switch_distance, hysteresis)
    _high.visible = _is_high
    _low.visible = not _is_high


## Pure switching logic, extracted for deterministic testing without a
## scene tree. `hysteresis` can be configured up to switch_distance's own
## range, so the low-detail-to-high-detail return threshold
## (switch_distance - hysteresis) is clamped to zero: a raw negative
## threshold can never be reached by a nonnegative distance, which would
## permanently strand the controller in low detail once it switched away
## (e.g. switch_distance=10, hysteresis=15 -> raw threshold -5).
static func next_detail_state(
    is_high: bool, distance: float, switch_distance: float, hysteresis: float
) -> bool:
    if is_high and distance > switch_distance + hysteresis:
        return false
    if is_high:
        return true
    # <=, not <: when hysteresis clamps the threshold to exactly 0.0, a
    # strict "<" can never be satisfied by a nonnegative distance even
    # when the camera returns to distance 0.0 exactly, which would still
    # permanently strand the controller in low detail.
    var return_threshold := maxf(0.0, switch_distance - hysteresis)
    return distance <= return_threshold
