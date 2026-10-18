extends SceneTree
## Actual Godot-engine frame sampling on the running CI renderer.
## Linux/Xvfb GL results are NOT Android FPS, GPU timing, thermals or art approval.
const Stats = preload("res://scripts/mobile_frame_metrics.gd")
const WARMUP_FRAMES := 24
const SAMPLE_FRAMES := 180

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene_source: PackedScene = load("res://scenes/sculpted_terrain_preview.tscn")
	if scene_source == null:
		_fail("Could not load sculpted terrain profiling scene")
		return
	var scene: Node3D = scene_source.instantiate()
	root.add_child(scene)
	var camera: Camera3D = scene.get_node_or_null("IslandCamera")
	if camera == null or not camera.current:
		_fail("No active Godot camera; refusing empty synthetic profile")
		return
	for i in range(WARMUP_FRAMES):
		await process_frame
	var intervals_ms: Array[float] = []
	var process_ms: Array[float] = []
	var peak_draw_calls := 0
	var previous_us := Time.get_ticks_usec()
	for i in range(SAMPLE_FRAMES):
		await process_frame
		var now_us := Time.get_ticks_usec()
		var elapsed_ms := float(now_us - previous_us) / 1000.0
		previous_us = now_us
		if elapsed_ms <= 0.0:
			_fail("Non-monotonic Godot frame clock")
			return
		intervals_ms.append(elapsed_ms)
		var process_time_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		if not is_finite(process_time_ms) or process_time_ms <= 0.0:
			_fail("Invalid engine process time sample")
			return
		process_ms.append(process_time_ms)
		peak_draw_calls = maxi(peak_draw_calls, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var frames_summary: Dictionary = Stats.summarize_frame_intervals(intervals_ms)
	var process_summary: Dictionary = Stats.summarize_frame_intervals(process_ms)
	if not frames_summary.get("valid", false) or not process_summary.get("valid", false) or frames_summary.get("samples", 0) != SAMPLE_FRAMES:
		_fail("Missing or malformed actual Godot frame samples")
		return
	var output := OS.get_environment("IOM_MOBILE_PROFILE_PATH")
	if output.is_empty():
		output = "user://mobile-frame-evidence.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write Godot performance evidence artifact")
		return
	var report := {
		"schema_version": 1,
		"source": "actual_godot_scene",
		"scene": "res://scenes/sculpted_terrain_preview.tscn",
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"commit_sha": OS.get_environment("IOM_GIT_SHA"),
		"capture_environment": "github_actions_linux_xvfb",
		"renderer": "gl_compatibility",
		"physical_android_measurement": false,
		"warmup_frames": WARMUP_FRAMES,
		"frame_interval_ms": frames_summary,
		"engine_process_ms": process_summary,
		"engine_process_clock_check": Stats.compare_clock_summaries(frames_summary, process_summary),
		"peak_3d_draw_calls": peak_draw_calls,
		"graphics_quality_verdict": "NOT_VERIFIED",
		"mobile_acceptance_verdict": "NOT_VERIFIED",
	}
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	file.close()
	print("IOM-07 actual Godot frame evidence saved: %s" % output)
	scene.queue_free()
	quit(0)
