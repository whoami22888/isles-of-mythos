extends Node3D
## Visual-only distance LOD controller; never changes authoritative gameplay state.
## Attach to a parent with high/low MeshInstance3D children and a Camera3D.
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

    if _high == null or _low == null or _high == _low:
        push_warning("Mobile LOD: high/low mesh paths must resolve to distinct MeshInstance3D nodes.")
        # Deterministic single-mesh fallback; never leave two meshes visible.
        if _high != null:
            _high.visible = true
        if _low != null and _low != _high:
            _low.visible = (_high == null)
        set_process(false)
        return

    if _camera == null:
        push_warning("Mobile LOD: camera path must resolve to Camera3D; using high detail.")
        _apply_detail(true)
        set_process(false)
        return

    # Apply before the first rendered frame, not only in the first _process.
    _update_detail()
    set_process(true)


func _process(_delta: float) -> void:
    if not is_instance_valid(_high) or not is_instance_valid(_low):
        # The remaining valid mesh is the only one that may render.
        if is_instance_valid(_high):
            _high.visible = true
        if is_instance_valid(_low):
            _low.visible = true
        set_process(false)
        return
    if not is_instance_valid(_camera):
        push_warning("Mobile LOD: camera disappeared; using high detail.")
        _apply_detail(true)
        set_process(false)
        return
    _update_detail()


func _update_detail() -> void:
    var distance := global_position.distance_to(_camera.global_position)
    _apply_detail(next_detail_state(_is_high, distance, switch_distance, hysteresis))


func _apply_detail(high_detail: bool) -> void:
    _is_high = high_detail
    _high.visible = high_detail
    _low.visible = not high_detail


## The exported hysteresis range can exceed a small switch_distance.
## Clamp the *effective* band to half the positive switch distance so that
## low->high recovery remains possible at ordinary positive near distances.
## Normal configurations (e.g. 45/5) retain their existing thresholds.
static func next_detail_state(
    is_high: bool, distance: float, switch_distance: float, hysteresis: float
) -> bool:
    var pivot := maxf(0.001, switch_distance)
    var band := clampf(hysteresis, 0.0, pivot * 0.5)
    if is_high:
        return distance <= pivot + band
    return distance <= pivot - band
