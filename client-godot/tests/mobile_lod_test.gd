extends SceneTree
## Deterministic enter/exit and invalid-boundary regression for the pure
## switching logic in scripts/mobile_lod.gd. No scene/camera required:
## MobileLod.next_detail_state is a static pure function.

const MobileLod := preload("res://scripts/mobile_lod.gd")


func _init() -> void:
    var failures := 0

    # Normal enter/exit with a healthy hysteresis band (switch=45, hyst=5):
    # exits high detail only past 50, re-enters only once back under 40.
    var high := true
    high = MobileLod.next_detail_state(high, 10.0, 45.0, 5.0)
    if high != true:
        failures += 1
        push_error("Must stay high detail well within switch_distance")
    high = MobileLod.next_detail_state(high, 60.0, 45.0, 5.0)
    if high != false:
        failures += 1
        push_error("Must switch to low detail past switch_distance + hysteresis")
    high = MobileLod.next_detail_state(high, 42.0, 45.0, 5.0)
    if high != false:
        failures += 1
        push_error("Must stay low detail inside the hysteresis band")
    high = MobileLod.next_detail_state(high, 35.0, 45.0, 5.0)
    if high != true:
        failures += 1
        push_error("Must re-enter high detail once under switch_distance - hysteresis")

    # Invalid-boundary case from the reported defect: hysteresis >=
    # switch_distance (switch=10, hysteresis=15) must still let the
    # controller recover high detail when the camera returns to 0.0,
    # instead of permanently stranding it in low detail.
    var stranded := false
    stranded = MobileLod.next_detail_state(stranded, 30.0, 10.0, 15.0)
    if stranded != false:
        failures += 1
        push_error(
            "Must switch to low detail past switch_distance + hysteresis "
            + "even when hysteresis >= switch_distance"
        )
    stranded = MobileLod.next_detail_state(stranded, 0.0, 10.0, 15.0)
    if stranded != true:
        failures += 1
        push_error(
            "Camera returning to distance 0.0 must restore high detail "
            + "even when hysteresis >= switch_distance (regression for the "
            + "unreachable negative-threshold defect)"
        )

    # Zero hysteresis is a degenerate but legal configuration; the
    # boundary itself must be reachable in both directions.
    var zero_band := true
    zero_band = MobileLod.next_detail_state(zero_band, 20.0, 20.0, 0.0)
    if zero_band != true:
        failures += 1
        push_error("Exactly at switch_distance with zero hysteresis must not switch away")
    zero_band = MobileLod.next_detail_state(zero_band, 20.01, 20.0, 0.0)
    if zero_band != false:
        failures += 1
        push_error("Just past switch_distance with zero hysteresis must switch to low detail")
    zero_band = MobileLod.next_detail_state(zero_band, 20.0, 20.0, 0.0)
    if zero_band != true:
        failures += 1
        push_error(
            "Returning to exactly switch_distance with zero hysteresis "
            + "must restore high detail"
        )

    print("Mobile LOD enter/exit and invalid-boundary regression: %d failures" % failures)
    quit(1 if failures else 0)
