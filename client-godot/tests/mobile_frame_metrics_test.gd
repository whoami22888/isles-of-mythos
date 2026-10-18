extends SceneTree
## Deterministic percentile unit checks. These are NOT device performance results.

const Stats = preload("res://scripts/mobile_frame_metrics.gd")
var _failures := 0

func _check(ok: bool, name: String) -> void:
	if not ok:
		push_error(name)
		_failures += 1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var sample: Array[float] = [40.0, 10.0, 30.0, 20.0]
	var report: Dictionary = Stats.summarize_frame_intervals(sample)
	_check(report.get("valid", false), "Samples must be accepted")
	_check(report.get("samples", -1) == 4, "Sample count must be exact")
	_check(absf(float(report.get("p50_ms", -1.0)) - 20.0) < 0.001, "Nearest-rank p50 must be 20ms")
	_check(absf(float(report.get("p95_ms", -1.0)) - 40.0) < 0.001, "Nearest-rank p95 must be 40ms")
	_check(absf(float(report.get("p99_ms", -1.0)) - 40.0) < 0.001, "Nearest-rank p99 must be 40ms")
	_check(absf(float(report.get("average_ms", -1.0)) - 25.0) < 0.001, "Average must be arithmetic mean")
	_check(report.get("max_ms", -1.0) == 40.0, "Worst frame must be retained")
	_check(not Stats.summarize_frame_intervals([]).get("valid", true), "Empty sample set must fail closed")
	var invalid: Array[float] = [16.0, -1.0]
	_check(not Stats.summarize_frame_intervals(invalid).get("valid", true), "Negative interval must fail closed")
	var invalid_inf: Array[float] = [16.0, INF]
	_check(not Stats.summarize_frame_intervals(invalid_inf).get("valid", true), "Non-finite interval must fail closed")
	var monotonic: Array[float] = [16.0, 16.0, 16.0, 40.0, 40.0, 40.0, 40.0, 40.0, 40.0, 40.0]
	var summary: Dictionary = Stats.summarize_frame_intervals(monotonic)
	_check(summary.get("p50_ms", -1.0) == 40.0, "Long-frame sample p50 must not be smoothed away")
	_check(summary.get("p95_ms", -1.0) == 40.0, "Long-frame sample p95 must remain visible")
	print("Mobile frame summary tests: %s failure(s)" % _failures)
	quit(1 if _failures else 0)
