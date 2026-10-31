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
    if _is_high and distance > switch_distance + hysteresis:
        _is_high = false
    elif not _is_high and distance < switch_distance - hysteresis:
        _is_high = true
    _high.visible = _is_high
    _low.visible = not _is_high
