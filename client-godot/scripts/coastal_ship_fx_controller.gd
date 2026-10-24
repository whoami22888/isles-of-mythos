extends Node3D
## Stacked coastal visual integration; *never* writes network or server game state.
## Active only in realistic_coastal_fx_slice.tscn; the original coastal scene
## remains unchanged. A demo navigation path runs only during its cinematic.

const WAKE_SCRIPT = preload("res://scripts/ship_wake_effect.gd")
const BOW_SCRIPT = preload("res://scripts/ship_bow_spray_effect.gd")

@export_range(0.2, 6.0, 0.1) var cinematic_speed: float = 2.6
@export var demo_course_direction := Vector3(0.0, 0.0, -1.0)

var wake: ShipWakeEffect
var bow_spray: ShipBowSprayEffect
var vessel: Node3D
var _coast: Node3D
var _anchor := Vector3.ZERO
var _elapsed := 0.0
var _demo_active := false
var _ready_for_effects := false


func _ready() -> void:
    call_deferred("_bind_components")


func _bind_components() -> void:
    _coast = get_parent() as Node3D
    if _coast == null:
        push_error("Coastal effects require a parent coastal scene")
        return
    vessel = _coast.get_node_or_null("HarbourShipFocalPoint") as Node3D
    if vessel == null:
        push_error("Coastal effects require the validated PBR ship scene")
        return
    _anchor = vessel.position
    wake = WAKE_SCRIPT.new()
    wake.name = "ShipWake"
    wake.sea_level = -0.35
    add_child(wake)
    wake.attach_vessel(vessel)
    bow_spray = BOW_SCRIPT.new()
    bow_spray.name = "BowContactSpray"
    bow_spray.sea_level = -0.35
    # GLTF vessel axis is provisional; model-local forward and scale require
    # actual ship inspection before premium visual acceptance.
    bow_spray.bow_axis_local = demo_course_direction
    add_child(bow_spray)
    bow_spray.attach_vessel(vessel)
    _ready_for_effects = true


func components_ready() -> bool:
    return _ready_for_effects and is_instance_valid(wake) and is_instance_valid(bow_spray)


func start_visual_demo() -> void:
    if not components_ready() or _demo_active:
        return
    _elapsed = 0.0
    _anchor = vessel.position
    wake.attach_vessel(vessel)
    bow_spray.attach_vessel(vessel)
    _demo_active = true


func stop_visual_demo() -> void:
    if not components_ready():
        return
    _demo_active = false
    vessel.position.x = _anchor.x
    vessel.position.z = _anchor.z
    # Do not let a teleport to start produce a false ship wake/spray.
    wake.attach_vessel(vessel)
    bow_spray.attach_vessel(vessel)


func advance_visual_demo(delta: float) -> void:
    if not _demo_active or not components_ready() or not is_finite(delta) or delta <= 0.0:
        return
    _elapsed += minf(delta, 0.25)
    var horizontal_direction := Vector3(demo_course_direction.x, 0.0, demo_course_direction.z)
    if horizontal_direction.length_squared() <= 0.0001:
        return
    horizontal_direction = horizontal_direction.normalized()
    var travel := minf(_elapsed * cinematic_speed, 11.0)
    var target := _anchor + horizontal_direction * travel
    vessel.position.x = target.x
    vessel.position.z = target.z
    # Force deterministic VFX updates after the demo vessel has moved.
    # Children are set to explicit-step mode during the cinematic only.
    wake.advance_wake(delta)
    bow_spray.advance_contact(delta)


func _process(delta: float) -> void:
    if not components_ready():
        return
    # The cinematic is an opt-in visual showcase, not authoritative ship
    # navigation. The base gameplay scene is unchanged.
    var cinematic_playing := bool(_coast.get("_cinematic_active"))
    if cinematic_playing and not _demo_active:
        start_visual_demo()
        wake.set_process(false)
        bow_spray.set_process(false)
    elif not cinematic_playing and _demo_active:
        stop_visual_demo()
        wake.set_process(true)
        bow_spray.set_process(true)
    if _demo_active:
        advance_visual_demo(delta)


func _exit_tree() -> void:
    if is_instance_valid(wake):
        wake.clear_wake()
    if is_instance_valid(bow_spray):
        bow_spray.attach_vessel(null)
