extends Node
class_name MobilePerformanceAdapter

## Runtime-only 3D resolution controller for the root viewport.
## UI remains at native canvas resolution: only Viewport.scaling_3d_scale changes.
## Frame intervals come from _process(delta), giving one consistent rolling clock.
## Performance.TIME_FPS and TIME_PROCESS are retained as diagnostics; TIME_PROCESS
## is not used for control because the existing IOM07 evidence records clock divergence.

const WINDOW_USEC: int = 2_000_000
const SAMPLE_CAPACITY: int = 512 # Covers 2 s at up to 256 FPS.
const EVALUATION_INTERVAL_SECONDS: float = 0.5
const MAX_SUSPEND_DELTA_SECONDS: float = 1.0

const MIN_SCALE: float = 0.70
const MAX_SCALE: float = 1.0
const SCALE_DOWN_STEP: float = 0.05
const SCALE_UP_STEP: float = 0.02

const LOW_FPS_THRESHOLD: float = 48.0
const STABLE_FPS_THRESHOLD: float = 58.5
const FRAME_TIME_THRESHOLD_MS: float = 20.0
const STABLE_RESTORE_SECONDS: float = 10.0
const RESTORE_STEP_INTERVAL_SECONDS: float = 1.0


var monitoring_enabled: bool = true

var _viewport: Viewport
var _sample_timestamps_usec := PackedInt64Array()
var _sample_frame_ms := PackedFloat32Array()
var _sample_engine_fps := PackedFloat32Array()
var _sample_engine_process_ms := PackedFloat32Array()
var _write_index: int = 0
var _sample_count: int = 0
var _evaluation_elapsed: float = 0.0
var _stable_seconds: float = 0.0
var _current_scale: float = 1.0

var _last_rolling_fps: float = 0.0
var _last_average_frame_ms: float = 0.0
var _last_engine_fps: float = 0.0
var _last_engine_process_ms: float = 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		monitoring_enabled = false
		set_process(false)
		return

	_viewport = get_viewport()
	if _viewport == null:
		monitoring_enabled = false
		set_process(false)
		return

	# Allocate the fixed ring buffer once, not from _process().
	_sample_timestamps_usec.resize(SAMPLE_CAPACITY)
	_sample_frame_ms.resize(SAMPLE_CAPACITY)
	_sample_engine_fps.resize(SAMPLE_CAPACITY)
	_sample_engine_process_ms.resize(SAMPLE_CAPACITY)

	_current_scale = clampf(_viewport.scaling_3d_scale, MIN_SCALE, MAX_SCALE)
	if not is_equal_approx(_viewport.scaling_3d_scale, _current_scale):
		_viewport.scaling_3d_scale = _current_scale
	set_process(true)


func _process(delta: float) -> void:
	if not monitoring_enabled or _viewport == null:
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	if delta > MAX_SUSPEND_DELTA_SECONDS:
		# App suspension/resume is not a GPU performance sample.
		_clear_window()
		_evaluation_elapsed = 0.0
		_stable_seconds = 0.0
		return

	var now_usec := Time.get_ticks_usec()
	var engine_fps_sample := float(Performance.get_monitor(Performance.TIME_FPS))
	var process_seconds_sample := float(Performance.get_monitor(Performance.TIME_PROCESS))
	var engine_process_ms_sample := process_seconds_sample * 1000.0 if is_finite(process_seconds_sample) and process_seconds_sample >= 0.0 else -1.0
	_record_sample(now_usec, delta * 1000.0, engine_fps_sample, engine_process_ms_sample)
	_evaluation_elapsed += delta
	if _evaluation_elapsed < EVALUATION_INTERVAL_SECONDS:
		return

	var evaluation_elapsed := _evaluation_elapsed
	_evaluation_elapsed = 0.0
	var summary := _summarize_window(now_usec)
	# Do not make a scaling decision until the complete 2-second window exists.
	_apply_window_summary(summary, evaluation_elapsed)


func _apply_window_summary(summary: Vector2, evaluation_elapsed: float) -> bool:
	var samples := int(summary.y)
	if samples <= 0 or not has_full_window_coverage(summary.x):
		return false

	_last_average_frame_ms = summary.x / float(samples)
	if _last_average_frame_ms <= 0.0 or not is_finite(_last_average_frame_ms):
		return false
	_last_rolling_fps = 1000.0 / _last_average_frame_ms

	# Engine monitors are retained as rolling diagnostics. The delta-derived
	# interval clock remains authoritative because IOM07 measured TIME_PROCESS
	# divergence from actual frame intervals on Xvfb.
	apply_metrics_sample(_last_rolling_fps, _last_average_frame_ms, evaluation_elapsed)
	return true


func _record_sample(timestamp_usec: int, frame_ms: float, engine_fps: float, engine_process_ms: float) -> void:
	_sample_timestamps_usec[_write_index] = timestamp_usec
	_sample_frame_ms[_write_index] = frame_ms
	_sample_engine_fps[_write_index] = engine_fps if is_finite(engine_fps) and engine_fps > 0.0 else -1.0
	_sample_engine_process_ms[_write_index] = engine_process_ms
	_write_index = (_write_index + 1) % SAMPLE_CAPACITY
	_sample_count = mini(_sample_count + 1, SAMPLE_CAPACITY)


