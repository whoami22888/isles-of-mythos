extends SceneTree
## IOM-07 moving coastal scene profiler, run on a real Godot Mobile renderer.
## Linux llvmpipe is not physical Android GPU or player-experience acceptance.

const Stats = preload("res://scripts/mobile_frame_metrics.gd")
const SAMPLES := 30
# One fully rendered frame with the fixed benchmark camera is enough to
# establish its material/pipeline state before measurement. Six redundant
# warmup renders cost >15 seconds on CI llvmpipe without changing the scene.
# The 30 static + 30 moving *measured* frames remain mandatory.
const WARMUP := 1
const STEP_SECONDS := 1.0 / 24.0

func _init() -> void:
	call_deferred("_profile")

func _fail(reason: String) -> void:
	push_error("IOM-07 moving coastal profile failed: " + reason)
	quit(1)

func _measure(scene: Node3D, fx: Node3D, moving: bool) -> Dictionary:
	var intervals: Array[float] = []
	var update_costs: Array[float] = []
	var draw_calls := 0
	var previous := Time.get_ticks_usec()
	var phase_name := "moving" if moving else "static"
	print("IOM07_STAGE_BEGIN phase=%s samples=%d" % [phase_name, SAMPLES])
	for sample in range(SAMPLES):
		print("IOM07_FRAME_BEGIN phase=%s sample=%d elapsed_usec=%d" % [phase_name, sample + 1, Time.get_ticks_usec()])
		var before_step := Time.get_ticks_usec()
		if moving:
			fx.advance_visual_demo(STEP_SECONDS)
		var step_ms := float(Time.get_ticks_usec() - before_step) / 1000.0
		update_costs.append(maxf(0.001, step_ms))
		await process_frame
		print("IOM07_PROCESS_FRAME_DONE phase=%s sample=%d" % [phase_name, sample + 1])
		await RenderingServer.frame_post_draw
		print("IOM07_RENDER_FRAME_DONE phase=%s sample=%d" % [phase_name, sample + 1])
		var now := Time.get_ticks_usec()
		var interval := float(now - previous) / 1000.0
		if not is_finite(interval) or interval <= 0.0:
			return {"valid": false, "reason": "INVALID_FRAME_INTERVAL"}
		intervals.append(interval)
		previous = now
		draw_calls = maxi(draw_calls, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		# Save diagnostic-only samples before the 240s runner deadline; never
		# substitute this checkpoint for the required full 30+30 result.
		var profile_path := OS.get_environment("IOM_COAST_PROFILE_PATH")
		if not profile_path.is_empty():
			var partial_path := profile_path.get_base_dir().path_join("INCOMPLETE_NOT_ACCEPTED.json")
			var checkpoint := FileAccess.open(partial_path, FileAccess.WRITE)
			if checkpoint != null:
				checkpoint.store_string(JSON.stringify({
					"status": "INCOMPLETE_DIAGNOSTIC_ONLY",
					"exact_git_sha": OS.get_environment("IOM_GIT_SHA"),
					"godot": Engine.get_version_info().get("string", "unknown"),
					"renderer": "mobile",
					"source_scene": "res://scenes/realistic_coastal_fx_slice.tscn",
					"phase": phase_name,
					"completed_samples_in_phase": intervals.size(),
					"required_samples_each_phase": SAMPLES,
					"frame_interval_ms": intervals,
					"visual_update_cpu_wall_ms": update_costs,
					"peak_draw_calls": draw_calls,
					"physical_android_measurement": false,
					"graphics_reference_parity": "NOT_VERIFIED"
				}))
				checkpoint.close()
	var frames: Dictionary = Stats.summarize_frame_intervals(intervals)
	var update_work: Dictionary = Stats.summarize_frame_intervals(update_costs)
	if not frames.get("valid", false) or not update_work.get("valid", false):
		return {"valid": false, "reason": "INVALID_STAGE_SAMPLES"}
	return {
		"valid": true,
		"phase": "moving_ship_wake_spray" if moving else "same_scene_static_ship",
		"frame_interval_ms": frames,
		"visual_update_cpu_wall_ms": update_work,
		"peak_draw_calls": draw_calls,
		"note": "Linux renderer wall-clock frames, with Godot manual 24Hz visual simulation; not live-network gameplay or device input latency"
	}

func _profile() -> void:
	var packed: PackedScene = load("res://scenes/realistic_coastal_fx_slice.tscn")
	if packed == null:
		_fail("Missing actual moving coastal scene")
		return
	print("IOM07_SCENE_INSTANTIATE_BEGIN")
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	# The effects controller binds nodes via call_deferred in _ready(). One
	# process frame is enough for that binding; six here were expensive
	# redundant *gameplay-camera* software-render frames before selecting the
	# benchmark camera. Keep all six fixed-cinematic-camera warmup frames below.
	print("IOM07_SCENE_ATTACHED waiting_for_deferred_bind")
	await process_frame
	var fx: Node3D = scene.get_node_or_null("CoastalShipEffects")
	var ship: Node3D = scene.get_node_or_null("HarbourShipFocalPoint")
	var coast: MeshInstance3D = scene.get_node_or_null("IrregularCoastalTerrain")
	var water: MeshInstance3D = scene.get_node_or_null("ShallowToDeepWater")
	if fx == null or ship == null or coast == null or water == null or not fx.components_ready():
		_fail("Actual coastal terrain, PBR ship, ocean or VFX integration missing")
		return
	var water_material := water.material_override as ShaderMaterial
	if water_material == null or water_material.get_shader_parameter("shoremap_bound") != true:
		_fail("Coastal shader lost mesh-derived foam shoreline binding")
		return
	# Compare both phases with one fixed cinematic camera pose. A gameplay
	# camera vs cinematic camera comparison would be an invalid performance A/B.
	scene.set_cinematic_view()
	scene.set_process(false)
	fx.set_process(false)
	fx.wake.set_process(false)
	fx.bow_spray.set_process(false)
	if not scene.frame_ship_cinematic(scene.cinematic_camera, scene.cinematic_camera.global_position):
		_fail("Could not frame the complete PBR vessel for both profile phases")
		return
	var baseline_camera_transform: Transform3D = scene.cinematic_camera.global_transform
	print("IOM07_FIXED_CAMERA_WARMUP_BEGIN count=%d" % WARMUP)
	for i in range(WARMUP):
		await process_frame
		# Wait for the actual GPU/software render to finish: a process_frame
		# signal alone occurs before the draw and is not a rendered warmup.
		await RenderingServer.frame_post_draw
		print("IOM07_FIXED_CAMERA_WARMUP_RENDERED %d/%d" % [i + 1, WARMUP])
	print("IOM07_FIXED_CAMERA_READY")
	var static_stage: Dictionary = await _measure(scene, fx, false)
	if not static_stage.get("valid", false):
		_fail("Static coastal scene did not yield real frame samples")
		return
	if scene.cinematic_camera.global_transform != baseline_camera_transform:
		_fail("Baseline camera moved before coastal A/B sampling")
		return
	print("IOM07_STATIC_PHASE_COMPLETE")
	fx.start_visual_demo()
	var start_position: Vector3 = ship.position
	var moving_stage: Dictionary = await _measure(scene, fx, true)
	if not moving_stage.get("valid", false):
		_fail("Moving cinematic did not yield real frame samples")
		return
	if scene.cinematic_camera.global_transform != baseline_camera_transform:
		_fail("Cinematic camera changed between baseline and motion phases")
		return
	print("IOM07_MOVING_PHASE_COMPLETE")
	var distance: float = ship.position.distance_to(start_position)
	if distance <= 0.2 or fx.wake.get_sample_count() < 2:
		_fail("Ship or wake failed to actually animate; refusing inert-scene metrics")
		return
	fx.stop_visual_demo()
	scene.set_gameplay_view()
	await process_frame
	if not scene.gameplay_camera.current or fx._demo_active:
		_fail("Cinematic did not restore normal player camera")
		return
	var output := OS.get_environment("IOM_COAST_PROFILE_PATH")
	if output.is_empty():
		_fail("Explicit IOM_COAST_PROFILE_PATH required")
		return
	var result := {
		"schema_version": 1,
		"exact_git_sha": OS.get_environment("IOM_GIT_SHA"),
		"source_scene": "res://scenes/realistic_coastal_fx_slice.tscn",
		"source": "actual_godot_renderer",
		"godot": Engine.get_version_info().get("string", "unknown"),
		"renderer": "mobile",
		"execution_environment": "github_actions_linux_xvfb_llvmpipe",
		"physical_android_measurement": false,
		"gameplay_player_test": false,
		"graphics_reference_parity": "NOT_VERIFIED",
		"device_thermal_memory_input_latency": "NOT_MEASURED",
		"warmup_frames": WARMUP,
		"samples_each_phase": SAMPLES,
		"same_camera_fixed_pose": true,
		"camera_mode": "cinematic_ship_framed_fixed_pose",
		"ship_motion_distance_units": distance,
		"static": static_stage,
		"moving": moving_stage
	}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("Could not write frame-profile evidence")
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("IOM-07 real moving coast profile: " + output)
	scene.queue_free()
	quit(0)