func _summarize_window(now_usec: int) -> Vector2:
	var cutoff_usec := now_usec - WINDOW_USEC
	var total_ms := 0.0
	var samples := 0
	var engine_fps_total := 0.0
	var engine_fps_samples := 0
	var engine_process_total := 0.0
	var engine_process_samples := 0
	var index := _write_index - 1
	if index < 0:
		index = SAMPLE_CAPACITY - 1

	var visited := 0
	while visited < _sample_count:
		var timestamp := _sample_timestamps_usec[index]
		if timestamp < cutoff_usec:
			break
		total_ms += float(_sample_frame_ms[index])
		samples += 1
		var engine_fps := float(_sample_engine_fps[index])
		if is_finite(engine_fps) and engine_fps > 0.0:
			engine_fps_total += engine_fps
			engine_fps_samples += 1
		var engine_process_ms := float(_sample_engine_process_ms[index])
		if is_finite(engine_process_ms) and engine_process_ms >= 0.0:
			engine_process_total += engine_process_ms
			engine_process_samples += 1
		index -= 1
		if index < 0:
			index = SAMPLE_CAPACITY - 1
		visited += 1

	_last_engine_fps = engine_fps_total / float(engine_fps_samples) if engine_fps_samples > 0 else 0.0
	_last_engine_process_ms = engine_process_total / float(engine_process_samples) if engine_process_samples > 0 else 0.0
	return Vector2(total_ms, float(samples))


func _clear_window() -> void:
	_write_index = 0
	_sample_count = 0


static func has_full_window_coverage(total_frame_ms: float) -> bool:
	return is_finite(total_frame_ms) and total_frame_ms >= (float(WINDOW_USEC) / 1000.0)


## Public injection point used by deterministic tests and diagnostics.
## It applies one already-computed rolling-window sample; production calls it
## only at the bounded evaluation interval above.
func apply_metrics_sample(rolling_fps: float, average_frame_ms: float, elapsed_seconds: float) -> void:
	if _viewport == null:
		_viewport = get_viewport()
	if _viewport == null:
		return

	var next_state := next_policy_state(
		_current_scale,
		rolling_fps,
		average_frame_ms,
		_stable_seconds,
		elapsed_seconds
	)
	_stable_seconds = next_state.y
	_set_scale(next_state.x)


func _set_scale(value: float) -> void:
	var next_scale := clampf(value, MIN_SCALE, MAX_SCALE)
	if is_equal_approx(next_scale, _current_scale):
		return
	_current_scale = next_scale
	if _viewport != null:
		_viewport.scaling_3d_scale = _current_scale
	print("Mobile 3D render scale adjusted to %.2fx" % _current_scale)


func get_metrics_snapshot() -> Dictionary:
	return {
		"rolling_fps": _last_rolling_fps,
		"average_frame_ms": _last_average_frame_ms,
		"engine_fps_monitor": _last_engine_fps,
		"engine_process_ms_monitor": _last_engine_process_ms,
		"scaling_3d_scale": _current_scale,
		"monitoring_enabled": monitoring_enabled,
	}


## Returns Vector2(new_scale, new_stable_seconds).
## Low-FPS / >20 ms samples lower 3D scale by 0.05 to 0.70.
## Restoration requires >=58.5 FPS and a frame budget <=1000/58.5 ms
## for 10 s; subsequent 0.02 steps are spaced one second apart.
static func next_policy_state(
	current_scale: float,
	rolling_fps: float,
	average_frame_ms: float,
	stable_seconds: float,
	elapsed_seconds: float
) -> Vector2:
	var bounded_scale := clampf(current_scale, MIN_SCALE, MAX_SCALE)
	if (
		not is_finite(rolling_fps)
		or not is_finite(average_frame_ms)
		or not is_finite(stable_seconds)
		or not is_finite(elapsed_seconds)
		or average_frame_ms <= 0.0
		or elapsed_seconds < 0.0
	):
		return Vector2(bounded_scale, 0.0)

	if rolling_fps < LOW_FPS_THRESHOLD or average_frame_ms > FRAME_TIME_THRESHOLD_MS:
		return Vector2(maxf(MIN_SCALE, bounded_scale - SCALE_DOWN_STEP), 0.0)

	if rolling_fps >= STABLE_FPS_THRESHOLD and average_frame_ms <= (1000.0 / STABLE_FPS_THRESHOLD):
		var next_stable_seconds := maxf(0.0, stable_seconds) + elapsed_seconds
		if next_stable_seconds >= STABLE_RESTORE_SECONDS:
			return Vector2(minf(MAX_SCALE, bounded_scale + SCALE_UP_STEP), STABLE_RESTORE_SECONDS - RESTORE_STEP_INTERVAL_SECONDS)
		return Vector2(bounded_scale, next_stable_seconds)

	return Vector2(bounded_scale, 0.0)
